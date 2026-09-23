#!/usr/bin/env bash
# Read-only host preflight; never sources user shell files or starts containers.
set -uo pipefail
export PATH="${HOME:-}/.local/bin:${HOME:-}/.devcontainers/bin:$PATH"

usage() {
  cat <<'EOF'
Usage: bash check-wsl.sh [--shell-only | --voice]

Default:     WSL dotfiles and Dev Containers CLI prerequisites.
--shell-only Check only the WSL dotfiles prerequisites, without Docker/CLI.
--voice      Also require the WSLg audio socket for container voice setup.
--help       Show this help.

No installation, configuration changes, container starts or recordings.
Exit codes: 0 = required checks passed, 1 = missing/broken prerequisite,
            2 = invalid arguments or not running on a WSL host.
Warnings do not change the exit code. Network downloads, Windows microphone
permissions and prerequisites inside a future container are not tested.
EOF
}
mode=cli
if (( $# > 1 )); then usage >&2; exit 2; fi
case "${1:-}" in
  '') ;;
  --shell-only) mode=shell ;;
  --voice) mode=voice ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

failures=0
warnings=0
ok() { printf '[ok] %s\n' "$*"; }
info() { printf '[info] %s\n' "$*"; }
warn() { printf '[warn] %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '[fail] %s\n' "$*"; failures=$((failures + 1)); }
has() { command -v "$1" >/dev/null 2>&1; }
require() {
  if has "$1"; then ok "$1 vorhanden";
  else fail "$1 fehlt im aktuellen PATH. $2"; fi
}

kernel=''
if [[ -r /proc/sys/kernel/osrelease ]]; then
  IFS= read -r kernel < /proc/sys/kernel/osrelease
fi
if [[ -f /.dockerenv || -f /run/.containerenv || ${kernel,,} != *microsoft* ]]; then
  fail 'Diesen Vorabcheck auf dem WSL-Host ausführen, nicht im Container.'
  exit 2
fi
ok 'WSL-Host erkannt'
case "$(uname -m)" in
  x86_64|aarch64|arm64) ok 'Architektur für die Terminal-Tools unterstützt' ;;
  *) fail 'Terminal-Tools unterstützen nur Linux x86_64/aarch64.' ;;
esac
if [[ -n ${HOME:-} && -d $HOME && -w $HOME ]]; then
  ok 'Persönliches Home ist beschreibbar'
else
  fail 'HOME fehlt oder ist nicht beschreibbar.'
fi

for tool in git curl zsh python3; do
  require "$tool" 'Vor der Einrichtung mit dem Paketmanager bereitstellen.'
done
# Utilities used by install.sh/install-tools.sh and the bounded probes below.
for tool in sha256sum timeout mktemp install cp mv rm mkdir chmod ln readlink \
  dirname basename date cut cat cmp grep find uname; do
  if ! has "$tool"; then fail "$tool fehlt (Basiswerkzeuge der Distribution)."; fi
done
if has timeout; then
  for tool in git curl zsh python3; do
    if has "$tool" && ! timeout -k 2s 10s "$tool" --version >/dev/null 2>&1; then
      fail "$tool gefunden, aber nicht innerhalb von 10 Sekunden ausführbar."
    fi
  done
  if has python3 && ! timeout -k 2s 10s python3 -c 'import hashlib, json, shutil, zipfile' >/dev/null 2>&1; then
    fail 'Python-Standardbibliothek unvollständig; vollständiges python3-Paket der Distribution bereitstellen.'
  fi
fi

if has nano; then
  if has timeout && timeout -k 2s 10s nano --version >/dev/null 2>&1; then
    ok 'Nano kann starten'
  else
    fail 'Nano gefunden, aber Startprüfung fehlgeschlagen.'
  fi
else
  require apt-get 'Wird zum lokalen Herunterladen des fehlenden Nano benötigt.'
  require dpkg-deb 'Wird zum Entpacken von Nano im persönlichen Home benötigt.'
  warn 'Nano fehlt: Der Installer kann es lokal entpacken. APT-Paketangebot und ncurses-Laufzeitbibliotheken sind hier nicht geprüft.'
fi

# Missing tools are expected before installation; conflicting versions are not.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTFILES/versions.env"
for spec in "herdr:$HERDR_VERSION" "broot:$BROOT_VERSION"; do
  tool="${spec%%:*}"
  expected="${spec#*:}"
  if ! has "$tool"; then
    info "$tool wird durch install-tools.sh bereitgestellt."
  elif has timeout && actual="$(timeout -k 2s 10s "$tool" --version 2>/dev/null)" \
    && [[ $actual == "$tool $expected" ]]; then
    ok "$tool entspricht dem Pin $expected"
  else
    fail "$tool kann nicht starten oder weicht vom Pin $expected ab; Installer ersetzt es nicht automatisch."
  fi
done

if [[ $mode != shell ]]; then
  require docker 'Docker samt WSL-Anbindung bereitstellen.'
  require devcontainer 'Dev Containers CLI in dieser WSL-Shell bereitstellen.'
  if has timeout; then
    if has docker; then
      if timeout -k 2s 10s docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then
        ok 'Docker-Daemon über den aktuellen Docker-Kontext erreichbar'
      else
        fail 'Docker-Daemon nicht erreichbar: Docker-Start, WSL-Anbindung, Kontext und Zugriffsrechte prüfen.'
      fi
    fi
    if has devcontainer; then
      if timeout -k 2s 10s devcontainer --version >/dev/null 2>&1 &&
        cli_help="$(timeout -k 2s 10s devcontainer up --help 2>&1)" &&
        [[ $cli_help == *--no-lockfile* ]]; then
        ok 'Dev Containers CLI startet und unterstützt --no-lockfile'
      else
        fail 'Dev Containers CLI startet nicht oder unterstützt --no-lockfile nicht: PATH, Laufzeit und Version prüfen.'
      fi
    fi
  fi
  info 'VS Code muss für diesen CLI-Weg nicht laufen.'
  info 'Nach install.sh lädt eine neue WSL-zsh die portablen Funktionen dcupexec/dcuvoice. Private Definitionen haben Vorrang. Mit whence -w dcupexec dcuvoice prüfen; dieser Check lädt keine Shell-Dateien.'
fi
if [[ $mode == voice ]]; then
  if [[ -S /mnt/wslg/PulseServer ]]; then
    ok 'WSLg-PulseAudio-Socket vorhanden'
  else
    fail 'WSLg-PulseAudio-Socket fehlt: WSLg-Verfügbarkeit auf dem Host prüfen.'
  fi
  info 'Im Zielcontainer zusätzlich prüfen: WSLg-Mount, PULSE_SERVER, AUDIODRIVER, Claude Code, sox und libsox-fmt-pulse sowie sudo/apt-get für den persönlichen Voice-Helper.'
  info 'Ein vorhandener Socket beweist keine funktionierende Mikrofonaufnahme. Hier wird nichts aufgenommen.'
fi
info 'Nicht geprüft: Netzwerk/Downloads, freier Speicher, vorhandene Konfigurationskonflikte, Windows-Terminal-Font und Zustand eines Zielcontainers. Danach install.sh und doctor.sh verwenden.'
printf '\nErgebnis: %s Fehler, %s Warnungen.\n' "$failures" "$warnings"
(( failures == 0 ))
