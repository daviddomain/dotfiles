#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }

# ── oh-my-zsh (im devcontainer meist schon da) ──
if [ ! -d "$ZSH_DIR" ]; then
  log "installiere oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ── externe Plugins & Theme ──
clone_if_missing() {
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    log "vorhanden: $(basename "$dest")"
  else
    log "clone: $(basename "$dest")"
    git clone --depth=1 "https://github.com/$repo" "$dest"
  fi
}

mkdir -p "$CUSTOM/plugins" "$CUSTOM/themes"
clone_if_missing romkatv/powerlevel10k            "$CUSTOM/themes/powerlevel10k"
clone_if_missing zsh-users/zsh-autosuggestions    "$CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing zsh-users/zsh-syntax-highlighting "$CUSTOM/plugins/zsh-syntax-highlighting"

# ── Symlinks ──
link() {
  local src="$1" dst="$2"
  [ -e "$src" ] || return 0
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    [ -L "$dst" ] || mv "$dst" "$dst.bak.$(date +%s)"
  fi
  ln -sfn "$src" "$dst"
  log "link: $dst -> $src"
}

link "$DOTFILES/zsh/zshrc"    "$HOME/.zshrc"
link "$DOTFILES/zsh/p10k.zsh" "$HOME/.p10k.zsh"

# ── Claude Code settings mergen (nur im Devcontainer) ──
if [[ -f /.dockerenv && -d "$HOME/.claude" ]]; then
  fragment="$DOTFILES/claude/settings.json"
  target="$HOME/.claude/settings.json"
  if [[ -f "$fragment" ]]; then
    [[ -f "$target" ]] || echo '{}' > "$target"
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      jq -s '.[0] * .[1]' "$target" "$fragment" > "$tmp" && mv "$tmp" "$target"
    else
      node -e '
        const fs=require("fs");
        const [t,f]=process.argv.slice(1);
        const deep=(a,b)=>{for(const k of Object.keys(b)){a[k]=(b[k]&&typeof b[k]==="object"&&!Array.isArray(b[k])&&a[k]&&typeof a[k]==="object")?deep(a[k],b[k]):b[k];}return a;};
        const base=JSON.parse(fs.readFileSync(t,"utf8")||"{}");
        const frag=JSON.parse(fs.readFileSync(f,"utf8"));
        fs.writeFileSync(t,JSON.stringify(deep(base,frag),null,2)+"\n");
      ' "$target" "$fragment"
    fi
    log "claude settings gemerged"
  fi
fi

# ── Claude Code Onboarding + Trust-Prompt überspringen (nur im Devcontainer) ──
# ~/.claude.json liegt NICHT im .claude-Volume, wird also bei jedem Rebuild neu erzeugt.
# Deshalb setzen wir die Flags bei jedem Create frisch.
if [[ -f /.dockerenv ]]; then
  ccjson="$HOME/.claude.json"
  [[ -f "$ccjson" ]] || echo '{}' > "$ccjson"

  # Workspace-Pfad zur Laufzeit bestimmen (Trust-Prompt ist projekt-spezifisch)
  workspace=""
  for d in /workspaces/*/; do
    [[ -d "$d" ]] && workspace="${d%/}" && break
  done

  if command -v jq >/dev/null 2>&1; then
    tmp="$(mktemp)"
    if [[ -n "$workspace" ]]; then
      jq --arg ws "$workspace" '
        .hasCompletedOnboarding = true
        | .projects[$ws].hasTrustDialogAccepted = true
      ' "$ccjson" > "$tmp" && mv "$tmp" "$ccjson"
    else
      jq '.hasCompletedOnboarding = true' "$ccjson" > "$tmp" && mv "$tmp" "$ccjson"
    fi
  else
    node -e '
      const fs=require("fs");
      const [p,ws]=process.argv.slice(1);
      const o=JSON.parse(fs.readFileSync(p,"utf8")||"{}");
      o.hasCompletedOnboarding=true;
      if(ws){o.projects=o.projects||{};o.projects[ws]=o.projects[ws]||{};o.projects[ws].hasTrustDialogAccepted=true;}
      fs.writeFileSync(p,JSON.stringify(o,null,2)+"\n");
    ' "$ccjson" "$workspace"
  fi
  log "claude onboarding + trust gesetzt"
fi

log "fertig"
