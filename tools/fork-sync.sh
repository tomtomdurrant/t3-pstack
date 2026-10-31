#!/usr/bin/env bash
# Keeps this fork on upstream's latest, and every Claude Code and Codex home on
# this fork. Safe to run at any time: a run with nothing new changes nothing.
#
#   tools/fork-sync.sh [catalog.json]
#
# catalog.json is an orchestrator_capabilities dump. With it, doctor also checks
# the model sheet against what this T3 can run.
#
# Exit 0: up to date, or updated. Exit 1: a person is needed, and the message
# says what is stuck. A merge or test failure pushes and installs nothing, so
# the machine stays on the last version that passed.
set -euo pipefail

fork=tomtomdurrant/t3-pstack
catalog=${1:-}
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

fail() {
    echo "fork-sync: $1" >&2
    osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "t3-pstack update needs you"' -e 'end run' "$1" >/dev/null 2>&1 || true
    exit 1
}

# This runs unattended, so even an unexpected failure must reach a person.
trap 'fail "unexpected failure at line $LINENO. See ~/.local/state/t3-pstack-sync/sync.log"' ERR

[[ $(git branch --show-current) == main ]] || fail "$PWD is not on main"
[[ -z $(git status --porcelain) ]] || fail "$PWD has uncommitted changes"

git fetch --quiet origin || fail "could not fetch origin"
git fetch --quiet upstream || fail "could not fetch upstream"
git merge --quiet --ff-only origin/main || fail "local main has diverged from origin/main"

before=$(git rev-parse --short HEAD)

if ! git merge-base --is-ancestor upstream/main HEAD; then
    if ! git merge --quiet --no-edit upstream/main >/dev/null; then
        files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
        git merge --abort
        fail "upstream $(git rev-parse --short upstream/main) conflicts with the fork's patch in: $files. Still on $before."
    fi
fi

undo_and_fail() {
    git reset --quiet --hard origin/main
    fail "$1 Still on $before."
}

# Only what proves the fork's patch. Upstream's CI covers the rest of its release.
bun install --frozen-lockfile >/dev/null 2>&1 || undo_and_fail "bun install failed after merging upstream."
bun tools/generate.mjs --check >/dev/null 2>&1 || undo_and_fail "the generator check failed after merging upstream."
GIT_CONFIG_GLOBAL=/dev/null bun test tests/t3-sheet.test.mjs tests/t3-sheet-values.test.mjs >/dev/null 2>&1 ||
    undo_and_fail "the validator tests failed after merging upstream."

if [[ $(git rev-parse HEAD) != $(git rev-parse origin/main) ]]; then
    git push --quiet origin main || undo_and_fail "could not push to origin."
fi

# Always run this, even with nothing new. Codex can drop its trust in the hook
# after an auto-update, and only the installer restores it.
node tools/install.mjs install --source "$fork" >/dev/null 2>&1 || fail "the installer failed. Run: node tools/install.mjs install --source $fork"

doctor=(node tools/install.mjs doctor --source "$fork")
[[ -z $catalog ]] || doctor+=(--catalog "$catalog")
if ! report=$("${doctor[@]}" 2>&1); then
    echo "$report" >&2
    fail "doctor failed after installing $(git rev-parse --short HEAD)."
fi

# The plugin managers compare version numbers, so a patch that changes without a
# new VERSION would never reach an installed copy.
version=$(<VERSION)
patched=plugins/pstack/skills/setup-pstack/scripts/t3-sheet.mjs
for home in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "${CODEX_HOME:-$HOME/.codex}"; do
    installed="$home/plugins/cache/t3-pstack/t3-pstack/$version/skills/setup-pstack/scripts/t3-sheet.mjs"
    cmp -s "$patched" "$installed" || fail "$installed does not match the fork. Remove that home's plugin cache and rerun."
done

after=$(git rev-parse --short HEAD)
if [[ $before == "$after" ]]; then
    echo "up to date: t3-pstack $version at $after, upstream $(git rev-parse --short upstream/main)"
else
    echo "updated: $before to $after, t3-pstack $version"
fi
