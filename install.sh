#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

# shellcheck source=versions.env
source "$DOTFILES/versions.env"
# shellcheck source=claude/extensions.sh
source "$DOTFILES/claude/extensions.sh"

log()  { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[dotfiles:warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[dotfiles:error]\033[0m %s\n' "$*" >&2; exit 1; }

is_devcontainer() {
  [[ -f /.dockerenv && -d /workspaces ]]
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "Für die Paketinstallation fehlen Root-Rechte bzw. sudo."
  fi
}

ensure_prerequisites() {
  local -a missing=()
  local command_name

  for command_name in git curl zsh; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done

  ((${#missing[@]} == 0)) && return 0

  if command -v apt-get >/dev/null 2>&1; then
    log "installiere fehlende Pakete: ${missing[*]}"
    run_as_root apt-get update
    run_as_root apt-get install -y --no-install-recommends "${missing[@]}"
  else
    die "Fehlende Programme: ${missing[*]}. Bitte mit dem Paketmanager des Systems installieren."
  fi
}

repo_url_matches() {
  local actual="$1" repo="$2"
  case "$actual" in
    "https://github.com/$repo"|"https://github.com/$repo.git"|"git@github.com:$repo"|"git@github.com:$repo.git") return 0 ;;
    *) return 1 ;;
  esac
}

sync_repo() {
  local repo="$1" dest="$2" ref="$3" expected_file="$4"
  local origin current

  if [[ -e "$dest" && ! -d "$dest/.git" ]]; then
    die "$dest existiert, ist aber kein Git-Repository."
  fi

  if [[ ! -d "$dest/.git" ]]; then
    log "clone: $(basename "$dest")"
    mkdir -p "$(dirname "$dest")"
    git init --quiet "$dest"
    git -C "$dest" remote add origin "https://github.com/$repo.git"
  fi

  origin="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
  repo_url_matches "$origin" "$repo" || die "Unerwartetes origin für $dest: ${origin:-<fehlt>}"

  if [[ -n "$(git -C "$dest" status --porcelain --untracked-files=normal)" ]]; then
    die "$dest enthält lokale Änderungen. Bitte zuerst prüfen und sichern."
  fi

  current="$(git -C "$dest" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$current" != "$ref" ]]; then
    log "setze $(basename "$dest") auf ${ref:0:12}"
    git -C "$dest" fetch --quiet --depth=1 origin "$ref"
    git -C "$dest" checkout --quiet --detach FETCH_HEAD
  else
    log "gepinnt: $(basename "$dest") (${ref:0:12})"
  fi

  [[ -e "$dest/$expected_file" ]] || die "Unvollständige Installation: $dest/$expected_file fehlt."
}

link_file() {
  local src="$1" dst="$2" backup
  [[ -e "$src" ]] || die "Quelle fehlt: $src"

  if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    log "link vorhanden: $dst"
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    backup="$dst.bak.$(date +%Y%m%d%H%M%S).$$"
    mv "$dst" "$backup"
    log "backup: $dst -> $backup"
  fi

  ln -s "$src" "$dst"
  log "link: $dst -> $src"
}

prepare_json_target() {
  local target="$1"
  mkdir -p "$(dirname "$target")"
  if [[ ! -f "$target" ]]; then
    (umask 077 && printf '{}\n' > "$target")
  fi
}

merge_json() {
  local target="$1" fragment="$2" tmp
  prepare_json_target "$target"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e . "$target" >/dev/null || ! jq -e . "$fragment" >/dev/null; then
      rm -f "$tmp"
      die "Ungültiges JSON in $target oder $fragment."
    fi
    if ! jq -s '.[0] * .[1]' "$target" "$fragment" > "$tmp"; then
      rm -f "$tmp"
      die "JSON-Merge für $target fehlgeschlagen."
    fi
  elif command -v node >/dev/null 2>&1; then
    if ! node -e '
      const fs = require("fs");
      const [target, fragment] = process.argv.slice(1);
      const deepMerge = (base, overlay) => {
        for (const [key, value] of Object.entries(overlay)) {
          base[key] = value && typeof value === "object" && !Array.isArray(value)
            && base[key] && typeof base[key] === "object" && !Array.isArray(base[key])
            ? deepMerge(base[key], value)
            : value;
        }
        return base;
      };
      const base = JSON.parse(fs.readFileSync(target, "utf8") || "{}");
      const overlay = JSON.parse(fs.readFileSync(fragment, "utf8"));
      process.stdout.write(JSON.stringify(deepMerge(base, overlay), null, 2) + "\n");
    ' "$target" "$fragment" > "$tmp"; then
      rm -f "$tmp"
      die "JSON-Merge für $target fehlgeschlagen."
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 -c '
import json, sys
target, fragment = sys.argv[1:]
def merge(base, overlay):
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key] = merge(base[key], value)
        else:
            base[key] = value
    return base
with open(target, encoding="utf-8") as handle:
    base = json.load(handle)
with open(fragment, encoding="utf-8") as handle:
    overlay = json.load(handle)
print(json.dumps(merge(base, overlay), indent=2))
    ' "$target" "$fragment" > "$tmp"; then
      rm -f "$tmp"
      die "JSON-Merge für $target fehlgeschlagen."
    fi
  else
    rm -f "$tmp"
    die "Claude-Settings benötigen jq, node oder python3 zum sicheren JSON-Merge."
  fi

  chmod --reference="$target" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  mv -f "$tmp" "$target"
}

detect_single_workspace() {
  local -a workspaces=()
  local workspace

  for workspace in /workspaces/*; do
    [[ -d "$workspace" ]] && workspaces+=("$workspace")
  done

  ((${#workspaces[@]} == 1)) || return 1
  printf '%s\n' "${workspaces[0]}"
}

update_claude_app_state() {
  local target="$1" seed_onboarding="$2" seed_trust="$3" workspace="${4:-}" tmp
  if [[ "$seed_trust" == "1" && -z "$workspace" ]]; then
    die "Workspace-Trust benötigt einen eindeutig erkannten Workspace."
  fi
  prepare_json_target "$target"
  tmp="$(mktemp "${target}.tmp.XXXXXX")"

  if command -v jq >/dev/null 2>&1; then
    if ! jq -e . "$target" >/dev/null; then
      rm -f "$tmp"
      die "Ungültiges JSON in $target."
    fi
    if ! jq \
      --arg workspace "$workspace" \
      --arg seed_onboarding "$seed_onboarding" \
      --arg seed_trust "$seed_trust" '
        if $seed_onboarding == "1" then
          .hasCompletedOnboarding = true
        else . end
        | if $seed_trust == "1" then
          .projects[$workspace].hasTrustDialogAccepted = true
        else . end
      ' "$target" > "$tmp"; then
      rm -f "$tmp"
      die "Claude-App-State konnte nicht aktualisiert werden."
    fi
  elif command -v node >/dev/null 2>&1; then
    if ! node -e '
      const fs = require("fs");
      const [target, seedOnboarding, seedTrust, workspace] = process.argv.slice(1);
      const state = JSON.parse(fs.readFileSync(target, "utf8") || "{}");
      if (seedOnboarding === "1") state.hasCompletedOnboarding = true;
      if (seedTrust === "1") {
        state.projects ||= {};
        state.projects[workspace] ||= {};
        state.projects[workspace].hasTrustDialogAccepted = true;
      }
      process.stdout.write(JSON.stringify(state, null, 2) + "\n");
    ' "$target" "$seed_onboarding" "$seed_trust" "$workspace" > "$tmp"; then
      rm -f "$tmp"
      die "Claude-App-State konnte nicht aktualisiert werden."
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 -c '
import json, sys
target, seed_onboarding, seed_trust, workspace = sys.argv[1:]
with open(target, encoding="utf-8") as handle:
    state = json.load(handle)
if seed_onboarding == "1":
    state["hasCompletedOnboarding"] = True
if seed_trust == "1":
    state.setdefault("projects", {}).setdefault(workspace, {})["hasTrustDialogAccepted"] = True
print(json.dumps(state, indent=2))
    ' "$target" "$seed_onboarding" "$seed_trust" "$workspace" > "$tmp"; then
      rm -f "$tmp"
      die "Claude-App-State konnte nicht aktualisiert werden."
    fi
  else
    rm -f "$tmp"
    die "Claude-App-State benötigt jq, node oder python3."
  fi

  chmod --reference="$target" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  mv -f "$tmp" "$target"
}

ensure_prerequisites

sync_repo ohmyzsh/ohmyzsh "$ZSH_DIR" "$OH_MY_ZSH_REF" oh-my-zsh.sh
mkdir -p "$CUSTOM/plugins" "$CUSTOM/themes"
sync_repo romkatv/powerlevel10k "$CUSTOM/themes/powerlevel10k" "$POWERLEVEL10K_REF" powerlevel10k.zsh-theme
sync_repo zsh-users/zsh-autosuggestions "$CUSTOM/plugins/zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_REF" zsh-autosuggestions.zsh
sync_repo zsh-users/zsh-syntax-highlighting "$CUSTOM/plugins/zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_REF" zsh-syntax-highlighting.zsh

link_file "$DOTFILES/zsh/zshrc" "$HOME/.zshrc"
link_file "$DOTFILES/zsh/p10k.zsh" "$HOME/.p10k.zsh"

if command -v claude >/dev/null 2>&1; then
  if ! claude_extensions_preflight "$DOTFILES/claude" "$HOME/.claude"; then
    die "Claude-Erweiterungen enthalten Konflikte oder unsichere Quellen."
  fi

  mkdir -p "$HOME/.claude"
  claude_extensions_install "$DOTFILES/claude" "$HOME/.claude" \
    || die "Claude-Erweiterungen konnten nicht installiert werden."

  if is_devcontainer; then
    if [[ -f "$DOTFILES/claude/settings.json" ]]; then
      merge_json "$HOME/.claude/settings.json" "$DOTFILES/claude/settings.json"
      log "claude settings gemerged"
    fi

    # ~/.claude.json ist interner Claude-Code-App-State, keine stabile Settings-API.
    # Onboarding und Workspace-Trust bleiben deshalb ohne ausdrückliches Opt-in unverändert.
    seed_onboarding="${DOTFILES_SEED_CLAUDE_ONBOARDING:-0}"
    accept_workspace_trust="${DOTFILES_ACCEPT_CLAUDE_WORKSPACE_TRUST:-0}"

    case "$seed_onboarding" in
      0|1) ;;
      *) die "DOTFILES_SEED_CLAUDE_ONBOARDING muss 0 oder 1 sein." ;;
    esac
    case "$accept_workspace_trust" in
      0|1) ;;
      *) die "DOTFILES_ACCEPT_CLAUDE_WORKSPACE_TRUST muss 0 oder 1 sein." ;;
    esac

    if [[ -n "${DOTFILES_SEED_CLAUDE_APP_STATE+x}" ]]; then
      warn "DOTFILES_SEED_CLAUDE_APP_STATE ist veraltet und wird ignoriert; nutze die getrennten Opt-ins."
    fi

    workspace=""
    if [[ "$accept_workspace_trust" == "1" ]]; then
      workspace="$(detect_single_workspace || true)"
      if [[ -z "$workspace" ]]; then
        warn "Workspace-Trust ausdrücklich angefordert, aber Workspace nicht eindeutig; Trust bleibt unverändert."
        accept_workspace_trust=0
      fi
    fi

    if [[ "$seed_onboarding" == "1" || "$accept_workspace_trust" == "1" ]]; then
      update_claude_app_state \
        "$HOME/.claude.json" \
        "$seed_onboarding" \
        "$accept_workspace_trust" \
        "$workspace"
      if [[ "$seed_onboarding" == "1" ]]; then
        log "claude onboarding ausdrücklich gesetzt"
      fi
      if [[ "$accept_workspace_trust" == "1" ]]; then
        log "claude workspace-trust ausdrücklich für $workspace gesetzt"
      fi
    else
      log "claude app-state unverändert (kein Opt-in aktiviert)"
    fi
  fi

  if [[ -f "$DOTFILES/claude/hooks.json" ]]; then
    merge_json "$HOME/.claude/settings.json" "$DOTFILES/claude/hooks.json"
    claude_extensions_record_hook_fragment "$DOTFILES/claude/hooks.json" "$HOME/.claude" \
      || die "Hook-Status konnte nicht gespeichert werden."
    log "claude hooks konfliktfrei gemerged"
  fi
fi

log "fertig"
