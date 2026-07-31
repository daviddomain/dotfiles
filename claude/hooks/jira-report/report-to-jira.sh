#!/usr/bin/env bash
# Stop-Hook: sorgt dafuer, dass ein Ticketlauf einen Report am Jira-Ticket hinterlaesst.
#
# Verhalten:
#   1. Ohne CLAUDE_REPORT_HOOK=1 passiert gar nichts.
#   2. Report-Datei da  -> wird gepostet, fertig.
#   3. Report fehlt     -> Abschluss blockiert, Agent bekommt die Formatvorgabe zurueck.
#   4. Nach MAX_BLOCKS Anlaeufen -> letzte Agentennachricht als markierter Notfall-Report.
set -uo pipefail

# Ganz oben, weil dieser Hook auf Benutzerebene registriert ist und sonst in
# jedem Projekt bei jedem Turn Spuren hinterlassen wuerde.
[[ "${CLAUDE_REPORT_HOOK:-}" == "1" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTER="$SCRIPT_DIR/post-report.sh"

ENV_FILE="${CLAUDE_HOOK_ENV_FILE:-$HOME/.claude/hook.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_FILE"; set +a
fi

WORKSPACE="${CLAUDE_PROJECT_DIR:-$(pwd)}"
REPORT_DIR="${CLAUDE_REPORT_DIR:-$WORKSPACE/.claude-reports}"
STATE_DIR="${CLAUDE_STATE_DIR:-$HOME/.claude/state}"
FORMAT_FILE="${CLAUDE_REPORT_FORMAT_FILE:-$HOME/.claude/context/report-format.md}"
MAX_BLOCKS="${CLAUDE_REPORT_MAX_BLOCKS:-2}"
TICKET_PATTERN="${CLAUDE_TICKET_PATTERN:-[a-z]+-[0-9]+}"

mkdir -p "$REPORT_DIR" "$STATE_DIR"
LOG="$STATE_DIR/hook.log"

log()    { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"; }

input="$(cat)"
session_id="$(jq -r '.session_id // "nosession"' <<<"$input")"
last_msg="$(jq -r '.last_assistant_message // ""' <<<"$input")"

branch="$(git -C "$WORKSPACE" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
ticket="$(grep -oiE "$TICKET_PATTERN" <<<"$branch" | head -n1 | tr '[:lower:]' '[:upper:]')"

log "aufgerufen in $WORKSPACE, branch=${branch:-unbekannt}, ticket=${ticket:-keins}"

# Ohne Ticket kein Ziel. Der Wrapper prueft das vorher, hier nur der Notausgang,
# damit der Hook nicht in eine Blockschleife laeuft.
if [[ -z "$ticket" ]]; then
  log "kein Ticket im Branch - uebersprungen"
  exit 0
fi

report="$REPORT_DIR/report.md"
counter_file="$STATE_DIR/${session_id}.blocks"

blocks=0
[[ -f "$counter_file" ]] && blocks="$(cat "$counter_file" 2>/dev/null || echo 0)"

# Formatvorgabe kommt aus der Datei im Volume. Fehlt sie, greift eine
# neutrale Kurzfassung, damit der Lauf nicht an einer leeren Anweisung scheitert.
read_format() {
  if [[ -s "$FORMAT_FILE" ]]; then
    cat "$FORMAT_FILE"
    return
  fi
  if (( blocks == 0 )); then
    log "Formatvorgabe fehlt: $FORMAT_FILE - Rueckfall auf Kurzfassung"
  fi
  cat <<'EOF'
## Status
fertig | teilweise | blockiert
## Was geaendert wurde
Betroffene Dateien mit je einem Satz.
## Abnahmekriterium
Wortlaut aus dem Auftrag, dahinter erfuellt: ja | nein, mit Begruendung.
## Abweichungen vom Auftrag
Alles, was du anders gemacht hast als beauftragt, mit Grund. Nichts beschoenigen.
## Offene Fragen
Nur was ohne Rueckmeldung nicht entschieden werden kann. Nichts erfinden.
EOF
}

# --- Fall 2: Report liegt vor ---------------------------------------------
if [[ -s "$report" ]]; then
  if out="$("$POSTER" "$ticket" "$report" 2>&1)"; then
    rm -f "$counter_file"
    mv "$report" "$STATE_DIR/${ticket}.posted.md"
    log "gepostet an $ticket"
    exit 0
  fi
  # Posten fehlgeschlagen: nicht blockieren, aber sichtbar machen.
  log "posten fehlgeschlagen: $out"
  jq -n --arg e "$out" '{
    decision: "block",
    reason: ("Der Report konnte nicht an Jira gepostet werden. Fehler: " + $e +
             "  Bitte NICHT erneut versuchen, sondern diesen Fehler wortwoertlich als letzte Nachricht ausgeben.")
  }'
  exit 0
fi

# --- Fall 3: Report fehlt, noch Anlaeufe frei ------------------------------
if (( blocks < MAX_BLOCKS )); then
  format="$(read_format)"
  echo $((blocks + 1)) > "$counter_file"
  jq -n --arg p "$report" --arg f "$format" '{
    decision: "block",
    reason: ("Du bist noch nicht fertig: Der Abschlussreport fehlt. Schreibe ihn nach " + $p +
             " mit genau diesen Abschnitten:\n" + $f + "\nDanach beende deine Antwort.")
  }'
  exit 0
fi

# --- Fall 4: Notfall -------------------------------------------------------
fallback="$STATE_DIR/${ticket}.fallback.md"
printf '%s\n' "$last_msg" > "$fallback"
"$POSTER" "$ticket" "$fallback" \
  "AUTOMATISCH ERZEUGT. Der Agent hat trotz $MAX_BLOCKS Aufforderungen keinen strukturierten Report geschrieben. Unten steht seine letzte Nachricht im Wortlaut. Bitte mit Vorsicht lesen, das ist kein geprueftes Ergebnis." \
  >> "$LOG" 2>&1
log "Notfall-Report an $ticket"
rm -f "$counter_file"
exit 0