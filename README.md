# Personal dotfiles

Persönliche Shell- und Claude-Code-Konfiguration für Ubuntu/WSL und
teamverwaltete Devcontainer. Projekt-Repositories werden dadurch nicht verändert.

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

`claude/settings.json` setzt `acceptEdits` als persönlichen Standard. Claude Code
darf damit Dateien im Arbeitsverzeichnis sowie übliche Dateisystemoperationen
ohne einzelne Bestätigung ausführen. Andere Shell-, Netzwerk- und
Infrastrukturaktionen durchlaufen weiterhin die Berechtigungsprüfung.

Für eine bewusst autonom gestartete Sitzung kann bei unterstütztem Konto,
Provider und Modell der Auto-Modus verwendet werden:

```bash
CLAUDE_CODE_ENABLE_AUTO_MODE=1 claude --permission-mode auto
```

Der Auto-Modus prüft Aktionen mit einem separaten Sicherheitsklassifikator,
garantiert aber keine Sicherheit. `bypassPermissions` bleibt ausschließlich ein
expliziter Ausnahmefall:

```bash
claude --permission-mode bypassPermissions
```

Dieser Modus überspringt nahezu alle Berechtigungs- und Sicherheitsprüfungen.
Er ist insbesondere ungeeignet, wenn der Container auf persistente Credentials,
schreibbare Host-Mounts, den Docker-Daemon oder ein unbeschränktes Netzwerk
zugreifen kann. Deshalb gibt es dafür bewusst keinen Alias.

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
Setup in WSL sowie in repräsentativen Devcontainern testen.
