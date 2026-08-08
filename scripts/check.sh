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
    | grep -v "^\./${SEAM}:" \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' || true)

if [ -n "$STRAY" ]; then
    echo "$STRAY" | sed 's/^/  /'
    FAILED=1
else
    echo "  OK: no stray C_* references"
fi

echo ""
echo "== Roll starters outside seam (must stay commented until step 8) =="
ROLL_STRAY=$(grep -rn -E 'RollAbilities|RerollAbilities|StartRapidRolling|ContinueRapidRolling|CancelRapidRolling' . \
    --include='*.lua' \
    | grep -v "^\./${SEAM}:" \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*--' || true)

if [ -n "$ROLL_STRAY" ]; then
    echo "$ROLL_STRAY" | sed 's/^/  /'
    FAILED=1
else
    echo "  OK: no live roll starter calls"
fi

echo ""
if [ -f tests/test_load.lua ]; then
    echo "== test_load.lua =="
    if lua5.1 tests/test_load.lua; then
        echo "  OK: test_load.lua"
    else
        echo "  FAIL: test_load.lua"
        FAILED=1
    fi
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "FAILED" >&2
    exit 1
fi
echo "OK: all checks passed"
