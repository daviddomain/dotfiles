#!/usr/bin/env bash
# Personal Linux CLI with its own Node runtime; no npm, sudo or profile edits.
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DOTFILES/versions.env"
export PATH="$HOME/.local/bin:$HOME/.devcontainers/bin:$PATH"
die() { printf '[cli:error] %s\n' "$*" >&2; exit 1; }
[[ $# == 0 ]] || die 'Aufruf: bash install-cli.sh (keine Optionen).'
for tool in curl sha256sum tar xz timeout; do
  command -v "$tool" >/dev/null || die "$tool fehlt. Zuerst bootstrap-wsl.sh verwenden."
done
[[ $(uname -s) == Linux ]] || die 'Nur Linux wird unterstützt.'
case "$(uname -m)" in
  x86_64) arch=x64; node_sha="$DEVCONTAINER_NODE_X64_SHA256" ;;
  aarch64|arm64) arch=arm64; node_sha="$DEVCONTAINER_NODE_ARM64_SHA256" ;;
  *) die 'Nur x86_64/aarch64 werden unterstützt.' ;;
esac

check_cli() {
  local help
  timeout -k 2s 15s "$1" --version >/dev/null 2>&1 || return
  help="$(timeout -k 2s 15s "$1" up --help 2>&1)" || return
  [[ $help == *--no-lockfile* ]]
}
if command -v devcontainer >/dev/null 2>&1; then
  check_cli "$(command -v devcontainer)" || die 'Vorhandene CLI defekt oder ohne --no-lockfile; bleibt unverändert. Bitte gesondert prüfen.'
  printf '[cli] Vorhandene funktionsfähige CLI bleibt erhalten: %s\n' "$(command -v devcontainer)"
  exit 0
fi

root="$HOME/.local/share/dotfiles-devcontainer-cli"
target="$root/cli-$DEVCONTAINER_CLI_VERSION-node-$DEVCONTAINER_NODE_VERSION-$arch"
wrapper="$HOME/.local/bin/devcontainer"
[[ ! -e $wrapper && ! -L $wrapper ]] || die "Ziel bereits belegt: $wrapper"
mkdir -p "$root" "$HOME/.local/bin"
scratch="$(mktemp -d "$root/.install.XXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
download() {
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 \
    --max-time 300 "$1" -o "$scratch/$3"
  printf '%s  %s\n' "$2" "$scratch/$3" | sha256sum --check --status \
    || die "Prüfsumme stimmt nicht: $3"
}
if [[ -e $target || -L $target ]]; then
  die "Installationsziel existiert bereits ohne nutzbaren Launcher: $target. Bleibt zur manuellen Prüfung erhalten."
fi
download "https://nodejs.org/dist/v$DEVCONTAINER_NODE_VERSION/node-v$DEVCONTAINER_NODE_VERSION-linux-$arch.tar.xz" "$node_sha" node.tar.xz
download "https://registry.npmjs.org/@devcontainers/cli/-/cli-$DEVCONTAINER_CLI_VERSION.tgz" "$DEVCONTAINER_CLI_SHA256" cli.tgz
mkdir "$scratch/payload" "$scratch/payload/node" "$scratch/payload/cli" "$scratch/payload/bin"
tar -xJf "$scratch/node.tar.xz" -C "$scratch/payload/node" --strip-components=1 --no-same-owner
tar -xzf "$scratch/cli.tgz" -C "$scratch/payload/cli" --strip-components=1 --no-same-owner
cat > "$scratch/payload/bin/devcontainer" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
root="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
exec "$root/node/bin/node" "$root/cli/devcontainer.js" "$@"
WRAPPER
chmod 755 "$scratch/payload/bin/devcontainer"
[[ $(timeout -k 2s 15s "$scratch/payload/node/bin/node" --version) == "v$DEVCONTAINER_NODE_VERSION" ]] || die 'Node startet nicht mit der erwarteten Version.'
[[ $(timeout -k 2s 15s "$scratch/payload/bin/devcontainer" --version) == "$DEVCONTAINER_CLI_VERSION" ]] || die 'CLI startet nicht mit der erwarteten Version.'
check_cli "$scratch/payload/bin/devcontainer" || die 'CLI unterstützt --no-lockfile nicht.'
mv -T "$scratch/payload" "$target"
ln -s "$target/bin/devcontainer" "$wrapper"
printf '[cli] Installiert: CLI %s mit Node %s im persönlichen Home.\n' "$DEVCONTAINER_CLI_VERSION" "$DEVCONTAINER_NODE_VERSION"
