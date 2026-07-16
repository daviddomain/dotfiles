#!/usr/bin/env bash

# Safe deployment helpers for personal Claude Code extensions.
# The caller remains responsible for merging JSON settings fragments.

_claude_extensions_error() {
  printf '[claude-extensions:error] %s\n' "$*" >&2
  return 1
}

_claude_extensions_log() {
  if declare -F log >/dev/null 2>&1; then
    log "$*"
  else
    printf '[claude-extensions] %s\n' "$*"
  fi
}

_claude_extensions_json_valid() {
  local file="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -e . "$file" >/dev/null 2>&1
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    ' "$file" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    json.load(handle)
    ' "$file" >/dev/null 2>&1
  else
    _claude_extensions_error "JSON-Pruefung benoetigt jq, node oder python3."
  fi
}

_claude_extensions_hook_fragment_valid() {
  local file="$1"

  _claude_extensions_json_valid "$file" || return 1

  if command -v jq >/dev/null 2>&1; then
    jq -e '
      type == "object"
      and ((keys - ["hooks"]) | length == 0)
      and ((.hooks // {}) | type == "object")
    ' "$file" >/dev/null 2>&1
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const keys = Object.keys(value);
      if (!value || Array.isArray(value) || typeof value !== "object"
          || keys.some((key) => key !== "hooks")
          || (value.hooks !== undefined
              && (!value.hooks || Array.isArray(value.hooks) || typeof value.hooks !== "object"))) {
        process.exit(1);
      }
    ' "$file" >/dev/null 2>&1
  else
    python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
valid = isinstance(value, dict) and set(value).issubset({"hooks"})
valid = valid and isinstance(value.get("hooks", {}), dict)
raise SystemExit(0 if valid else 1)
    ' "$file" >/dev/null 2>&1
  fi
}

_claude_extensions_settings_fragment_valid() {
  local file="$1"

  _claude_extensions_json_valid "$file" || return 1

  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "object" and (has("hooks") | not)' "$file" >/dev/null 2>&1
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (!value || Array.isArray(value) || typeof value !== "object"
          || Object.prototype.hasOwnProperty.call(value, "hooks")) {
        process.exit(1);
      }
    ' "$file" >/dev/null 2>&1
  else
    python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle)
raise SystemExit(0 if isinstance(value, dict) and "hooks" not in value else 1)
    ' "$file" >/dev/null 2>&1
  fi
}

claude_extensions_validate_sources() {
  local repo_claude="$1" path rel name secret_file private_match

  [[ -d "$repo_claude" ]] || {
    _claude_extensions_error "Claude-Konfigurationsverzeichnis fehlt: $repo_claude"
    return 1
  }

  for name in find sort sha256sum tar cp mv ln readlink mkdir chmod; do
    command -v "$name" >/dev/null 2>&1 || {
      _claude_extensions_error "Erforderliches Programm fehlt: $name"
      return 1
    }
  done

  while IFS= read -r -d '' path; do
    rel="${path#"$repo_claude"/}"
    name="${path##*/}"

    [[ ! -L "$path" ]] || {
      _claude_extensions_error "Symlinks innerhalb der versionierten Claude-Quellen sind nicht erlaubt: $rel"
      return 1
    }

    case "$rel" in
      README.md|settings.json|hooks.json|extensions.sh|validate.sh|skills|skills/*|agents|agents/*|rules|rules/*|hooks|hooks/*) ;;
      *)
        _claude_extensions_error "Nicht freigegebener Pfad unter claude/: $rel"
        return 1
        ;;
    esac

    case "/$rel/" in
      */projects/*|*/session-env/*|*/shell-snapshots/*|*/file-history/*|*/transcripts/*|*/plugins/*|*/cache/*|*/debug/*|*/telemetry/*)
        _claude_extensions_error "Runtime-Verzeichnis darf nicht versioniert werden: $rel"
        return 1
        ;;
    esac

    case "$name" in
      .credentials.json|credentials.json|history.jsonl|stats-cache.json|.claude.json|*.jsonl|*.log|*.sqlite|*.sqlite3|*.db|*.pem|*.key)
        _claude_extensions_error "Runtime- oder Credential-Datei darf nicht versioniert werden: $rel"
        return 1
        ;;
    esac
  done < <(find "$repo_claude" -mindepth 1 -print0 | sort -z)

  if [[ -f "$repo_claude/settings.json" ]] && ! _claude_extensions_settings_fragment_valid "$repo_claude/settings.json"; then
    _claude_extensions_error "settings.json muss gueltiges JSON sein und darf keine Hooks enthalten."
    return 1
  fi

  if [[ -f "$repo_claude/hooks.json" ]] && ! _claude_extensions_hook_fragment_valid "$repo_claude/hooks.json"; then
    _claude_extensions_error "hooks.json darf nur ein gueltiges hooks-Objekt enthalten."
    return 1
  fi

  if [[ -d "$repo_claude/skills" ]]; then
    while IFS= read -r -d '' path; do
      name="${path##*/}"
      [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
        _claude_extensions_error "Ungueltiger Skill-Name: $name"
        return 1
      }
      [[ -d "$path" && -f "$path/SKILL.md" ]] || {
        _claude_extensions_error "Jeder Skill benoetigt ein Verzeichnis mit SKILL.md: $name"
        return 1
      }
    done < <(find "$repo_claude/skills" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  fi

  for name in agents rules; do
    if [[ -d "$repo_claude/$name" ]]; then
      if find "$repo_claude/$name" -type f ! -name '*.md' -print -quit | grep -q .; then
        _claude_extensions_error "Unter claude/$name sind nur Markdown-Dateien erlaubt."
        return 1
      fi
    fi
  done

  for name in skills agents rules hooks; do
    [[ -d "$repo_claude/$name" ]] || continue
    while IFS= read -r -d '' path; do
      rel="${path##*/}"
      [[ "$rel" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
        _claude_extensions_error "Ungueltiger Eintragsname unter claude/$name: $rel"
        return 1
      }
    done < <(find "$repo_claude/$name" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  secret_file="$(grep -RIlE --binary-files=without-match \
    'sk-ant-[[:alnum:]_-]{20,}|gh[pousr]_[[:alnum:]]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' \
    "$repo_claude" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$secret_file" ]]; then
    _claude_extensions_error "Moegliches Secret gefunden: ${secret_file#"$repo_claude"/}"
    return 1
  fi

  private_match="${DOTFILES_CLAUDE_PRIVATE_DENY_FILE:-}"
  if [[ -n "$private_match" ]]; then
    [[ -f "$private_match" ]] || {
      _claude_extensions_error "Private Deny-Datei fehlt: $private_match"
      return 1
    }
    secret_file="$(grep -RIlEf "$private_match" "$repo_claude" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$secret_file" ]]; then
      _claude_extensions_error "Privates Ausschlussmuster getroffen: ${secret_file#"$repo_claude"/}"
      return 1
    fi
  fi
}

_claude_extensions_hash_path() {
  local path="$1"

  if [[ -f "$path" ]]; then
    sha256sum "$path" | awk '{print $1}'
  elif [[ -d "$path" ]]; then
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner --format=gnu \
      -cf - -C "$path" . 2>/dev/null | sha256sum | awk '{print $1}'
  else
    return 1
  fi
}

_claude_extensions_copy_state_file() {
  local target_claude="$1" category="$2" name="$3"
  printf '%s/.dotfiles-managed/copies/%s/%s.sha256\n' "$target_claude" "$category" "$name"
}

_claude_extensions_preflight_copy() {
  local source="$1" target="$2" state_file="$3" source_hash target_hash previous_hash

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi
  [[ ! -L "$target" ]] || {
    _claude_extensions_error "Bestehender Symlink kollidiert mit verwalteter Kopie: $target"
    return 1
  }

  source_hash="$(_claude_extensions_hash_path "$source")" || return 1
  target_hash="$(_claude_extensions_hash_path "$target")" || {
    _claude_extensions_error "Zieltyp ist nicht verwaltbar: $target"
    return 1
  }

  [[ "$target_hash" == "$source_hash" ]] && return 0

  previous_hash=""
  [[ -f "$state_file" ]] && read -r previous_hash < "$state_file"
  if [[ -n "$previous_hash" && "$target_hash" == "$previous_hash" ]]; then
    return 0
  fi

  _claude_extensions_error "Bestehender persoenlicher Inhalt bleibt unveraendert; Konflikt bei $target"
}

_claude_extensions_preflight_link() {
  local source="$1" target="$2"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi
  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
    return 0
  fi

  _claude_extensions_error "Bestehender persoenlicher Inhalt bleibt unveraendert; Konflikt bei $target"
}

_claude_extensions_check_hook_json() {
  local mode="$1" target="$2" fragment="$3" previous="$4"

  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const [mode, targetPath, fragmentPath, previousPath] = process.argv.slice(1);
      const read = (path) => path && fs.existsSync(path)
        ? JSON.parse(fs.readFileSync(path, "utf8") || "{}") : {};
      const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
      const target = read(targetPath);
      const fragment = read(fragmentPath);
      const previous = read(previousPath);
      const currentHooks = target.hooks && typeof target.hooks === "object" ? target.hooks : {};
      const nextHooks = fragment.hooks && typeof fragment.hooks === "object" ? fragment.hooks : {};
      const previousHooks = previous.hooks && typeof previous.hooks === "object" ? previous.hooks : {};
      const conflicts = [];
      for (const [event, nextValue] of Object.entries(nextHooks)) {
        if (!(event in currentHooks) || equal(currentHooks[event], nextValue)) continue;
        if (mode === "preflight" && event in previousHooks
            && equal(currentHooks[event], previousHooks[event])) continue;
        conflicts.push(event);
      }
      if (conflicts.length) {
        process.stderr.write(`Hook-Konflikt: ${conflicts.join(", ")}\n`);
        process.exit(1);
      }
    ' "$mode" "$target" "$fragment" "$previous"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, os, sys
mode, target_path, fragment_path, previous_path = sys.argv[1:]
def read(path):
    if not path or not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)
target = read(target_path)
fragment = read(fragment_path)
previous = read(previous_path)
current_hooks = target.get("hooks") if isinstance(target.get("hooks"), dict) else {}
next_hooks = fragment.get("hooks") if isinstance(fragment.get("hooks"), dict) else {}
previous_hooks = previous.get("hooks") if isinstance(previous.get("hooks"), dict) else {}
conflicts = []
for event, value in next_hooks.items():
    if event not in current_hooks or current_hooks[event] == value:
        continue
    if mode == "preflight" and event in previous_hooks and current_hooks[event] == previous_hooks[event]:
        continue
    conflicts.append(event)
if conflicts:
    print("Hook-Konflikt: " + ", ".join(conflicts), file=sys.stderr)
    raise SystemExit(1)
    ' "$mode" "$target" "$fragment" "$previous"
  elif command -v jq >/dev/null 2>&1; then
    local target_json='{}' fragment_json previous_json='{}'
    [[ -f "$target" ]] && target_json="$(<"$target")"
    fragment_json="$(<"$fragment")"
    [[ -f "$previous" ]] && previous_json="$(<"$previous")"
    jq -e -n \
      --arg mode "$mode" \
      --argjson target "$target_json" \
      --argjson fragment "$fragment_json" \
      --argjson previous "$previous_json" '
        ($target.hooks // {}) as $current
        | ($fragment.hooks // {}) as $next
        | ($previous.hooks // {}) as $old
        | [($next | to_entries[]) as $entry | select(
            ($current | has($entry.key))
            and ($current[$entry.key] != $entry.value)
            and (($mode != "preflight")
              or (($old | has($entry.key) | not) or $current[$entry.key] != $old[$entry.key]))
          ) | $entry.key]
        | length == 0
      ' >/dev/null
  else
    _claude_extensions_error "Hook-Konfliktpruefung benoetigt node, python3 oder jq."
  fi
}

claude_extensions_preflight() {
  local repo_claude="$1" target_claude="$2" category source name target target_root state_file

  claude_extensions_validate_sources "$repo_claude" || return 1

  for target_root in \
    "$target_claude/.dotfiles-managed" \
    "$target_claude/.dotfiles-backups"; do
    if [[ -L "$target_root" || ( -e "$target_root" && ! -d "$target_root" ) ]]; then
      _claude_extensions_error "Unsicheres verwaltetes Ziel: $target_root"
      return 1
    fi
  done

  for category in skills agents; do
    [[ -d "$repo_claude/$category" ]] || continue
    target_root="$target_claude/$category"
    if [[ -L "$target_root" || ( -e "$target_root" && ! -d "$target_root" ) ]]; then
      _claude_extensions_error "Kategorie-Ziel muss ein echtes Verzeichnis sein: $target_root"
      return 1
    fi
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      target="$target_claude/$category/$name"
      state_file="$(_claude_extensions_copy_state_file "$target_claude" "$category" "$name")"
      _claude_extensions_preflight_copy "$source" "$target" "$state_file" || return 1
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  for category in rules hooks; do
    [[ -d "$repo_claude/$category" ]] || continue
    target_root="$target_claude/$category"
    if [[ -L "$target_root" || ( -e "$target_root" && ! -d "$target_root" ) ]]; then
      _claude_extensions_error "Kategorie-Ziel muss ein echtes Verzeichnis sein: $target_root"
      return 1
    fi
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      _claude_extensions_preflight_link "$source" "$target_claude/$category/$name" || return 1
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  if [[ -f "$repo_claude/hooks.json" ]]; then
    if [[ -L "$target_claude/settings.json" ]]; then
      _claude_extensions_error "Hook-Merge ersetzt keine verlinkte settings.json."
      return 1
    fi
    _claude_extensions_check_hook_json \
      preflight \
      "$target_claude/settings.json" \
      "$repo_claude/hooks.json" \
      "$target_claude/.dotfiles-managed/hooks-fragment.json" || return 1
  fi
}

_claude_extensions_record_copy_state() {
  local source="$1" state_file="$2" state_dir tmp source_hash
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"
  source_hash="$(_claude_extensions_hash_path "$source")" || return 1
  tmp="$state_file.tmp.$$"
  (umask 077 && printf '%s\n' "$source_hash" > "$tmp") || return 1
  mv -f "$tmp" "$state_file"
}

_claude_extensions_install_copy() {
  local source="$1" target="$2" state_file="$3" category="$4" name="$5" target_claude="$6"
  local source_hash target_hash='' target_root tmp backup_root backup

  source_hash="$(_claude_extensions_hash_path "$source")" || return 1
  if [[ -e "$target" && ! -L "$target" ]]; then
    target_hash="$(_claude_extensions_hash_path "$target")" || return 1
  fi

  if [[ "$target_hash" == "$source_hash" ]]; then
    _claude_extensions_record_copy_state "$source" "$state_file"
    _claude_extensions_log "claude $category unveraendert: $name"
    return 0
  fi

  target_root="$(dirname "$target")"
  mkdir -p "$target_root"
  tmp="$target_root/.${name}.dotfiles-new.$$"
  [[ ! -e "$tmp" && ! -L "$tmp" ]] || {
    _claude_extensions_error "Temporaeres Ziel existiert bereits: $tmp"
    return 1
  }

  if ! cp -a "$source" "$tmp"; then
    rm -rf -- "$tmp"
    _claude_extensions_error "Kopieren fehlgeschlagen: $source"
    return 1
  fi

  backup=""
  if [[ -e "$target" || -L "$target" ]]; then
    backup_root="$target_claude/.dotfiles-backups/$category"
    mkdir -p "$backup_root"
    backup="$backup_root/$name.$(date +%Y%m%d%H%M%S).$$"
    mv "$target" "$backup" || {
      rm -rf -- "$tmp"
      return 1
    }
    _claude_extensions_log "backup: $target -> $backup"
  fi

  if ! mv "$tmp" "$target"; then
    [[ -n "$backup" ]] && mv "$backup" "$target"
    rm -rf -- "$tmp"
    return 1
  fi

  _claude_extensions_record_copy_state "$source" "$state_file"
  _claude_extensions_log "claude $category kopiert: $name"
}

_claude_extensions_install_link() {
  local source="$1" target="$2" category="$3" name="$4"
  mkdir -p "$(dirname "$target")"

  if [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
    _claude_extensions_log "claude $category link vorhanden: $name"
    return 0
  fi

  ln -s "$source" "$target"
  _claude_extensions_log "claude $category verlinkt: $name"
}

claude_extensions_install() {
  local repo_claude="$1" target_claude="$2" category source name target state_file

  claude_extensions_preflight "$repo_claude" "$target_claude" || return 1
  mkdir -p "$target_claude"

  for category in skills agents; do
    [[ -d "$repo_claude/$category" ]] || continue
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      target="$target_claude/$category/$name"
      state_file="$(_claude_extensions_copy_state_file "$target_claude" "$category" "$name")"
      _claude_extensions_install_copy \
        "$source" "$target" "$state_file" "$category" "$name" "$target_claude" || return 1
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  for category in rules hooks; do
    [[ -d "$repo_claude/$category" ]] || continue
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      _claude_extensions_install_link "$source" "$target_claude/$category/$name" "$category" "$name" || return 1
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done
}

claude_extensions_record_hook_fragment() {
  local fragment="$1" target_claude="$2" state_dir state_file tmp
  state_dir="$target_claude/.dotfiles-managed"
  state_file="$state_dir/hooks-fragment.json"
  tmp="$state_file.tmp.$$"
  mkdir -p "$state_dir"
  (umask 077 && cp "$fragment" "$tmp") || return 1
  chmod 600 "$tmp"
  mv -f "$tmp" "$state_file"
}

claude_extensions_verify() {
  local repo_claude="$1" target_claude="$2" category source name target state_file source_hash target_hash

  claude_extensions_validate_sources "$repo_claude" || return 1

  for category in skills agents; do
    [[ -d "$repo_claude/$category" ]] || continue
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      target="$target_claude/$category/$name"
      state_file="$(_claude_extensions_copy_state_file "$target_claude" "$category" "$name")"
      [[ -e "$target" && ! -L "$target" && -f "$state_file" ]] || {
        _claude_extensions_error "Verwaltete Kopie oder Status fehlt: $target"
        return 1
      }
      source_hash="$(_claude_extensions_hash_path "$source")" || return 1
      target_hash="$(_claude_extensions_hash_path "$target")" || return 1
      [[ "$source_hash" == "$target_hash" ]] || {
        _claude_extensions_error "Verwaltete Kopie weicht ab: $target"
        return 1
      }
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  for category in rules hooks; do
    [[ -d "$repo_claude/$category" ]] || continue
    while IFS= read -r -d '' source; do
      name="${source##*/}"
      target="$target_claude/$category/$name"
      [[ -L "$target" && "$(readlink -f "$target")" == "$(readlink -f "$source")" ]] || {
        _claude_extensions_error "Erwarteter Symlink fehlt oder weicht ab: $target"
        return 1
      }
    done < <(find "$repo_claude/$category" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  done

  if [[ -f "$repo_claude/hooks.json" ]]; then
    _claude_extensions_check_hook_json \
      verify \
      "$target_claude/settings.json" \
      "$repo_claude/hooks.json" \
      "$target_claude/.dotfiles-managed/hooks-fragment.json" || return 1
  fi
}
