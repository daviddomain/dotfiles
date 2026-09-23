#!/usr/bin/env bash
# Prepare an existing Ubuntu WSL. Dotfiles installation remains a separate step.
set -euo pipefail
usage() {
  cat <<'EOF'
Aufruf: bash bootstrap-wsl.sh [--plan] [--yes] [--shell-only]
  --plan        Nur Plan anzeigen, nichts installieren.
  --yes         Dem angezeigten Installationsumfang vorab zustimmen.
  --shell-only  Nur WSL-Basispakete, keine Dev Containers CLI.

Ohne --yes wird vor Änderungen nachgefragt. Unterstützt Ubuntu auf WSL2
als normaler Benutzer mit sudo. Windows/WSL und Docker Desktop separat
einrichten. Es werden keine Container gestartet und keine Dotfiles installiert.
EOF
}
plan=0; yes=0; shell_only=0
for arg in "$@"; do
  case "$arg" in
    --plan) plan=1 ;; --yes) yes=1 ;; --shell-only) shell_only=1 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
die() { printf '[bootstrap:error] %s\n' "$*" >&2; exit 1; }
kernel=''; IFS= read -r kernel < /proc/sys/kernel/osrelease
[[ ! -f /.dockerenv && ! -f /run/.containerenv && ${kernel,,} == *microsoft* && ${kernel,,} == *wsl2* ]] \
  || die 'Auf dem WSL2-Host ausführen, nicht im Container.'
source /etc/os-release
[[ $ID == ubuntu ]] || die 'Dieser Bootstrap unterstützt Ubuntu; andere Distributionen bitte separat einrichten.'
[[ $EUID != 0 && -d $HOME && -w $HOME ]] || die 'Als normaler Benutzer mit beschreibbarem Home starten, nicht mit sudo bash.'
command -v sudo >/dev/null || die 'sudo fehlt. Zuerst einen normalen Ubuntu-Benutzer mit sudo-Rechten einrichten.'
case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) die 'Nur x86_64/aarch64 werden unterstützt.' ;; esac
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$HOME/.devcontainers/bin:$PATH"
missing=()
for package in git curl ca-certificates zsh python3 coreutils nano tar xz-utils diffutils findutils grep; do
  if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
    missing+=("$package")
  fi
done
printf '[bootstrap] Fehlende Ubuntu-Pakete: %s\n' "${missing[*]:-(keine)}"
if (( ! shell_only )); then
  if command -v devcontainer >/dev/null 2>&1; then
    printf '[bootstrap] Vorhandene CLI prüfen und erhalten: %s\n' "$(command -v devcontainer)"
  else
    printf '[bootstrap] Gepinnte Dev Containers CLI samt Node unter ~/.local/share/dotfiles-devcontainer-cli installieren; Launcher unter ~/.local/bin.\n'
  fi
fi
printf '[bootstrap] Docker, Shell-Profile, Claude-Anmeldung und Projektdateien werden nicht verändert.\n'
(( ! plan )) || exit 0
if (( ! yes )); then
  [[ -t 0 ]] || die 'Keine interaktive Eingabe. Plan prüfen und für unbeaufsichtigte Installation ausdrücklich --yes verwenden.'
  read -r -p 'Diesen Installationsumfang ausführen? [j/N] ' answer
  [[ $answer == j || $answer == J || $answer == ja ]] || { printf 'Abgebrochen, nichts verändert.\n'; exit 0; }
fi
if (( ${#missing[@]} )); then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi
if (( ! shell_only )); then bash "$DOTFILES/install-cli.sh"; fi
printf '\n[bootstrap] Voraussetzungen eingerichtet. Es folgt der rein lesende Vorabcheck.\n'
check_args=(); (( ! shell_only )) || check_args=(--shell-only)
if ! bash "$DOTFILES/check-wsl.sh" "${check_args[@]}"; then
  printf '[bootstrap] Offene Voraussetzungen oben beheben (z.B. Docker Desktop starten/WSL-Anbindung aktivieren); danach erneut prüfen.\n' >&2
  exit 1
fi
printf '\n[bootstrap] Als nächste Schritte im persönlichen Klon: bash install.sh, bash doctor.sh, danach eine neue zsh öffnen.\n'
