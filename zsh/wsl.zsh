# WSL-host helpers only. Sourcing this file never starts or changes a container.
[[ -f /.dockerenv || -f /run/.containerenv ]] && return 0
[[ -r /proc/sys/kernel/osrelease ]] || return 0
[[ "${(L)$(</proc/sys/kernel/osrelease)}" == *microsoft* ]] || return 0

typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.devcontainers/bin" $path)

_dotfiles_dc_preflight() {
  emulate -L zsh
  local workspace="$1" help
  [[ -d "$workspace" ]] || { print -u2 'Projektordner existiert nicht.'; return 1; }
  (( $+commands[devcontainer] && $+commands[docker] && $+commands[timeout] )) \
    || { print -u2 'devcontainer, docker oder timeout fehlt. bootstrap-wsl.sh/check-wsl.sh verwenden.'; return 1; }
  timeout -k 2s 10s docker info >/dev/null 2>&1 \
    || { print -u2 'Docker ist nicht erreichbar.'; return 1; }
  help="$(timeout -k 2s 15s devcontainer up --help 2>&1)" || return
  [[ "$help" == *--no-lockfile* ]] \
    || { print -u2 'Diese CLI unterstützt --no-lockfile nicht. Bitte separat aktualisieren.'; return 1; }
}

_dotfiles_dc_up() {
  emulate -L zsh
  local workspace="$1"
  shift
  devcontainer up --workspace-folder "$workspace" --no-lockfile \
    --dotfiles-repository "${DOTFILES_DEVCONTAINER_REPOSITORY:-https://github.com/daviddomain/dotfiles.git}" \
    --dotfiles-target-path '~/dotfiles' --dotfiles-install-command install.sh "$@"
}

_dotfiles_dc_ready() {
  emulate -L zsh
  devcontainer exec --workspace-folder "$1" sh -lc '
    test -e "$HOME/dotfiles" && test -e "$HOME/.zshrc" &&
    test -e "$HOME/.p10k.zsh" &&
    test -e "$HOME/.oh-my-zsh/custom/themes/powerlevel10k/powerlevel10k.zsh-theme"
  ' >/dev/null 2>&1
}

_dotfiles_dc_git_auth() {
  emulate -L zsh
  devcontainer exec --workspace-folder "$1" sh -lc '
    cd "$HOME" || exit
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      gh auth setup-git >/dev/null
    fi
  '
}

_dotfiles_dc_voice_install() {
  emulate -L zsh
  devcontainer exec --workspace-folder "$1" sh -lc '
    set -eu
    cd "$HOME"
    command -v dpkg-query >/dev/null && command -v apt-get >/dev/null || {
      echo "Voice-Helper benötigt einen Debian-/Ubuntu-kompatiblen Container." >&2; exit 1;
    }
    installed="$(dpkg-query -W -f="\${Status}\n" sox libsox-fmt-pulse 2>/dev/null | grep -c "^install ok installed$" || true)"
    if [ "$installed" -ne 2 ]; then
      if [ "$(id -u)" -eq 0 ]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y sox libsox-fmt-pulse
      else
        command -v sudo >/dev/null || { echo "sudo fehlt für Voice-Pakete." >&2; exit 1; }
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y sox libsox-fmt-pulse
      fi
    fi
  '
}

# Existing local functions/aliases win; ~/.zshrc.local is also sourced afterwards.
if (( ! $+functions[dcupexec] && ! $+aliases[dcupexec] )); then
  function dcupexec {
    emulate -L zsh
    if [[ ${1:-} == --help ]]; then
      print 'dcupexec [Projektordner] [Shell] – starten/wiederverwenden und Shell öffnen.'
      return 0
    fi
    (( $# <= 2 )) || { print -u2 'Aufruf: dcupexec [Projektordner] [Shell]'; return 2; }
    local workspace="${1:-.}" shell="${2:-zsh}"
    _dotfiles_dc_preflight "$workspace" || return
    workspace="${workspace:A}"
    local -a audio=()
    if [[ -S /mnt/wslg/PulseServer ]]; then
      audio=(--mount type=bind,source=/mnt/wslg,target=/mnt/wslg
        --remote-env PULSE_SERVER=unix:/mnt/wslg/PulseServer
        --remote-env AUDIODRIVER=pulseaudio)
    fi
    _dotfiles_dc_up "$workspace" "${audio[@]}" || return
    _dotfiles_dc_git_auth "$workspace" || return
    _dotfiles_dc_ready "$workspace" || print -u2 'Shell-Dotfiles unvollständig. Persönlichen Klon und doctor.sh prüfen; eine Neuerstellung separat planen.'
    if (( ${#audio[@]} )); then
      if devcontainer exec --workspace-folder "$workspace" test -S /mnt/wslg/PulseServer >/dev/null 2>&1; then
        _dotfiles_dc_voice_install "$workspace" || return
        devcontainer exec --workspace-folder "$workspace" env \
          PULSE_SERVER=unix:/mnt/wslg/PulseServer AUDIODRIVER=pulseaudio "$shell"
        return
      fi
      print -u2 'Audio-Mount fehlt. Für Audio kann dcuvoice den Container nach Bestätigung neu erstellen.'
    fi
    devcontainer exec --workspace-folder "$workspace" "$shell"
  }
fi

if (( ! $+functions[dcuvoice] && ! $+aliases[dcuvoice] )); then
  function dcuvoice {
    emulate -L zsh
    if [[ ${1:-} == --help ]]; then
      print 'dcuvoice [Projektordner] [Shell] – Container nach Bestätigung neu erstellen, Audio einrichten und Aufnahme prüfen.'
      return 0
    fi
    (( $# <= 2 )) || { print -u2 'Aufruf: dcuvoice [Projektordner] [Shell]'; return 2; }
    local workspace="${1:-.}" shell="${2:-zsh}" answer
    [[ -S /mnt/wslg/PulseServer ]] || { print -u2 'WSLg-PulseAudio-Socket fehlt.'; return 1; }
    _dotfiles_dc_preflight "$workspace" || return
    workspace="${workspace:A}"
    print -u2 "Container für $workspace neu erstellen: Laufende Prozesse werden beendet; nicht persistente Daten können verloren gehen. Danach wird eine kurze Mikrofonaufnahme geprüft."
    [[ -t 0 ]] || { print -u2 'Nur interaktiv mit ausdrücklicher Bestätigung ausführbar.'; return 1; }
    read -r "answer?Neu erstellen und Aufnahme prüfen? [ja/NEIN] "
    [[ $answer == ja ]] || { print 'Abgebrochen; Container unverändert.'; return 0; }
    _dotfiles_dc_up "$workspace" --remove-existing-container \
      --mount type=bind,source=/mnt/wslg,target=/mnt/wslg \
      --remote-env PULSE_SERVER=unix:/mnt/wslg/PulseServer \
      --remote-env AUDIODRIVER=pulseaudio || return
    _dotfiles_dc_ready "$workspace" || { print -u2 'Dotfiles im neuen Container unvollständig.'; return 1; }
    _dotfiles_dc_git_auth "$workspace" || return
    _dotfiles_dc_voice_install "$workspace" || return
    devcontainer exec --workspace-folder "$workspace" env \
      PULSE_SERVER=unix:/mnt/wslg/PulseServer AUDIODRIVER=pulseaudio sh -lc '
        set -eu
        test -S /mnt/wslg/PulseServer
        command -v rec >/dev/null
        file="$(mktemp /tmp/dotfiles-voice.XXXXXX.wav)"
        trap '\''rm -f -- "$file"'\'' EXIT
        timeout -k 2s 5s rec -q "$file" trim 0 0.5
        test -s "$file"
      ' || return
    print 'Dotfiles und kurze SoX-Aufnahme geprüft; Claude /voice anschließend in der Container-Shell verwenden.'
    devcontainer exec --workspace-folder "$workspace" env \
      PULSE_SERVER=unix:/mnt/wslg/PulseServer AUDIODRIVER=pulseaudio "$shell"
  }
fi
