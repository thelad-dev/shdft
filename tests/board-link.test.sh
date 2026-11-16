#!/usr/bin/env bash
# Tests für home/.local/bin/fm-board-link (ältestes offenes Board) und die Sperre in home/.claude/statusline.sh:
# temporäres HOME, ein Lavish-Ersatz im PATH, ohne Netzwerk.
# shellcheck disable=SC2016  # Shell-Variablen stehen im Ersatzskript absichtlich als Text
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
LINK=$ROOT/home/.local/bin/fm-board-link
STATUS=$ROOT/home/.claude/statusline.sh

unset FM_HOME XDG_CACHE_HOME COLUMNS
BASE=$(mktemp -d "${TMPDIR:-/tmp}/board-link-test.XXXXXX")
trap 'rm -rf "$BASE"' EXIT

PASS=0
FAIL=0
assert_eq() {
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1))
        printf 'FEHLER: %s\n    erwartet: %s\n    erhalten: %s\n' "$1" "$2" "$3" >&2
    fi
}

export HOME="$BASE/home"
mkdir -p "$HOME" "$BASE/bin"
CACHE="$HOME/.cache/claude-statusline"

# Ersatz für lavish-axi: listet die Zeilen aus $BASE/sessions.txt (Format der echten Liste).
cat >"$BASE/bin/lavish-axi" <<SH
#!/usr/bin/env bash
printf 'sessions[2]{file,status,url,pending_prompts,listener}:\n'
cat "$BASE/sessions.txt"
SH
chmod +x "$BASE/bin/lavish-axi"
export PATH="$BASE/bin:$PATH"

mkdir -p "$BASE/b"
payload='<html>{"schema":1,"captains_call":[1,2]}</html>'
# Anlage-Reihenfolge alt, bericht, neu (Geburtszeit hat Sekundenauflösung; spätere Änderung zählt nicht)
printf '%s' "$payload" >"$BASE/b/alt.html"; sleep 1.1
printf '<html>Bericht</html>' >"$BASE/b/bericht.html"; sleep 1.1
printf '%s' "$payload" >"$BASE/b/neu.html"
touch -d '1 day ago' "$BASE/b/neu.html"
touch "$BASE/b/alt.html"
row() { printf '  %s,%s,"http://127.0.0.1:4387/session/%s",0,none\n' "$1" "$2" "$3"; }

run_link() { rm -rf "$CACHE"; bash "$LINK" "$@"; sed 's/|[0-9:]*$//' "$CACHE/board.txt" 2>/dev/null; }

# 1. Das älteste offene Board nach Anlage gewinnt, unabhängig von der Listenreihenfolge
{ row "$BASE/b/neu.html" open neu; row "$BASE/b/alt.html" open alt; row "$BASE/b/bericht.html" open bericht; } >"$BASE/sessions.txt"
assert_eq "ältestes offenes Board" "http://127.0.0.1:4387/session/alt|2" "$(run_link)"
assert_eq "Argument wird nicht gebraucht" "http://127.0.0.1:4387/session/alt|2" "$(run_link /irgendwo)"

# 2. Ein beendetes Board zählt nicht, das nächstältere offene wird gezeigt (Bericht ohne Karten: 0)
{ row "$BASE/b/neu.html" open neu; row "$BASE/b/alt.html" ended alt; row "$BASE/b/bericht.html" open bericht; } >"$BASE/sessions.txt"
assert_eq "beendetes Board übersprungen" "http://127.0.0.1:4387/session/bericht|0" "$(run_link)"

# 3. Eine Sitzung ohne Datei zählt nicht
{ row "$BASE/b/fehlt.html" open fehlt; row "$BASE/b/neu.html" open neu; } >"$BASE/sessions.txt"
assert_eq "Sitzung ohne Datei übersprungen" "http://127.0.0.1:4387/session/neu|2" "$(run_link)"

# 4. Kein offenes Board: leere Anzeige, kein Fehler, alte Anzeige wird geleert
row "$BASE/b/alt.html" ended alt >"$BASE/sessions.txt"
mkdir -p "$CACHE"
printf 'http://alt|1|00:00\n' >"$CACHE/board.txt"
bash "$LINK" "$BASE"
assert_eq "kein Board: Exit-Code" "0" "$?"
assert_eq "kein Board: Anzeige leer" "0" "$(wc -c <"$CACHE/board.txt" | tr -d ' ')"

# 5. Sperre: verwaiste (älter als eine Minute) wird ersetzt, auch bei fehlendem fm-board-link
rm -rf "$CACHE"
mkdir -p "$CACHE/board.lock"
touch -d '5 minutes ago' "$CACHE/board.lock"
printf '{"model":{"display_name":"M"},"workspace":{"project_dir":"%s"}}' "$BASE" | PATH="$BASE/nope:/usr/bin:/bin" bash "$STATUS" >/dev/null
sleep 1
assert_eq "verwaiste Sperre ersetzt und freigegeben (fm-board-link fehlt)" "nein" "$([ -e "$CACHE/board.lock" ] && echo ja || echo nein)"

# 6. Eine frische Sperre bleibt, solange ihr Lauf arbeitet
rm -rf "$CACHE"
mkdir -p "$CACHE/board.lock"
printf '{"model":{"display_name":"M"}}' | bash "$STATUS" >/dev/null
assert_eq "frische Sperre bleibt" "ja" "$([ -e "$CACHE/board.lock" ] && echo ja || echo nein)"

# 7. Die Statuszeile reicht das Arbeitsverzeichnis an fm-board-link weiter
rm -rf "$CACHE"
printf '#!/usr/bin/env bash\nprintf "%%s" "$1" >"%s/arg"\n' "$BASE" >"$BASE/bin/fm-board-link"
chmod +x "$BASE/bin/fm-board-link"
printf '{"model":{"display_name":"M"},"workspace":{"project_dir":"/x/y"}}' | bash "$STATUS" >/dev/null
sleep 1
assert_eq "Arbeitsverzeichnis weitergereicht" "/x/y" "$(cat "$BASE/arg" 2>/dev/null)"

printf 'board-link: %d bestanden, %d fehlgeschlagen\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
