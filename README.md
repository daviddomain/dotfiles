# Personal dotfiles

Persönliche Shell- und Claude-Code-Konfiguration für Ubuntu/WSL und die
SpielerPlus-Devcontainer. Projekt-Repositories werden dadurch nicht verändert.

## Installation

Voraussetzungen außerhalb von Debian/Ubuntu: `git`, `curl` und `zsh`.
Auf Debian/Ubuntu installiert `install.sh` fehlende Pakete über `apt-get`.

```bash
./install.sh
./doctor.sh
```

VS Code Dev Containers klont dieses Repository über die User Settings nach
`~/dotfiles` und führt denselben Befehl bei der Container-Erstellung aus.

## Verhalten

- oh-my-zsh, Powerlevel10k und beide zsh-Plugins werden auf die in
  `versions.env` festgelegten, getesteten Revisionen gesetzt.
- `~/.zshrc` und `~/.p10k.zsh` werden verlinkt. Vorhandene reguläre Dateien
  werden zuvor als zeitgestempeltes Backup gesichert.
- npm-, Node-, Docker- und sudo-Plugins sowie direnv, fzf und gh-Completion
  werden nur aktiviert, wenn die jeweilige Umgebung sie anbietet.
- Die zsh-History wird nur dann nach `~/.claude/.shell/zsh_history` umgebogen,
  wenn `~/.claude` in einem Devcontainer ein echter beschreibbarer Mount ist.
- In Devcontainern mit installierter Claude CLI wird das versionierte Fragment
  in `~/.claude/settings.json` gemergt.

## Sicherheitsrelevante Claude-Einstellungen

`claude/settings.json` aktiviert bewusst `bypassPermissions`. In den
SpielerPlus-Containern besteht zusätzlich Zugriff auf den Docker-Daemon und auf
den persistenten GitHub-Login. Der Modus ist daher funktional mit weitreichendem
Zugriff auf die lokale Entwicklungsumgebung gleichzusetzen.

Das Setzen von Onboarding- und Workspace-Trust-Flags in `~/.claude.json` nutzt
internen, nicht als stabile API dokumentierten Claude-Code-App-State. Es bleibt
für den bisherigen Komfort standardmäßig aktiv, lässt sich aber abschalten:

```bash
DOTFILES_SEED_CLAUDE_APP_STATE=0 ./install.sh
```

Bei keinem oder mehreren Verzeichnissen unter `/workspaces` wird kein
Trust-Eintrag erzeugt.

## Updates

Upstream-Revisionen in `versions.env` nur bewusst aktualisieren und danach das
Setup in WSL sowie mindestens einem Node- und einem PHP-Devcontainer testen.
