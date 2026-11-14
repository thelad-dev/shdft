#!/usr/bin/env bash
# Tests für home/.local/bin/fm-board-link und die Sperre in home/.claude/statusline.sh:
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
URL="http://127.0.0.1:4387/session/abc"

# Ersatz für lavish-axi: listet nur das Board unter $BASE/zuhause als offene Sitzung.
cat >"$BASE/bin/lavish-axi" <<SH
#!/usr/bin/env bash
printf 'sessions[1]{file,status,url}:\n  %s,open,"%s",0,none\n' "$BASE/zuhause/.lavish/bearings-board.html" "$URL"
SH
chmod +x "$BASE/bin/lavish-axi"
export PATH="$BASE/bin:$PATH"

mkdir -p "$BASE/zuhause/.lavish" "$BASE/zuhause/projekt/unter"
printf '<html>{"schema":1,"captains_call":[1,2]}</html>' >"$BASE/zuhause/.lavish/bearings-board.html"

run_link() { rm -rf "$CACHE"; bash "$LINK" "$@"; cat "$CACHE/board.txt" 2>/dev/null | sed 's/|[0-9:]*$//'; }

# 1. Zuhause ohne FM_HOME aus dem Arbeitsverzeichnis der Sitzung (aufwärts gesucht)
assert_eq "Zuhause aus Arbeitsverzeichnis" "$URL|2" "$(run_link "$BASE/zuhause/projekt/unter")"

# 2. Arbeitsverzeichnis außerhalb: das Board einer offenen Lavish-Sitzung
assert_eq "Zuhause aus Lavish-Sitzung" "$URL|2" "$(run_link "$BASE")"
assert_eq "Zuhause ohne Argument" "$URL|2" "$(run_link)"

# 3. FM_HOME hat Vorrang
assert_eq "FM_HOME vorrangig" "" "$(FM_HOME="$BASE/leer" run_link "$BASE/zuhause")"

# 4. Kein Board: leere Anzeige, kein Fehler, alte Anzeige wird geleert
mv "$BASE/zuhause/.lavish/bearings-board.html" "$BASE/board.html"
rm -f "$BASE/bin/lavish-axi"
printf '#!/usr/bin/env bash\nexit 0\n' >"$BASE/bin/lavish-axi"
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
