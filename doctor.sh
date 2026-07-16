#!/usr/bin/env bash
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
source "$DOTFILES/versions.env"
# shellcheck source=claude/extensions.sh
source "$DOTFILES/claude/extensions.sh"

failures=0
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; failures=$((failures + 1)); }

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1: $(command -v "$1")"
  else
    fail "$1 fehlt"
  fi
}

check_link() {
  local target="$1" expected="$2"
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$expected")" ]]; then
    ok "$target -> $expected"
  else
    fail "$target zeigt nicht auf $expected"
  fi
}

check_revision() {
  local name="$1" path="$2" expected="$3" actual
  actual="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$actual" == "$expected" ]]; then
    ok "$name: ${expected:0:12}"
  else
    fail "$name: erwartet ${expected:0:12}, gefunden ${actual:-<fehlt>}"
  fi
}

check_command git
check_command curl
check_command zsh

check_link "$HOME/.zshrc" "$DOTFILES/zsh/zshrc"
check_link "$HOME/.p10k.zsh" "$DOTFILES/zsh/p10k.zsh"

check_revision oh-my-zsh "$HOME/.oh-my-zsh" "$OH_MY_ZSH_REF"
check_revision powerlevel10k "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" "$POWERLEVEL10K_REF"
check_revision zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_REF"
check_revision zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_REF"

if claude_extensions_validate_sources "$DOTFILES/claude"; then
  ok "versionierte Claude-Erweiterungsquellen sind sicher"
else
  fail "versionierte Claude-Erweiterungsquellen sind unsicher oder ungueltig"
fi

if command -v claude >/dev/null 2>&1; then
  if claude_extensions_verify "$DOTFILES/claude" "$HOME/.claude"; then
    ok "persoenliche Claude-Erweiterungen stimmen mit den Dotfiles ueberein"
  else
    fail "persoenliche Claude-Erweiterungen fehlen, kollidieren oder weichen ab"
  fi
fi

if [[ -f /.dockerenv && -d /workspaces ]]; then
  ok "Devcontainer erkannt"

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code: $(claude --version 2>/dev/null || command -v claude)"
  else
    warn "Claude CLI nicht installiert; Claude-spezifisches Setup wird übersprungen"
  fi

  if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$HOME/.claude"; then
    ok "$HOME/.claude ist ein persistenter Mount"
  else
    warn "$HOME/.claude ist kein eigener Mount; Claude-Daten und History sind nicht rebuild-persistent"
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    warn "Docker-Daemon ist erreichbar; Claude bypassPermissions hat entsprechend große Reichweite"
  fi
else
  ok "Host-/WSL-Modus erkannt"
fi

if ((failures > 0)); then
  printf '\n%d Prüfung(en) fehlgeschlagen.\n' "$failures" >&2
  exit 1
fi

printf '\nAlle erforderlichen Prüfungen bestanden.\n'
