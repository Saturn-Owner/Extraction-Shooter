#!/usr/bin/env bash
# Bringt den Linux-Server-Build auf den VPS und startet ihn neu.
#
#   ./tools/deploy_server.sh benutzer@vps-adresse
#
# Laeuft von Windows aus in der Git Bash. Voraussetzung: SSH-Zugang zum VPS
# (am besten mit Schluessel statt Passwort, siehe docs/multiplayer-beta.md).
# Das Skript kopiert den Build nach /opt/extraction und startet den
# systemd-Dienst neu — der muss einmalig eingerichtet sein (ebenfalls docs).

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Benutzung: $0 benutzer@vps-adresse"
    exit 1
fi

TARGET="$1"
BUILD="build/linux/extraction_server.x86_64"

if [ ! -f "$BUILD" ]; then
    echo "Kein Server-Build unter $BUILD — erst tools/export_beta.ps1 laufen lassen."
    exit 1
fi

echo "Kopiere Server-Build nach $TARGET ..."
scp "$BUILD" "$TARGET:/opt/extraction/extraction_server.x86_64.neu"

echo "Tausche Build aus und starte den Dienst neu ..."
ssh "$TARGET" 'chmod +x /opt/extraction/extraction_server.x86_64.neu \
    && mv /opt/extraction/extraction_server.x86_64.neu /opt/extraction/extraction_server.x86_64 \
    && sudo systemctl restart extraction-server \
    && sleep 2 \
    && sudo systemctl status extraction-server --no-pager -l | head -n 12'

echo "Fertig. Verbinden mit: connect <vps-adresse>"
