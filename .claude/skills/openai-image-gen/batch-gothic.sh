#!/bin/bash

# Batch generate all Gothic cathedral assets for 0xbigboss.github.io
# Run from within your project's public/images directory

set -e

SCRIPT_DIR="$(dirname "$0")"
GEN="$SCRIPT_DIR/generate.sh"

echo "=== Gothic Cathedral Asset Generator ==="
echo "This will generate multiple images using DALL-E 3"
echo "Estimated cost: ~$1.00-1.50"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

mkdir -p backgrounds heroes windows decorative

echo ""
echo "=== Generating Backgrounds ==="

"$GEN" "Dark cathedral stone wall texture, seamless tileable pattern, deep charcoal gray with subtle purple undertones, weathered medieval masonry, dramatic shadows between stones, gothic architecture, 4k texture, dark moody atmosphere, no visible mortar lines" backgrounds/stone-texture.png 1024x1024

"$GEN" "Gothic cathedral ribbed vault ceiling view from below, deep blue-black with gold leaf accent lines on ribs, dramatic perspective, medieval architecture, dim candlelit glow, ornate stone carvings fading into darkness, atmospheric fog, 4k wallpaper" backgrounds/vault-ceiling.png 1792x1024 hd

echo ""
echo "=== Generating Hero Images ==="

"$GEN" "Divine light rays streaming through gothic cathedral rose window, deep purple and blue stained glass, golden light beams cutting through darkness, dust particles floating in light, medieval stone interior, dramatic chiaroscuro, cinematic lighting, 4k, no people" heroes/home.png 1792x1024 hd

"$GEN" "Medieval craftsman's workshop, golden tools on dark wood workbench, gothic arched window in background with blue light, warm candlelight illuminating workspace, scrolls and blueprints scattered, brass instruments and gears, artisan craftsmanship aesthetic, dramatic shadows, cinematic still life, no people" heroes/projects.png 1792x1024 hd

"$GEN" "Ancient scriptorium desk with illuminated manuscript open, quill pen resting in gold ink pot, gothic window casting blue light, leather-bound journals stacked neatly, medieval monastery aesthetic, dramatic rim lighting, warm golden candlelight contrasting cool window light, no people" heroes/posts.png 1792x1024 hd

"$GEN" "Gothic cathedral door slightly ajar with divine golden light streaming through the crack, ornate wrought iron hinges and handles, intricately carved stone archway frame with gothic tracery, welcoming yet mysterious atmosphere, invitation to enter, dramatic cinematic lighting, medieval aesthetic" heroes/contact.png 1792x1024 hd

echo ""
echo "=== Generating Stained Glass Windows ==="

"$GEN" "Gothic stained glass window design, geometric sacred pattern, deep purple and blue glass pieces with gold leading lines, hammer and gear symbols representing craftsmanship, backlit with divine golden rays, ornate pointed arch frame, isolated on pure black background, digital art illustration" windows/projects.png 1024x1024 hd

"$GEN" "Gothic stained glass window design, open book and quill pen symbols in center, deep blue and purple glass with intricate gold leading, medieval manuscript aesthetic, soft backlit glow, pointed gothic arch frame, ornate tracery pattern surrounding, isolated on pure black background, digital art" windows/posts.png 1024x1024 hd

"$GEN" "Gothic stained glass window design, white dove and reaching hand symbols representing connection, deep purple and gold glass pieces, divine light streaming through, pointed gothic arch frame, ornate geometric leading pattern, isolated on pure black background, digital art illustration" windows/contact.png 1024x1024 hd

echo ""
echo "=== Generating Decorative Elements ==="

"$GEN" "Medieval illuminated manuscript style monogram combining letters A and E intertwined, ornate gold leaf with deep blue and purple accents, flourishes and Celtic knotwork borders, gothic calligraphy style, intricate hand-drawn detail, pure black background, luxury heraldic aesthetic, logo design" decorative/monogram-ae.png 1024x1024 hd

"$GEN" "Medieval ornate horizontal divider bar, intricate gold filigree scrollwork on pure black background, gothic pattern with symmetrical design, thin elegant line with central diamond medallion, Celtic knotwork accents on ends, digital art, isolated decorative element, PNG style" decorative/divider.png 1792x1024

"$GEN" "Volumetric divine light rays streaming from top of frame downward, god rays with floating dust particles, warm golden light on pure black background, cathedral window lighting effect, subtle and ethereal atmosphere, overlay texture, digital art" decorative/light-rays.png 1792x1024

echo ""
echo "=== Complete! ==="
echo ""
echo "Generated assets:"
find . -name "*.png" -newer "$0" 2>/dev/null | sort
echo ""
echo "Total images: $(find . -name "*.png" -newer "$0" 2>/dev/null | wc -l | tr -d ' ')"
