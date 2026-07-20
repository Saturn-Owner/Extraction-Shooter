#!/usr/bin/env bash
# Bringt den aktuellen Git-Stand (HEAD) auf den VPS und startet den Server neu.
#
#   ./tools/deploy_server.sh root@193.23.160.41
#
# Läuft von Windows aus in der Git Bash. Der VPS ist eingerichtet (siehe
# docs/multiplayer-beta.md): offizielle Godot-4.7.1-Binary unter
# /opt/extraction/godot, Projekt unter /opt/extraction/projekt, systemd-Dienst
# extraction-server. Es wird KEIN Export-Build gebraucht — der Server läuft
# mit der normalen Godot-Binary direkt auf dem Projektquellcode.
#
# SSH-Schlüssel ggf. mitgeben:  ./tools/deploy_server.sh "root@..." ~/schluessel

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Benutzung: $0 benutzer@vps-adresse [pfad-zum-ssh-schluessel]"
    exit 1
fi

TARGET="$1"
SSH_OPTS=(-o BatchMode=yes)
if [ $# -ge 2 ]; then
    SSH_OPTS+=(-i "$2")
fi

echo "Packe den aktuellen Git-Stand (HEAD) ..."
git archive --format=tar.gz -o /tmp/projekt.tar.gz HEAD

echo "Kopiere zum VPS ..."
scp "${SSH_OPTS[@]}" /tmp/projekt.tar.gz "$TARGET:/opt/extraction/projekt.tar.gz"
rm /tmp/projekt.tar.gz

echo "Entpacke, importiere und starte den Dienst neu ..."
ssh "${SSH_OPTS[@]}" "$TARGET" '
    set -e
    systemctl stop extraction-server
    rm -rf /opt/extraction/projekt
    mkdir -p /opt/extraction/projekt
    tar -xzf /opt/extraction/projekt.tar.gz -C /opt/extraction/projekt
    rm /opt/extraction/projekt.tar.gz
    chown -R extraction:extraction /opt/extraction/projekt
    su -s /bin/bash extraction -c "cd /opt/extraction && ./godot/Godot_v4.7.1-stable_linux.x86_64 --headless --path projekt --import --quit-after 150" >/dev/null 2>&1
    systemctl start extraction-server
    sleep 3
    systemctl is-active extraction-server
    journalctl -u extraction-server --no-pager -n 3 --since "-10 seconds"
'

echo "Fertig. Verbinden im Spiel mit der VPS-Adresse."
