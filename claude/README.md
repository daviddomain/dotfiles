# Portable Claude Code extensions

This directory contains only declarative, public-safe personal configuration.
Runtime data from `~/.claude` is never copied back into this repository.

Supported source layout:

```text
claude/
├── settings.json          # Devcontainer-only personal settings fragment
├── hooks.json             # optional user-level hook registrations only
├── skills/<name>/SKILL.md
├── agents/<name>.md
├── rules/<name>.md
└── hooks/<name>/...
```

The installer uses a conservative hybrid strategy:

- skills and agents are copied because not every supported Claude Code version
  reliably discovers them through symlinks;
- rules and hook scripts are linked one entry at a time;
- an existing unrelated target is treated as a conflict and is never replaced;
- managed copies use local hashes under `~/.claude/.dotfiles-managed` so a
  locally edited copy cannot be overwritten silently;
- updated managed copies are backed up under `~/.claude/.dotfiles-backups`;
- `hooks.json` is merged only after checking existing hook events for conflicts.

Once every target environment runs Claude Code 2.1.203 or later, individual
skill directories can be reconsidered for symlink deployment after explicit
cross-environment testing. Agents remain copied until their symlink behavior is
documented and verified.

Run the public-safety check before reviewing a commit:

```bash
bash claude/validate.sh
```

For an additional private list of forbidden internal terms, provide a local
grep pattern file that is not part of this repository:

```bash
DOTFILES_CLAUDE_PRIVATE_DENY_FILE=~/.config/dotfiles/claude-private-deny.txt \
  bash claude/validate.sh
```

The automated check rejects known credential and runtime paths plus common
high-confidence secret formats. It does not replace reviewing the complete diff
for internal names, URLs, infrastructure details, or project-specific content.
