#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$DOTFILES/versions.env"

die() {
  printf '\033[1;31m[versions:error]\033[0m %s\n' "$*" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git fehlt."
[[ -f "$VERSIONS_FILE" ]] || die "$VERSIONS_FILE fehlt."

# shellcheck source=versions.env
source "$VERSIONS_FILE"

specs=(
  "OH_MY_ZSH_REF|ohmyzsh/ohmyzsh"
  "POWERLEVEL10K_REF|romkatv/powerlevel10k"
  "ZSH_AUTOSUGGESTIONS_REF|zsh-users/zsh-autosuggestions"
  "ZSH_SYNTAX_HIGHLIGHTING_REF|zsh-users/zsh-syntax-highlighting"
)

updates=0
proposals=()

printf 'Prüfe gepinnte Revisionen gegen die aktuellen Upstream-Default-Branches.\n\n'

for spec in "${specs[@]}"; do
  IFS='|' read -r variable repo <<< "$spec"
  current="${!variable:-}"
  url="https://github.com/$repo.git"

  [[ "$current" =~ ^[0-9a-f]{40}$ ]] \
    || die "$variable enthält keine vollständige Git-Revision: ${current:-<leer>}"

  if ! remote_head="$(git ls-remote --exit-code "$url" HEAD)"; then
    die "Upstream für $repo konnte nicht abgefragt werden."
  fi
  latest="${remote_head%%$'\t'*}"

  [[ "$latest" =~ ^[0-9a-f]{40}$ ]] \
    || die "Upstream für $repo lieferte keine vollständige Git-Revision."

  printf '%s\n' "$repo"
  printf '  aktuell:  %s\n' "$current"

  if [[ "$current" == "$latest" ]]; then
    printf '  Status:   aktuell\n\n'
    continue
  fi

  updates=$((updates + 1))
  proposals+=("$variable=$latest")
  printf '  Vorschlag: %s\n' "$latest"
  printf '  Vergleich: https://github.com/%s/compare/%s...%s\n\n' \
    "$repo" "$current" "$latest"
done

if ((updates == 0)); then
  printf 'Keine neuen Upstream-Revisionen gefunden. versions.env wurde nicht verändert.\n'
  exit 0
fi

printf '%d neue Upstream-Revision(en) gefunden.\n' "$updates"
printf 'Nach Prüfung der Vergleichslinks können passende Werte manuell übernommen werden:\n\n'
printf '%s\n' "${proposals[@]}"
printf '\nversions.env wurde nicht verändert.\n'
