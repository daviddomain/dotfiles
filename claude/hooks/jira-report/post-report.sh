#!/usr/bin/env bash
# Postet eine Report-Datei als Kommentar an ein Jira-Ticket.
# Aufruf: post-report.sh <TICKET> <report-datei> [vorspann]
# Wird vom Stop-Hook aufgerufen, kann aber auch von Hand benutzt werden.
set -euo pipefail

ENV_FILE="${CLAUDE_HOOK_ENV_FILE:-$HOME/.claude/hook.env}"

ticket="${1:?Ticket fehlt}"
report_file="${2:?Report-Datei fehlt}"
prefix="${3:-}"

[[ -f "$ENV_FILE" ]] || { echo "Zugangsdaten fehlen: $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a

: "${JIRA_BASE_URL:?}" "${JIRA_EMAIL:?}" "${JIRA_API_TOKEN:?}"

text="$(cat "$report_file")"
[[ -n "$prefix" ]] && text="${prefix}"$'\n\n'"${text}"

payload="$(jq -n --arg b "$text" '{body: $b}')"

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "[DRY_RUN] POST $JIRA_BASE_URL/rest/api/2/issue/$ticket/comment"
  echo "[DRY_RUN] $(jq -r '.body' <<<"$payload" | head -c 300)"
  exit 0
fi

http_code="$(curl -sS -o /tmp/jira-resp.json -w '%{http_code}' \
  -X POST \
  -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$payload" \
  "$JIRA_BASE_URL/rest/api/2/issue/$ticket/comment")"

if [[ "$http_code" != "201" ]]; then
  echo "Jira-Kommentar fehlgeschlagen (HTTP $http_code):" >&2
  head -c 500 /tmp/jira-resp.json >&2
  exit 1
fi

echo "Report an $ticket gepostet."