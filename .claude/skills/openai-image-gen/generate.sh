#!/bin/bash

# OpenAI DALL-E 3 Image Generation Script
# Usage: generate.sh "prompt" output.png [size] [quality]

set -e

PROMPT="$1"
OUTPUT="$2"
SIZE="${3:-1024x1024}"
QUALITY="${4:-standard}"

if [ -z "$PROMPT" ] || [ -z "$OUTPUT" ]; then
    echo "Usage: generate.sh \"prompt\" output.png [size] [quality]"
    echo ""
    echo "Sizes: 1024x1024 (default), 1792x1024, 1024x1792"
    echo "Quality: standard (default), hd"
    exit 1
fi

if [ -z "$OPENAI_API_KEY" ]; then
    echo "Error: OPENAI_API_KEY environment variable not set"
    exit 1
fi

echo "Generating image..."
echo "  Prompt: ${PROMPT:0:80}..."
echo "  Size: $SIZE"
echo "  Quality: $QUALITY"
echo "  Output: $OUTPUT"

# Call OpenAI API
RESPONSE=$(curl -s https://api.openai.com/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d "{
    \"model\": \"dall-e-3\",
    \"prompt\": $(echo "$PROMPT" | jq -Rs .),
    \"n\": 1,
    \"size\": \"$SIZE\",
    \"quality\": \"$QUALITY\",
    \"response_format\": \"url\"
  }")

# Check for errors
ERROR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [ -n "$ERROR" ]; then
    echo "Error: $ERROR"
    exit 1
fi

# Extract URL and download
IMAGE_URL=$(echo "$RESPONSE" | jq -r '.data[0].url')
REVISED_PROMPT=$(echo "$RESPONSE" | jq -r '.data[0].revised_prompt // empty')

if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" = "null" ]; then
    echo "Error: No image URL in response"
    echo "$RESPONSE"
    exit 1
fi

echo "Downloading image..."
curl -s "$IMAGE_URL" -o "$OUTPUT"

echo "Done! Saved to: $OUTPUT"
if [ -n "$REVISED_PROMPT" ]; then
    echo ""
    echo "DALL-E revised prompt:"
    echo "  $REVISED_PROMPT"
fi
