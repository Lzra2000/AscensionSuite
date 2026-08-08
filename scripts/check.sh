#!/usr/bin/env sh
# AscensionSuite local checks: Lua 5.1 compile + C_* seam scan.
#
#   sh scripts/check.sh
set -eu
cd "$(dirname "$0")/.."

FAILED=0

echo "== Lua syntax (luac5.1 -p) =="
while IFS= read -r file; do
    if ! luac5.1 -p "$file" >/dev/null 2>&1; then
        echo "  FAIL: $file"
        FAILED=1
    else
        echo "  OK:   $file"
    fi
done <<EOF
$(find . -name '*.lua' ! -path './.git/*' ! -path './dist/*' | sort)
EOF

echo ""
echo "== C_* outside integration/AscensionAPI.lua =="
SEAM="integration/AscensionAPI.lua"
STRAY=$(grep -rn -E '\bC_[A-Za-z]+[.:]' . --include='*.lua' \
    --exclude-dir=dist --exclude-dir=.git \
    | grep -v "^\./${SEAM}:" \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' || true)

if [ -n "$STRAY" ]; then
    echo "$STRAY" | sed 's/^/  /'
    FAILED=1
else
    echo "  OK: no stray C_* references"
fi

echo ""
echo "== Roll starters outside seam (only integration/AscensionAPI.lua) =="
ROLL_STRAY=$(grep -rn -E '\b(RollAbilities|RerollAbilities|StartRapidRolling|ContinueRapidRolling|CancelRapidRolling)\s*\(' . \
    --include='*.lua' \
    --exclude-dir=dist --exclude-dir=.git \
    | grep -v "^\./${SEAM}:" \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' || true)

if [ -n "$ROLL_STRAY" ]; then
    echo "$ROLL_STRAY" | sed 's/^/  /'
    FAILED=1
else
    echo "  OK: roll starters confined to seam"
fi

echo ""
echo "== tests =="
RAN=0
for test in tests/test_*.lua; do
    [ -f "$test" ] || continue
    RAN=$((RAN + 1))
    if lua5.1 "$test"; then
        echo "  OK:   $test"
    else
        echo "  FAIL: $test"
        FAILED=1
    fi
done

if [ "$RAN" -eq 0 ]; then
    echo "  FAIL: no tests found in tests/"
    FAILED=1
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "FAILED" >&2
    exit 1
fi
echo "OK: all checks passed"
