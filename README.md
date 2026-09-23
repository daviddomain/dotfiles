# Personal dotfiles

Persönliche Shell- und Claude-Code-Konfiguration für Ubuntu/WSL und
teamverwaltete Devcontainer. Projekt-Repositories werden dadurch nicht verändert.

## Einstieg auf einem neuen Windows-/WSL-Rechner

Zuerst Windows-seitig WSL2 mit Ubuntu und einen normalen Linux-Benutzer mit
`sudo` einrichten. Für Devcontainer zusätzlich Docker Desktop starten und die
WSL-Anbindung für diese Ubuntu-Distribution aktivieren. Der Bootstrap installiert
weder WSL noch Docker Desktop und ändert keine Docker-Zugriffsrechte.

Falls selbst Git fehlt, in der Ubuntu-Shell zunächst den Zugang zum öffentlichen
Repository bereitstellen (GitHub-Anmeldung ist dafür nicht erforderlich):

```bash
sudo apt-get update
sudo apt-get install -y git ca-certificates
git clone https://github.com/daviddomain/dotfiles.git ~/dotfiles
cd ~/dotfiles
bash ./bootstrap-wsl.sh --plan
bash ./bootstrap-wsl.sh
```

Einen bereits vorhandenen Zielordner vorher prüfen; nicht überschreiben.
`bootstrap-wsl.sh` unterstützt Ubuntu auf WSL2 (x86_64/aarch64). Es zeigt fehlende
Basispakete und den CLI-Installationsplan an und fragt vor Änderungen nach.
`--yes` bestätigt diesen Umfang ausdrücklich für unbeaufsichtigte Läufe;
`--shell-only` richtet nur die WSL-Basispakete ein. Dieser Modus passt auch dann,
wenn Container ausschließlich über VS Code gestartet werden sollen.

Die Basispakete umfassen Git, curl, CA-Zertifikate, zsh, Python 3, Nano sowie die
benötigten Prüf- und Archivwerkzeuge. Nur fehlende Pakete werden angefordert;
APT kann dabei notwendige Abhängigkeiten installieren oder aktualisieren.
Die Standardvariante ruft danach `install-cli.sh` auf. Eine funktionsfähige CLI
mit Unterstützung für `--no-lockfile` bleibt erhalten. Eine defekte oder zu alte
Installation wird nicht automatisch ersetzt.

Bei fehlender CLI installiert `install-cli.sh` die in `versions.env` festgelegten
CLI- und Node-Versionen aus den offiziellen npm-/Node-Archiven, prüft deren
SHA-256-Summen und legt sie unter `~/.local/share/dotfiles-devcontainer-cli` ab.
`~/.local/bin/devcontainer` verweist auf den zugehörigen Launcher. Dafür sind weder
ein vorhandenes Node/npm noch globale npm-Pakete nötig; andere Node-Installationen
bleiben unverändert. Dieser Installer kann separat mit `bash ./install-cli.sh`
ausgeführt werden, wenn die benötigten Basiswerkzeuge bereits vorhanden sind.

Zum Abschluss läuft `check-wsl.sh`. Fehlendes oder nicht erreichbares Docker wird
als offene Voraussetzung gemeldet; bereits installierte Pakete bleiben erhalten.
Nach Behebung kann der Bootstrap wiederholt werden. Er installiert noch keine
Dotfiles, ändert keine Shell-Profile und startet keine Container.

Nach erfolgreicher Prüfung und Sichtung der gewünschten persönlichen Einstellungen:

```bash
bash ./install.sh
bash ./doctor.sh
zsh
whence -w dcupexec dcuvoice
```

`install.sh` ändert die Standardshell nicht. Das gewünschte Terminalprofil bewusst
auf zsh einstellen. Für die Prompt-Symbole eine passende Nerd Font unter Windows
installieren und im Terminal auswählen. Claude Code samt persönlicher Anmeldung
ist optional und wird nicht durch den Bootstrap installiert. Audio erst nach dem
erfolgreichen normalen Container-Einstieg einrichten.

## Installation

Voraussetzungen außerhalb von Debian/Ubuntu: `git`, `curl` und `zsh`.
Auf Debian/Ubuntu installiert `install.sh` fehlende Pakete über `apt-get`.
Die persönlichen Terminal-Tools benötigen zusätzlich Linux (x86_64 oder
aarch64), `python3` und `sha256sum`.

```bash
./install.sh
./doctor.sh
```

VS Code Dev Containers klont dieses Repository über die User Settings nach
`~/dotfiles` und führt denselben Befehl bei der Container-Erstellung aus.

## WSL vor der Einrichtung prüfen

Im persönlichen Dotfiles-Klon auf dem WSL-Host ausführen:

```bash
bash ./check-wsl.sh              # Dotfiles + Docker + Dev Containers CLI
bash ./check-wsl.sh --voice      # zusätzlich WSLg-Audio-Socket
bash ./check-wsl.sh --shell-only # nur das WSL-Dotfiles-Setup
```

`check-wsl.sh` prüft vor der Installation die benötigten Programme, unterstützte
Architektur, das persönliche Home, vorhandene Herdr-/Broot-Versionen sowie im
CLI-Modus die Erreichbarkeit von Docker und die Startfähigkeit der Dev Containers
CLI. Die Aufrufe sind zeitlich begrenzt. Ein separates Node.js ist nicht pauschal
Pflicht: Die tatsächliche CLI muss mit ihrer jeweiligen Laufzeit starten können.
Zusätzlich muss die CLI `--no-lockfile` unterstützen.

Der Check installiert nichts, lädt keine privaten Shell-Dateien, startet keine
Container und nimmt kein Audio auf. Exit-Code `0` bedeutet, dass die erforderlichen
Prüfungen bestanden sind, `1` meldet fehlende/defekte Voraussetzungen und `2`
ungültige Argumente oder den Aufruf außerhalb des WSL-Hosts. Warnungen ändern
den Exit-Code nicht. Downloads, APT-Paketangebot, Konfigurationskonflikte,
Windows-Mikrofonrechte und der Zustand eines Zielcontainers werden nicht geprüft.
`doctor.sh` prüft anschließend die tatsächlich installierten Dotfiles.

### Devcontainer ohne geöffnetes VS Code

Der direkte Weg benötigt Docker und eine in WSL funktionierende Dev Containers
CLI. Diese übernimmt die VS-Code-User-Settings nicht automatisch:

```bash
# Im gewünschten Projektordner auf dem WSL-Host:
devcontainer up --workspace-folder . --no-lockfile \
  --dotfiles-repository https://github.com/daviddomain/dotfiles.git \
  --dotfiles-target-path '~/dotfiles' \
  --dotfiles-install-command install.sh
devcontainer exec --workspace-folder . zsh
```

Die gemeinsame zsh-Konfiguration lädt auf dem WSL-Host `zsh/wsl.zsh`. Darin liegen
die portablen Funktionen `dcupexec` und `dcuvoice`; im Container werden sie nicht
definiert. Neue WSL-zsh-Shells finden auch `~/.local/bin` und `~/.devcontainers/bin`.
Die Verfügbarkeit lässt sich mit `whence -w dcupexec dcuvoice` prüfen.

- `dcupexec [Projektordner] [Shell]` startet oder verwendet den Container und
  öffnet die Shell (Standard: aktueller Ordner und zsh). Die Funktion übergibt
  die Dotfiles-Parameter und `--no-lockfile`, damit die CLI keine Lockdatei im
  Projekt erzeugt. Die vom Projekt selbst definierten Lifecycle-Befehle laufen
  weiterhin; die Option unterbindet deren mögliche Schreibzugriffe nicht.
- Ist der WSLg-Socket vorhanden, wird Audio bei der Erstellung eingebunden.
  Bei verfügbarem Mount stellt der Helper SoX im Debian-/Ubuntu-Container bereit.
  Eine angemeldete GitHub CLI im Container wird für HTTPS-Git eingebunden.
- `dcuvoice [Projektordner] [Shell]` erstellt den Container neu. Es verlangt
  interaktiv die Eingabe `ja`, bevor laufende Prozesse beendet werden und nicht
  persistente Daten verloren gehen können. Danach werden Audio und eine kurze
  Mikrofonaufnahme geprüft; die temporäre Aufnahme wird wieder gelöscht.
  Der Helper benötigt im Container APT/dpkg und Root oder sudo. Er transkribiert
  nicht selbst; Claude Code und `/voice` müssen separat verfügbar sein.
- Beide Funktionen bieten `--help`. Audio ist optional; normale Container-Starts
  funktionieren auch ohne WSLg-Socket. Ein bestehender Container ohne Audio-Mount
  wird von `dcupexec` nicht automatisch neu erstellt.

Vorhandene private Funktionen und Aliase bleiben erhalten. `~/.zshrc.local`
wird danach geladen und hat Vorrang. Wer dort noch ältere Definitionen von
`dcupexec`/`dcuvoice` hat, verwendet weiter diese alten Definitionen, bis er sie
nach Backup bewusst entfernt. Der Installer migriert oder löscht sie nicht.
Für einen eigenen Fork kann `DOTFILES_DEVCONTAINER_REPOSITORY` in der privaten
WSL-Konfiguration auf dessen URL gesetzt werden.

Ein bestehender Container erhält beim erneuten Einstieg nicht automatisch
aktualisierte Dotfiles. Dafür den persönlichen Klon kontrolliert aktualisieren
und `install.sh` sowie `doctor.sh` ausführen. Der Helper prüft nur die Shell-
Grundkonfiguration; die vollständige Prüfung erfolgt mit `doctor.sh`.

## Verhalten

- oh-my-zsh, Powerlevel10k und beide zsh-Plugins werden auf die in
  `versions.env` festgelegten, getesteten Revisionen gesetzt.
- `~/.zshrc` und `~/.p10k.zsh` werden verlinkt. Vorhandene reguläre Dateien
  werden zuvor als zeitgestempeltes Backup gesichert.
- npm-, Node-, Docker- und sudo-Plugins sowie direnv, fzf und gh-Completion
  werden nur aktiviert, wenn die jeweilige Umgebung sie anbietet.
- Der persönliche Broot-Launcher wird geladen, wenn er unter
  `~/.config/broot/launcher/bash/br` vorhanden und lesbar ist.
- Nano wird als Standardeditor gesetzt, wenn es installiert ist. Persönliche
  Anpassungen in `~/.zshrc.local` können diese Vorgabe überschreiben.
- `~/.local/bin` wird in zsh auch ohne Login-Shell in den Suchpfad aufgenommen.
- Die zsh-History wird nur dann nach `~/.claude/.shell/zsh_history` umgebogen,
  wenn `~/.claude` in einem Devcontainer ein echter beschreibbarer Mount ist.
- Außerhalb von Devcontainern wird die zsh-History einmal täglich beim ersten
  Prompt nach `${XDG_STATE_HOME:-$HOME/.local/state}/zsh-history-backups`
  gesichert. Tageskopien werden nicht überschrieben; Sicherungen, die älter
  als 60 Tage sind, werden automatisch entfernt.
- In Devcontainern mit installierter Claude CLI wird das versionierte Fragment
  in `~/.claude/settings.json` gemergt.
- Persoenliche Skills und Agents werden konfliktgeschuetzt kopiert; Rules und
  Hook-Skripte werden pro Eintrag nach `~/.claude` verlinkt. Bestehende fremde
  Inhalte werden dabei niemals automatisch ersetzt.

## Nano, Herdr und Broot

`install.sh` ruft `install-tools.sh` auf. Die Tools lassen sich auch separat
einrichten, ohne die Shell-Komponenten oder Claude-Einstellungen zu verändern:

```bash
bash ./install-tools.sh
```

- Nano erhält die Einstellungen aus `nano/nanorc`: zwei Leerzeichen pro Tab,
  automatische Einrückung, Maus, Zeilennummern, weichen Zeilenumbruch, Löschen
  markierter Bereiche und eine Suche mit Beachtung der Groß-/Kleinschreibung.
- Der Installer erzeugt `~/.nanorc` und ergänzt die vorhandenen Syntaxdateien.
  Der WSL-Shortcut `Alt+C` aus `nano/wsl.nanorc` wird nur außerhalb von
  Containern und bei vorhandenem `clip.exe` ergänzt. In Containern gilt für
  `Alt+C` die normale Nano-Belegung; es wird kein Host-Clipboard eingebunden.
- Ein vorhandenes Nano bleibt erhalten. Fehlt es, wird unter Debian/Ubuntu
  das Paket aus den konfigurierten APT-Quellen heruntergeladen und unter
  `~/.local/share/dotfiles-tools/nano` entpackt. Es gibt keine systemweite
  Paketinstallation. APT-Paketlisten sowie die benötigten ncurses-Bibliotheken
  müssen bereits vorhanden sein. Die Nano-Version folgt dem Paketangebot
  der Distribution; sie wird nicht als eigener Upstream-Binary-Pin geführt.
- Herdr und Broot werden bei Bedarf aus offiziellen GitHub-Releases nach
  `~/.local/bin` installiert. Versionen und SHA-256-Prüfsummen stehen in
  `versions.env`. Vorhandene andere Versionen führen zu einem Hinweis mit
  Abbruch, statt sie automatisch zu ersetzen.
- Herdr verwendet `one-dark`, zsh und `Alt+J` als Präfix. Danach öffnet `T`
  ein Shell-Popup und `F` ein Broot-Popup. In Broot öffnet `Ctrl+E` eine
  Textdatei im Editor. Der `br`-Launcher wird bei Bedarf bereitgestellt.
- Eine vorhandene Broot-Konfiguration bleibt bestehen. Frische Installationen
  erhalten `broot/conf.toml`. Herdr- und Nano-Konfigurationen werden als Kopien
  installiert: Erstmalig ersetzte Inhalte erhalten ein `.bak.*`-Backup,
  spätere lokale Änderungen werden anhand einer Prüfsumme erkannt und nicht
  überschrieben. Statusdateien liegen unter `~/.local/state/dotfiles-tools`.
  XDG-Konfigurations-, Daten-, Cache- und Statusverzeichnisse werden berücksichtigt.
  Ist das geerbte XDG-Datenverzeichnis nicht beschreibbar, verwendet der
  Tool-Installer stattdessen `~/.local/share/dotfiles-tools`. Die geerbte
  Umgebungsvariable und das fremde Verzeichnis bleiben unverändert.
- Herdr wird manuell gestartet. Ein Container-Rebuild beendet seine Prozesse;
  Sitzungen und Logs bleiben lokale Laufzeitdaten und gehören nicht ins Repo.

Herdr und Broot werden nicht automatisch aktualisiert. Bei einem Update zuerst
Release Notes prüfen, Version und die offiziellen Release-Prüfsummen gemeinsam
ändern und Installation sowie Diagnose erneut in WSL und Devcontainern testen.
`check-versions.sh` prüft weiterhin ausschließlich die vier Shell-Komponenten.

Quellen: [Herdr-Installation](https://herdr.dev/docs/install/),
[Broot-Installation](https://dystroy.org/broot/install/),
[Nano-Konfiguration](https://www.nano-editor.org/dist/latest/nanorc.5.html).

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
