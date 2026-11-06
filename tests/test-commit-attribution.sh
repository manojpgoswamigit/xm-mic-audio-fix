#!/usr/bin/env bash
# =============================================================================
#  Commit attribution hooks: .githooks/commit-msg, pre-push, check-attribution
# =============================================================================
#  Proves, in a throwaway repository, that:
#    * commit messages, authors and committers naming an AI tool are refused
#    * ordinary words that merely contain a tool name still pass
#    * pre-push catches commits and tags that skipped the commit hook
#
#  No network, no changes to this repository.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
check="$repo_root/.githooks/check-attribution"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xm-attribution-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---- the checker on its own ------------------------------------------------
for bad in \
    "Co-Authored-By: Claude Opus <noreply@anthropic.com>" \
    "Generated with Codex" "written with Gemini" "via GitHub Copilot" \
    "opencode session" "Cline did this" "DeepSeek-V3" "ChatGPT" "GPT-4o" \
    "Cursor Agent <cursoragent@cursor.com>" "Windsurf" "aider" "Qwen" \
    "Grok" "AI-generated" "with help from an LLM" "Roo Code" "Kilo Code"
do
    printf '%s\n' "$bad" | "$check" --text t 2>/dev/null && fail "not caught: '$bad'"
done

for ok in \
    "fix: decline the mic when Music is active" "aim the slider at 54%" \
    "move the mouse cursor over the handle" "said, contained, maintain" \
    "Merge branch 'main'" "partition table is GPT" "Manoj Goswami <manoj@example.com>"
do
    printf '%s\n' "$ok" | "$check" --text t 2>/dev/null || fail "false positive: '$ok'"
done

# ---- hooks in a throwaway repo ---------------------------------------------
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git init -q --bare "$tmp/remote.git"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config user.name "Dev Person"
git config user.email "dev@example.com"
git config core.hooksPath "$repo_root/.githooks"
git remote add origin "$tmp/remote.git"

commit() { git commit -q --allow-empty "$@" >/dev/null 2>"$tmp/err"; }

commit -m "feat: clean commit" || fail "clean commit refused: $(cat "$tmp/err")"

commit -m "feat: x" -m "Co-Authored-By: Claude <noreply@anthropic.com>" \
    && fail "commit-msg let a Co-Authored-By trailer through"
grep -q "commit message" "$tmp/err" || fail "no explanation: $(cat "$tmp/err")"

commit -m "fix: thing" --author "Codex <codex@openai.com>" \
    && fail "commit-msg let an AI author through"

GIT_COMMITTER_NAME="Gemini" commit -m "fix: thing" \
    && fail "commit-msg let an AI committer through"

# A comment line (as in the editor template) does not count.
printf 'fix: real subject\n# Claude was here\n' > "$tmp/msg"
commit -F "$tmp/msg" --cleanup=strip || fail "comment line counted: $(cat "$tmp/err")"

git push -q origin main 2>"$tmp/err" || fail "clean push refused: $(cat "$tmp/err")"

# --no-verify skips commit-msg, but pre-push still refuses it.
commit --no-verify -m "chore: bump" -m "Generated with DeepSeek" || fail "--no-verify commit"
git push -q origin main 2>"$tmp/err" && fail "pre-push let a skipped commit through"
grep -q "Push refused" "$tmp/err" || fail "no push explanation: $(cat "$tmp/err")"
git reset -q --hard HEAD~1

# New branch: only commits the remote lacks are checked (all clean here).
git switch -q -c feature
commit -m "feat: branch work"
git push -q origin feature 2>"$tmp/err" || fail "clean new branch refused: $(cat "$tmp/err")"

# Annotated tags are checked too.
git tag -a v1 -m "release made with Cline"
git push -q origin v1 2>"$tmp/err" && fail "pre-push let an AI tag message through"
git tag -d v1 >/dev/null
git tag -a v1 -m "xm v1"
git push -q origin v1 2>"$tmp/err" || fail "clean tag refused: $(cat "$tmp/err")"

# ---- this repository's own history is clean ---------------------------------
cd "$repo_root"
"$check" --commits HEAD 2>"$tmp/err" || fail "repository history: $(cat "$tmp/err")"

echo "PASS: AI-tool mentions blocked in messages, authors, committers, pushes and tags; ordinary words allowed"
