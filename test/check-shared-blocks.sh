#!/usr/bin/env bash
# Guards the deliberate duplication between this repo's install.sh and
# miniclosedai's. Both carry a byte-identical `ask-bootstrap` block (Node
# bootstrap + npm install + fallback + verification) and an identical
# prompt(). They're copied rather than fetched from a shared URL on purpose
# — see the block's own header comment — which means nothing but a check
# like this stops them drifting apart silently.
#
# Opt-in: takes the sibling miniclosedai checkout as $1 (default ../miniclosedai)
# and skips cleanly when it isn't there, since CI only ever has one repo.
#
#   ./test/check-shared-blocks.sh [path/to/miniclosedai]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIBLING="${1:-$HERE/../miniclosedai}"

if [ ! -f "$SIBLING/install.sh" ]; then
    echo "· no miniclosedai checkout at $SIBLING — skipping shared-block check"
    exit 0
fi

# Two extraction modes, because the two shared regions are delimited
# differently: the bootstrap block by literal comment markers, prompt() by a
# function definition whose end is a regex (`^}`). awk's index() is a literal
# substring search, so it cannot express the latter.
extract_literal() {
    awk -v b="$2" -v e="$3" '
        index($0, b) { inblock = 1 }
        inblock      { print }
        index($0, e) { inblock = 0 }
    ' "$1"
}
extract_regex() { sed -n "/$2/,/$3/p" "$1"; }

FAIL=0
compare() {
    local label="$1" mode="$2" begin="$3" end="$4"
    local a b
    a="$("extract_$mode" "$HERE/install.sh" "$begin" "$end")"
    b="$("extract_$mode" "$SIBLING/install.sh" "$begin" "$end")"
    if [ -z "$a" ] || [ -z "$b" ]; then
        printf '✗ %s: block missing from one of the two installers\n' "$label"
        FAIL=1
        return
    fi
    if [ "$a" = "$b" ]; then
        printf '✓ %s: identical in both installers (%s lines)\n' "$label" "$(printf '%s\n' "$a" | wc -l | tr -d ' ')"
    else
        printf '✗ %s: DRIFTED — diff follows\n' "$label"
        diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | sed 's/^/    /' || true
        FAIL=1
    fi
}

compare "ask-bootstrap" literal "BEGIN shared block: ask-bootstrap" "END shared block: ask-bootstrap"
compare "prompt()"      regex   "^prompt() {"                      "^}"

# The two installers write the same EDS_TUI_* names into the same two rc
# files and each strips the other's lines by name prefix. A name present in
# one list but not the other gets duplicated on re-run, or deleted out from
# under the other product — so the lists have to match exactly.
strip_list() { grep -oE "\^export \(EDS_TUI_[A-Z_|]+\)=" "$1" | head -1; }
A_LIST="$(strip_list "$HERE/install.sh" || true)"
B_LIST="$(strip_list "$SIBLING/install.sh" || true)"
if [ -n "$A_LIST" ] && [ "$A_LIST" = "$B_LIST" ]; then
    printf '✓ EDS_TUI_* strip lists match\n'
else
    printf '✗ EDS_TUI_* strip lists differ:\n    node: %s\n    app:  %s\n' "$A_LIST" "$B_LIST"
    FAIL=1
fi

exit "$FAIL"
