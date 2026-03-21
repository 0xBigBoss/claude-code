#!/usr/bin/env bash
# Reset test environment and run QA suite for ralph-reviewed plugin
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="/tmp/ralph-test"

# Reset test repo
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
git init -q
echo '# test' > README.md
git add -A && git commit -q -m "init"

cat > math.ts <<'EOF'
// TODO: implement add, subtract, multiply, divide
export function add(a: number, b: number): number {
  return 0; // broken
}

export function divide(a: number, b: number): number {
  return a / b; // no zero check
}
EOF
git add -A && git commit -q -m "add broken math module"

echo "test repo ready at $TEST_DIR"

# Start claude with QA prompt
exec claude --plugin-dir "$PLUGIN_DIR" "Read $PLUGIN_DIR/QA.md and execute the full QA suite. Report any bugs, edge cases, or unexpected behavior."
