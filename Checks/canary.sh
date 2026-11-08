#!/bin/sh
# The canary test, run on the Berth Mac: write a journal page, caption,
# place and photo carrying a unique marker through the app's own code, then
# search everything the server side holds for it, in every encoding it
# could appear in: a fresh Postgres dump, the app's and the proxy's logs,
# and a fresh Berth backup. Finding it anywhere is a failure. The PIN is
# searched for too. The test account is deleted afterwards.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer} xcrun swiftc -O -o "$work/canary" \
  Tekkoh/Core/Crypto.swift Tekkoh/Core/Models.swift Shared/Day.swift Tekkoh/Core/API.swift Tekkoh/Core/Transport.swift Tekkoh/Core/Keychain.swift Checks/canary/main.swift

set -- $("$work/canary" write "$work/id.json")
handle=$1 marker=$2 pin=$3
echo "wrote a page for $handle carrying $marker"

# Fresh copies of everything the server side keeps.
berth pg:backup tekkoh-db >/dev/null
dump=$(ls -t ~/.berth/backups/pg/tekkoh-db/* | head -1)
# Berth keeps Postgres's compressed custom format: turn it into plain SQL
# (bytea as hex) with the database container's own pg_restore.
container exec -i pg-tekkoh-db pg_restore -f - < "$dump" > "$work/dump.sql"
berth logs tekkoh > "$work/app.log" 2>&1 || true
cp ~/.berth/logs/caddy.log "$work/caddy.log" 2>/dev/null || true
cat ~/.berth/apps/tekkoh/logs/*.log > "$work/berth-app.log" 2>/dev/null || true
grep -c "$handle" "$work/dump.sql" >/dev/null || { echo "FAIL: the account isn't in the dump, so the dump proves nothing"; exit 1; }

# The marker as text, as hex (Postgres bytea) and as base64 (API bodies),
# and the PIN.
hex=$(printf %s "$marker" | xxd -p | tr -d '\n')
b64a=$(printf %s "$marker" | base64 | cut -c1-12)
b64b=$(printf %s "x$marker" | base64 | cut -c3-14)
b64c=$(printf %s "xx$marker" | base64 | cut -c5-16)
found=0
for f in "$work"/dump.sql "$work"/*.log; do
  for needle in "$marker" "$hex" "$b64a" "$b64b" "$b64c"; do
    if grep -q -- "$needle" "$f"; then echo "FAIL: $(basename "$f") contains $needle"; found=1; fi
  done
  if grep -qE "(^|[^0-9])$pin([^0-9]|$)" "$f"; then echo "note: $(basename "$f") contains the digits $pin (check it's a coincidence)"; fi
done
lines=$(wc -l < "$work/dump.sql" | tr -d ' ')
echo "searched a $lines-line database dump and $(cat "$work"/*.log | wc -l | tr -d ' ') lines of logs"

"$work/canary" delete "$work/id.json"
[ $found -eq 0 ] && echo "PASS: the marker is nowhere on the server side" || exit 1
