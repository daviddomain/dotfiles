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
- Persoenliche Skills und Agents werden konfliktgeschuetzt kopiert; Rules und
  Hook-Skripte werden pro Eintrag nach `~/.claude` verlinkt. Bestehende fremde
  Inhalte werden dabei niemals automatisch ersetzt.

## Portable Claude-Erweiterungen

Die optionale Struktur unter `claude/skills`, `claude/agents`, `claude/rules`
und `claude/hooks` ist die oeffentliche Single Source of Truth. Da die aktuell
unterstuetzten Claude-Code-Versionen Symlinks nicht fuer jeden Erweiterungstyp
garantieren, verwendet `install.sh` bewusst ein Hybridverfahren. Verwaltete
Kopien erhalten lokale Pruefsummen; lokale Abweichungen fuehren zu einem
Konflikt statt zu einem stillen Ueberschreiben.

Hook-Registrierungen koennen separat in `claude/hooks.json` liegen. Dieses
Fragment darf ausschliesslich den `hooks`-Schluessel enthalten und wird nur
gemergt, wenn bestehende Hook-Ereignisse nicht kollidieren. Details und die
oeffentliche Sicherheitspruefung stehen in [claude/README.md](claude/README.md).

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
internen, nicht als stabile API dokumentierten Claude-Code-App-State. Der
Installer verändert diesen State deshalb standardmäßig nicht. Beide
Automatisierungen lassen sich getrennt und ausdrücklich aktivieren:

```bash
# Nur Welcome-/Onboarding-Dialog überspringen
DOTFILES_SEED_CLAUDE_ONBOARDING=1 ./install.sh

# Workspace-Trust für genau einen erkannten Workspace automatisch akzeptieren
DOTFILES_ACCEPT_CLAUDE_WORKSPACE_TRUST=1 ./install.sh
```

Workspace-Trust sollte normalerweise im Claude-Dialog bewusst bestätigt
werden. Das zweite Opt-in ist nur für einen bereits geprüften Workspace
gedacht. Bei keinem oder mehreren Verzeichnissen unter `/workspaces` wird auch
mit Opt-in kein Trust-Eintrag erzeugt. Beide Opt-ins können bei Bedarf in einem
Aufruf kombiniert werden.

## Updates

Die Upstream-Repositories bleiben über vollständige Commit-SHAs in
`versions.env` reproduzierbar gepinnt. Einmal monatlich sowie anlassbezogen bei
Sicherheits-, Kompatibilitäts- oder Fehlerkorrekturen nach neuen Revisionen
suchen:

```bash
./check-versions.sh
```

Der Befehl fragt nur die aktuellen Commits der jeweiligen
Upstream-Default-Branches ab. Er zeigt Abweichungen, Vergleichslinks und mögliche
neue Werte an, verändert aber weder `versions.env` noch installierte
Komponenten.

Neue Revisionen kontrolliert übernehmen:

1. Die verlinkten Upstream-Änderungen und gegebenenfalls Release Notes prüfen.
2. Nur bewusst ausgewählte, vollständige Commit-SHAs manuell in `versions.env`
   eintragen und den Diff kontrollieren.
3. Vor Container-Tests den Working Tree des verwendeten Projekt-Repositories
   prüfen. Dort keine Dateien oder Git-Einstellungen verändern.
4. In WSL sowie je einem repräsentativen Node- und PHP-Devcontainer jeweils
   `./install.sh` zweimal und danach `./doctor.sh` ausführen.
5. Nach den Tests erneut bestätigen, dass die untersuchten Projekt-Repositories
   unverändert sind. Erst dann die Dotfiles-Änderung committen und veröffentlichen.

Eine gefundene Revision ist nur ein Prüf-Kandidat. Sie wird erst nach Sichtung
der Änderungen und erfolgreichen Tests zur neuen bekannten guten Revision.
