#!/usr/bin/env bash
# Führt alle Tests aus und, falls vorhanden, shellcheck über das Skript und die Tests.
# SHELLCHECK=<Pfad> nimmt ein shellcheck, das nicht im PATH liegt.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
status=0

for t in "$HERE"/*.test.sh; do
    echo "== $(basename "$t")"
    bash "$t" || status=1
done

SC=${SHELLCHECK:-shellcheck}
if command -v "$SC" >/dev/null 2>&1; then
    echo "== shellcheck"
    "$SC" "$ROOT/profiles/shared/shdftupdate.sh" "$HERE"/*.sh && echo "shellcheck: ohne Meldung" || status=1
else
    echo "== shellcheck nicht gefunden, übersprungen"
fi
exit "$status"
