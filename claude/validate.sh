#!/usr/bin/env bash
set -euo pipefail

CLAUDE_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=extensions.sh
source "$CLAUDE_CONFIG/extensions.sh"

claude_extensions_validate_sources "$CLAUDE_CONFIG"
printf 'Claude-Konfigurationsquellen sind oeffentlich und strukturell sicher.\n'
