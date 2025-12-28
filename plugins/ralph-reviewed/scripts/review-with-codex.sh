#!/usr/bin/env bash
#
# Standalone script for Codex review.
# Can be used for testing or as an alternative to the TypeScript implementation.
#
# Environment variables:
#   ORIGINAL_PROMPT - The original task description
#   WORK_SUMMARY    - Summary of work done
#   GIT_DIFF        - Code changes (diff)
#   REVIEW_COUNT    - Current review attempt (0-indexed)
#   MAX_REVIEWS     - Maximum allowed reviews
#
# Output:
#   "APPROVE"              - Work approved
#   "REJECT: <feedback>"   - Work rejected with feedback
#
# Exit codes:
#   0 - Success (check stdout for result)
#   1 - Error (defaults to approve)
#

set -euo pipefail

# Defaults
ORIGINAL_PROMPT="${ORIGINAL_PROMPT:-No task provided}"
WORK_SUMMARY="${WORK_SUMMARY:-No summary available}"
GIT_DIFF="${GIT_DIFF:-(no changes)}"
REVIEW_COUNT="${REVIEW_COUNT:-0}"
MAX_REVIEWS="${MAX_REVIEWS:-3}"

# Check for codex
if ! command -v codex &> /dev/null; then
    echo "APPROVE"
    exit 0
fi

# Build review prompt
PROMPT=$(cat <<EOF
# Code Review Request

You are reviewing work completed by Claude in an iterative development loop.

## Original Task
${ORIGINAL_PROMPT}

## Work Summary
${WORK_SUMMARY}

## Code Changes
\`\`\`diff
${GIT_DIFF}
\`\`\`

## Review Guidelines
- Focus on: functional correctness, obvious bugs, missing requirements
- Ignore: style preferences, minor improvements, documentation nits
- Be practical: if it works and meets requirements, approve it
- This is review $((REVIEW_COUNT + 1)) of ${MAX_REVIEWS} maximum

## Your Decision
Output exactly one of:
- \`<review>APPROVE</review>\` - Work meets requirements, ship it
- \`<review>REJECT: your specific feedback here</review>\` - Needs changes

If rejecting, be specific and actionable. Focus on 1-2 critical issues only.
EOF
)

# Call Codex with timeout
RESPONSE=$(timeout 60 codex -q "${PROMPT}" 2>/dev/null || echo "<review>APPROVE</review>")

# Parse response
if echo "${RESPONSE}" | grep -q '<review>APPROVE</review>'; then
    echo "APPROVE"
    exit 0
fi

# Try to extract rejection feedback
FEEDBACK=$(echo "${RESPONSE}" | grep -oP '(?<=<review>REJECT:\s).*(?=</review>)' || true)
if [[ -n "${FEEDBACK}" ]]; then
    echo "REJECT: ${FEEDBACK}"
    exit 0
fi

# Fallback - unclear response
echo "APPROVE"
exit 0
