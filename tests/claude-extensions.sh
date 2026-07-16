#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../claude/extensions.sh
source "$ROOT/claude/extensions.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo/claude"
target="$tmp/home/.claude"

mkdir -p "$repo/skills/sample" "$repo/agents" "$repo/rules" "$repo/hooks"
printf '%s\n' '---' 'description: Neutral test skill.' '---' 'Test.' > "$repo/skills/sample/SKILL.md"
printf '%s\n' '---' 'name: reviewer' 'description: Neutral test agent.' '---' 'Test.' > "$repo/agents/reviewer.md"
printf '%s\n' '# Preferences' '- Test only.' > "$repo/rules/preferences.md"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$repo/hooks/check.sh"

claude_extensions_validate_sources "$repo"
claude_extensions_preflight "$repo" "$target"
claude_extensions_install "$repo" "$target"
claude_extensions_verify "$repo" "$target"

[[ -f "$target/skills/sample/SKILL.md" && ! -L "$target/skills/sample" ]]
[[ -f "$target/agents/reviewer.md" && ! -L "$target/agents/reviewer.md" ]]
[[ -L "$target/rules/preferences.md" ]]
[[ -L "$target/hooks/check.sh" ]]

claude_extensions_install "$repo" "$target"
claude_extensions_verify "$repo" "$target"

printf '%s\n' 'local edit' >> "$target/skills/sample/SKILL.md"
if claude_extensions_preflight "$repo" "$target" >/dev/null 2>&1; then
  printf 'Konfliktpruefung hat eine lokale Aenderung uebersehen.\n' >&2
  exit 1
fi

cp "$repo/skills/sample/SKILL.md" "$target/skills/sample/SKILL.md"
printf '%s\n' 'Updated.' >> "$repo/skills/sample/SKILL.md"
claude_extensions_preflight "$repo" "$target"
claude_extensions_install "$repo" "$target"
claude_extensions_verify "$repo" "$target"
grep -q 'Updated.' "$target/skills/sample/SKILL.md"
find "$target/.dotfiles-backups/skills" -type d -name 'sample.*' -print -quit | grep -q .

printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/check.sh"}]}]}}' \
  > "$repo/hooks.json"
claude_extensions_preflight "$repo" "$target"
cp "$repo/hooks.json" "$target/settings.json"
claude_extensions_record_hook_fragment "$repo/hooks.json" "$target"
claude_extensions_verify "$repo" "$target"

printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"exit 0"}]}]}}' \
  > "$target/settings.json"
if claude_extensions_preflight "$repo" "$target" >/dev/null 2>&1; then
  printf 'Hook-Konfliktpruefung hat einen fremden Hook uebersehen.\n' >&2
  exit 1
fi

cp "$target/.dotfiles-managed/hooks-fragment.json" "$target/settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash|Edit","hooks":[{"type":"command","command":"$HOME/.claude/hooks/check.sh"}]}]}}' \
  > "$repo/hooks.json"
claude_extensions_preflight "$repo" "$target"

printf '%s\n' 'not public runtime data' > "$repo/history.jsonl"
if claude_extensions_validate_sources "$repo" >/dev/null 2>&1; then
  printf 'Runtime-Dateipruefung hat history.jsonl uebersehen.\n' >&2
  exit 1
fi
rm "$repo/history.jsonl"

printf 'Claude extension deployment tests passed.\n'
