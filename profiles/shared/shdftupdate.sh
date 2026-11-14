#!/usr/bin/env bash
# /shdftupdate: zieht die shdft-Einstellungen dieses Rechners nach, ohne je Lokales zu überschreiben.
# Der Klon wird per Fast-Forward aktualisiert, jede verwaltete Datei mit HEAD verglichen:
# veraltete Dateien werden nachgezogen (vorher nach ~/.shdft-backup/<Zeitstempel>/ gesichert),
# fehlende angelegt, lokal Abweichendes nur gemeldet und als Vorschlag vorbereitet
# (eigener Zweig und Arbeitsbaum, nie Push, nie PR). Weitere Rechner: ssh-Aliase in $SHDFT_CONFIG_DIR/hosts.
# Exit 0: aktuell oder sicher nachgezogen. Exit 1: etwas zu melden. Exit 2: Aufruf- oder Umgebungsfehler.
set -euo pipefail

REMOTE_REF=origin/main
MAIN_BRANCH=main

# Gemischte Dateien, wie in MERGES der Installer (tests/shdftupdate.test.sh prüft den Gleichlauf).
MERGES=(
    .claude/settings.json
    .pi/agent/settings.json
)
# Shell-Blöcke: <Datei unter $HOME>|<Blockname>|<Quelle im Repo>
BLOCKS=(
    ".bashrc|shdft|shell/bashrc-shdft.sh"
    ".bashrc|shdft-profile|profiles/@PROFILE@/shell/bashrc-profile.sh"
    ".profile|shdft-profile|profiles/@PROFILE@/shell/profile-profile.sh"
)
# Profil-Dateien außerhalb von home/: <Quelle im Repo>|<Ziel unter $HOME>
# shellcheck disable=SC2034  # wird über LINKS_<Profil> / TEMPLATES_<Profil> angesprochen
LINKS_linux=(
    "profiles/linux/wezterm.lua|.config/wezterm/wezterm.lua"
)
# shellcheck disable=SC2034
LINKS_windows_wsl=(
    "profiles/windows-wsl/home/.local/bin/win-browser|.local/bin/win-browser"
)
# shellcheck disable=SC2034
TEMPLATES_linux=()
# shellcheck disable=SC2034
TEMPLATES_windows_wsl=(
    "profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in|.local/share/applications/win-browser.desktop"
)

# Sicherheitsprüfung: <Art>|<Groß-/Kleinschreibung egal 0/1>|<ERE>
SCAN_PATTERNS=(
    'Token|0|gh[pousr]_[A-Za-z0-9]{20,}'
    'Token|0|github_pat_[A-Za-z0-9_]{20,}'
    'Token|0|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{20,}'
    'Token|0|(^|[^A-Za-z0-9])(sk|rk)_(live|test)_[A-Za-z0-9]{16,}'
    'Token|0|(^|[^A-Za-z0-9])pk_live_[A-Za-z0-9]{16,}'
    'Token|0|xox[baprs]-[A-Za-z0-9-]{10,}'
    'Token|0|AKIA[0-9A-Z]{16}'
    'Token|0|AIza[0-9A-Za-z_-]{30,}'
    'Token|0|(^|[^A-Za-z0-9])npm_[A-Za-z0-9]{30,}'
    'Token|0|glpat-[A-Za-z0-9_-]{20,}'
    'Token|0|(^|[^A-Za-z0-9])hf_[A-Za-z0-9]{30,}'
    'Token|0|dop_v1_[A-Za-z0-9]{20,}'
    'Token|0|eyJ[A-Za-z0-9_-]{5,}\.eyJ[A-Za-z0-9_-]{5,}'
    'Token|1|bearer[[:space:]]+[A-Za-z0-9._~+/=-]{20,}'
    'Token|1|authorization[[:space:]]*[:=][[:space:]]*["'"'"']?(basic|bearer)[[:space:]]+[A-Za-z0-9._~+/=-]{8,}'
    'Kennwort|1|curl[^|;&]*[[:space:]](-u|--user)[[:space:]]+["'"'"']?[^[:space:]:"'"'"'$<]+:[^[:space:]"'"'"'$<]+'
    'Schlüssel|0|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'Schlüssel|0|ssh-rsa[[:space:]]+AAAA'
    'Schlüssel|0|ssh-ed25519[[:space:]]+AAAA'
    'private IP|0|(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}($|[^0-9])'
    'private IP|0|(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}($|[^0-9])'
    'private IP|0|(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}($|[^0-9])'
    'private IP|0|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}($|[^0-9])'
    'private IP|1|(^|[^0-9A-Fa-f:])f[cd][0-9a-f]{2}(:[0-9a-f]{0,4}){2,7}($|[^0-9A-Fa-f:])'
    'Benutzerpfad|0|(^|[^A-Za-z0-9_.$}-])/(home|Users)/[A-Za-z0-9][A-Za-z0-9._-]*'
    'Benutzerpfad|1|(^|[^A-Za-z0-9_.$}-])/mnt/[a-z]/Users/[A-Za-z0-9][A-Za-z0-9._-]*'
    'Benutzerpfad|1|[A-Za-z]:[\\/]+Users[\\/]+[A-Za-z0-9][A-Za-z0-9._-]*'
    'Benutzerpfad|0|(^|[^\\])\\{2,4}[A-Za-z0-9._-]{3,}\\{1,2}[A-Za-z0-9$._-]+'
    'Verbindungszeichenfolge|0|://[^/[:space:]:@]+:[^/[:space:]@$<][^/[:space:]@]*@'
    'Verbindungszeichenfolge|1|(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp)://'
    'Verbindungszeichenfolge|1|jdbc:'
    'Verbindungszeichenfolge|0|Password='
)
# Kennwort: Schlüsselwort (auch als Teil eines Namens wie DB_PASS), dann : oder = und ein Wert.
# Platzhalter sind nur $NAME, ${NAME}, <...>, @NAME@ und strata-local; der Wert ist die letzte Gruppe.
SCAN_PASSWORD_RE="((^|[^A-Za-z])(pass|pwd)|password|passwd|passphrase|secret|token|(api|access|secret|private|auth|signing|encryption)[_-]?key)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?([^[:space:]\"',;]+)"
SCAN_MAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

usage() {
    cat <<'EOF'
Aufruf: shdftupdate.sh [--dry-run] [--no-propose] [--local] [-v] [--repo PFAD]

Zieht die shdft-Einstellungen dieses Rechners nach: Klon per Fast-Forward aktualisieren,
veraltete Dateien nachziehen, fehlende anlegen. Lokal Abweichendes wird nie überschrieben,
sondern gemeldet und als Vorschlag (Zweig und Arbeitsbaum, ohne Push und ohne PR) vorbereitet.

  -n, --dry-run   nur prüfen und anzeigen; schreibt nichts (außer dem Abruf von origin)
  --no-propose    keinen Vorschlag für lokale Abweichungen vorbereiten
  --local         nur diesen Rechner, die Hosts-Liste nicht abfragen
  -v, --verbose   bei Abweichungen den gekürzten Diff zeigen
  --repo PFAD     shdft-Klon (sonst SHDFT_REPO, Ort des Skripts, ~/.claude/CLAUDE.md, ~/shdft, ~/workspaces/shdft)
  -h, --help      diese Hilfe

Umgebung:
  SHDFT_REPO        shdft-Klon
  SHDFT_PROFILE     linux oder windows-wsl (sonst Erkennung über WSL)
  SHDFT_CONFIG_DIR  Standard ~/.config/shdft; dort liegt die Liste hosts (ein ssh-Alias je Zeile)
  SHDFT_STATE_DIR   Standard ~/.local/state/shdft; dort liegen die Arbeitsbäume der Vorschläge

Exit 0: aktuell oder sicher nachgezogen. Exit 1: etwas zu melden. Exit 2: Aufruf- oder Umgebungsfehler.
EOF
}

parse_args() {
    OPT_DRY=0 OPT_NO_PROPOSE=0 OPT_LOCAL=0 OPT_VERBOSE=0 OPT_REPO=""
    while [ $# -gt 0 ]; do
        case "$1" in
        -n | --dry-run) OPT_DRY=1 ;;
        --no-propose) OPT_NO_PROPOSE=1 ;;
        --local) OPT_LOCAL=1 ;;
        -v | --verbose) OPT_VERBOSE=1 ;;
        --repo)
            if [ $# -lt 2 ]; then
                echo "Fehler: --repo braucht einen Pfad." >&2
                usage >&2
                exit 2
            fi
            OPT_REPO=$2
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unbekannte Option: $1" >&2
            usage >&2
            exit 2
            ;;
        esac
        shift
    done
}

say() { printf '%-13s %s\n' "$1" "$2"; }
first_line() { printf '%s\n' "${1%%$'\n'*}"; }
commits_text() { if [ "$1" = 1 ]; then echo "1 Commit"; else echo "$1 Commits"; fi; }
join_by() {
    local sep=$1 out="" x
    shift
    for x in "$@"; do out+="${out:+$sep}$x"; done
    printf '%s' "$out"
}
g() { git -C "$REPO" -c core.quotePath=false "$@"; }

host_name() {
    local h
    h=$(uname -n 2>/dev/null || true)
    h=${h%%.*}
    printf '%s\n' "${h:-rechner}"
}

detect_profile() {
    case "${SHDFT_PROFILE:-}" in
    linux | windows-wsl)
        PROFILE=$SHDFT_PROFILE
        return 0
        ;;
    "") ;;
    *)
        echo "Fehler: SHDFT_PROFILE muss linux oder windows-wsl sein, nicht ${SHDFT_PROFILE}." >&2
        exit 2
        ;;
    esac
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
        PROFILE=windows-wsl
    else
        PROFILE=linux
    fi
}

# Setzt REPO auf die Wurzel des Arbeitsbaums, wenn der Pfad ein shdft-Klon ist.
repo_ok() {
    local top
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
    [ -d "$top/home" ] && [ -f "$top/shell/bashrc-shdft.sh" ] || return 1
    REPO=$top
}

find_repo() {
    local c dir
    if [ -n "$OPT_REPO" ]; then
        repo_ok "$OPT_REPO" || { echo "Fehler: $OPT_REPO ist kein shdft-Klon." >&2; exit 2; }
        return 0
    fi
    if [ -n "${SHDFT_REPO:-}" ]; then
        repo_ok "$SHDFT_REPO" || { echo "Fehler: SHDFT_REPO=$SHDFT_REPO ist kein shdft-Klon." >&2; exit 2; }
        return 0
    fi
    c=${BASH_SOURCE[0]:-}
    if [ -f "$c" ]; then
        dir=$(cd "$(dirname "$c")/../.." 2>/dev/null && pwd -P) || dir=""
        if [ -n "$dir" ] && repo_ok "$dir"; then return 0; fi
    fi
    c=$(readlink -f "$HOME/.claude/CLAUDE.md" 2>/dev/null || true)
    case "$c" in
    */home/.claude/CLAUDE.md)
        if repo_ok "${c%/home/.claude/CLAUDE.md}"; then return 0; fi
        ;;
    esac
    for c in "$HOME/shdft" "$HOME/workspaces/shdft"; do
        if repo_ok "$c"; then return 0; fi
    done
    return 1
}

# ---------------------------------------------------------------- Schritt 1: Klon

step_repo() {
    local old new out files b7 n7 count ahead behind dirty
    REPO_STATE=aktuell REPO_MSG="" FF_CHANGED="" REPO_PROBLEM=0 ALLOW_WRITE=0
    BRANCH=$(g symbolic-ref -q --short HEAD || true)
    BRANCH_LABEL=${BRANCH:-losgelöster HEAD}
    HEAD_BEFORE=$(g rev-parse HEAD)
    old=$(g rev-parse -q --verify "refs/remotes/$REMOTE_REF^{commit}" 2>/dev/null || true)

    # Eigene ssh-Einstellungen (Umgebung oder core.sshCommand) bleiben; sonst nie nach einem Kennwort fragen.
    if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "$(g config --get core.sshCommand 2>/dev/null || true)" ]; then
        export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
    fi
    if ! out=$(g fetch --quiet origin 2>&1); then
        REPO_STATE=offline
        REPO_MSG="Offline oder origin nicht erreichbar (git fetch fehlgeschlagen), Stand von $REMOTE_REF unbekannt"
        NOTES+=("git fetch: $(first_line "$out")")
        if [ "$BRANCH" = "$MAIN_BRANCH" ]; then ALLOW_WRITE=1; fi
    else
        new=$(g rev-parse -q --verify "refs/remotes/$REMOTE_REF^{commit}" 2>/dev/null || true)
        if [ -z "$new" ]; then
            REPO_STATE=ohne-ref
            REPO_MSG="$REMOTE_REF fehlt nach dem Abruf"
        elif [ -n "$old" ] && [ "$old" != "$new" ] && ! g merge-base --is-ancestor "$old" "$new"; then
            REPO_STATE=umgeschrieben
            REPO_MSG="$REMOTE_REF wurde umgeschrieben (${old:0:7} -> ${new:0:7}), nichts erzwungen"
        elif [ "$BRANCH" != "$MAIN_BRANCH" ]; then
            REPO_STATE=zweig
            REPO_MSG="Zweig $BRANCH_LABEL statt $MAIN_BRANCH, kein Fast-Forward"
        elif [ "$(g rev-parse HEAD)" = "$new" ]; then
            REPO_MSG="aktuell"
            ALLOW_WRITE=1
        elif g merge-base --is-ancestor HEAD "$new"; then
            count=$(commits_text "$(g rev-list --count "HEAD..$new")")
            b7=$(g rev-parse --short HEAD)
            n7=$(g rev-parse --short "$new")
            if [ "$OPT_DRY" = 1 ]; then
                REPO_STATE=ff-offen
                ALLOW_WRITE=1
                REPO_MSG="würde aktualisieren $b7..$n7 ($count)"
                NOTES+=("Trockenlauf: Dateien werden gegen den alten Stand verglichen")
            elif out=$(g merge --ff-only --quiet "$REMOTE_REF" 2>&1); then
                REPO_STATE=aktualisiert
                ALLOW_WRITE=1
                REPO_MSG="aktualisiert $b7..$n7 ($count)"
                FF_CHANGED=$(g diff --name-only "$HEAD_BEFORE" HEAD)
            else
                REPO_STATE=ff-blockiert
                files=$(printf '%s\n' "$out" | sed -n 's/^\t//p' | paste -sd, - | sed 's/,/, /g')
                if [ -n "$files" ]; then
                    REPO_MSG="Fast-Forward nicht möglich: lokale Änderungen in $files"
                    NOTES+=("Der Nutzer kann die Datei im Klon mit git -C $REPO restore <datei> zurücksetzen; das Skript tut das nie selbst")
                else
                    REPO_MSG="Fast-Forward nicht möglich: $(first_line "$out")"
                fi
            fi
        elif g merge-base --is-ancestor "$new" HEAD; then
            ahead=$(g rev-list --count "$new..HEAD")
            REPO_STATE=voraus
            REPO_MSG="$(commits_text "$ahead") nicht gepusht"
        else
            ahead=$(g rev-list --count "$new..HEAD")
            behind=$(g rev-list --count "HEAD..$new")
            REPO_STATE=divergiert
            REPO_MSG="divergiert: $ahead lokal, $behind auf $REMOTE_REF"
        fi
    fi

    case "$REPO_STATE" in
    aktuell | aktualisiert | ff-offen) ;;
    *) REPO_PROBLEM=1 ;;
    esac
    if [ "$REPO_STATE" = aktuell ] || [ "$REPO_STATE" = aktualisiert ]; then
        PROPOSE_REASON=""
    elif [ "$REPO_STATE" = ff-offen ]; then
        PROPOSE_REASON="Trockenlauf"
    else
        PROPOSE_REASON="$REPO_MSG; ein Vorschlag braucht HEAD == $REMOTE_REF"
    fi

    dirty=$(g status --porcelain --untracked-files=no | sed 's/^...//' | paste -sd, - | sed 's/,/, /g' || true)
    if [ -n "$dirty" ]; then NOTES+=("Klon hat lokale Änderungen (bleiben unangetastet): $dirty"); fi
}

# ---------------------------------------------------------------- Verwaltete Dateien

IT_CLASS=() IT_SRC=() IT_DEST=() IT_LABEL=() IT_NAME=()
ST=() ART=() NOTE=() SUM=() RAWF=() LOCALF=() PROPF=() PROPSKIP=() AFTER=()

TILDE='~'
add_item() { # Klasse Quelle Ziel [Blockname]
    IT_CLASS+=("$1") IT_SRC+=("$2") IT_DEST+=("$3") IT_NAME+=("${4:-}")
    IT_LABEL+=("$TILDE${3#"$HOME"}${4:+ (Block $4)}")
}

in_head() { g cat-file -e "HEAD:$1" 2>/dev/null; }

build_items() {
    local p rel m line src dest file name rest
    local -n plinks="LINKS_${PROFILE//-/_}" ptemplates="TEMPLATES_${PROFILE//-/_}"
    while IFS= read -r -d '' p; do
        rel=${p#home/}
        for m in "${MERGES[@]}"; do
            if [ "$m" = "$rel" ]; then continue 2; fi
        done
        add_item link "$p" "$HOME/$rel"
    done < <(g ls-tree -r -z --name-only HEAD -- home/)
    for line in "${plinks[@]}"; do
        src=${line%%|*}
        dest=${line#*|}
        if in_head "$src"; then add_item link "$src" "$HOME/$dest"; fi
    done
    for m in "${MERGES[@]}"; do
        if in_head "home/$m"; then add_item merge "home/$m" "$HOME/$m"; fi
    done
    for line in "${BLOCKS[@]}"; do
        file=${line%%|*}
        rest=${line#*|}
        name=${rest%%|*}
        src=${rest#*|}
        src=${src//@PROFILE@/$PROFILE}
        if in_head "$src"; then add_item block "$src" "$HOME/$file" "$name"; fi
    done
    for line in "${ptemplates[@]}"; do
        src=${line%%|*}
        dest=${line#*|}
        if in_head "$src"; then add_item template "$src" "$HOME/$dest"; fi
    done
}

# Filter: bringen eine Repo-Fassung in die Form, wie sie unter $HOME liegt (und zurück).
# shellcheck disable=SC2329  # die Filter werden über ihren Namen aufgerufen
f_link() { cat; }
f_block() { awk '{ print }'; }
# shellcheck disable=SC2329
f_tpl() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "${line//@HOME@/"$HOME"}"; done
}
# shellcheck disable=SC2329
f_tpl_back() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "${line//"$HOME"/@HOME@}"; done
}

# Stimmt der Inhalt mit irgendeinem früheren Stand der Datei im Repo überein?
history_match() { # Quelle Kandidat Filter
    local src=$1 cand=$2 filter=$3 c old="$TMP/old"
    while IFS= read -r c; do
        if g cat-file blob "$c:$src" 2>/dev/null | "$filter" >"$old"; then
            if cmp -s "$old" "$cand"; then return 0; fi
        fi
    done < <(g rev-list HEAD -- "$src")
    return 1
}

# Schlägt einen Vorschlag für Index i vor: Basis ist der frühere Repo-Stand mit dem kleinsten Diff zur lokalen
# Fassung (HEAD ist ein Kandidat), Inhalt der Dreiwege-Merge aus lokal, Basis und HEAD. So dreht ein Vorschlag
# nie Änderungen zurück, die das Repo inzwischen hat.
make_proposal() { # Index Filter (bringt Repo-Stände in die Form von LOCALF)
    local i=$1 f=$2 src=${IT_SRC[$1]} c n best=-1 base="$TMP/base.$1" old="$TMP/old"
    while IFS= read -r c; do
        if g cat-file blob "$c:$src" 2>/dev/null | "$f" >"$old"; then
            n=$(diff "$old" "${LOCALF[$i]}" | grep -c '^[<>]' || true)
            if [ "$best" -lt 0 ] || [ "$n" -lt "$best" ]; then
                best=$n
                cp "$old" "$base"
            fi
        fi
    done < <(g rev-list HEAD -- "$src")
    if [ "$best" -lt 0 ]; then
        PROPSKIP[i]="kein Repo-Stand dieser Datei gefunden"
    elif git merge-file -p "${LOCALF[$i]}" "$base" "${RAWF[$i]}" >"$TMP/prop.$i" 2>/dev/null; then
        if cmp -s "$TMP/prop.$i" "${RAWF[$i]}"; then
            PROPSKIP[i]="die lokale Änderung steckt schon im Repo (steht eine Klon-Datei auf älterem Stand, hilft git -C $REPO restore <datei>)"
        else
            PROPF[i]="$TMP/prop.$i"
        fi
    else
        PROPSKIP[i]="Repo hat sich ebenfalls geändert, Merge-Konflikt"
    fi
}

classify_plain() { # Index Filter Rückfilter (Klassen link und template)
    local i=$1 f=$2 u=$3 src dest foreign="" own=0
    src=${IT_SRC[$i]}
    dest=${IT_DEST[$i]}
    RAWF[i]="$TMP/raw.$i"
    g cat-file blob "HEAD:$src" >"${RAWF[$i]}"
    AFTER[i]="$TMP/head.$i"
    "$f" <"${RAWF[$i]}" >"${AFTER[$i]}"
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        ST[i]=fehlt
        return 0
    fi
    if [ -d "$dest" ]; then
        ST[i]=problem
        ART[i]="Verzeichnis"
        NOTE[i]="ist ein Verzeichnis, erwartet war eine Datei"
        return 0
    fi
    if [ ! -e "$dest" ]; then
        ST[i]=fehlt
        return 0
    fi
    case "${IT_CLASS[$i]}" in
    template) ART[i]="Vorlage" ;;
    *)
        if [ -L "$dest" ]; then
            if [ "$(readlink -f "$dest")" = "$(readlink -f "$REPO/$src")" ]; then
                ART[i]="Link"
                own=1
            else
                foreign=$(readlink "$dest")
                ART[i]="Link auf anderen Klon"
            fi
        else
            ART[i]="Kopie"
        fi
        ;;
    esac
    if cmp -s "$dest" "${AFTER[$i]}"; then
        ST[i]=gleich
        if [ -n "$foreign" ]; then NOTES+=("${IT_LABEL[$i]} ist ein Link auf $foreign, nicht auf diesen Klon"); fi
        return 0
    fi
    if [ "$own" = 0 ] && history_match "$src" "$dest" "$f"; then
        if [ -n "$foreign" ]; then
            ST[i]=problem
            NOTE[i]="Repo neuer, aber der Link zeigt auf $foreign (anderer Klon) und wird nicht umgelegt"
        else
            ST[i]=neuer
        fi
        return 0
    fi
    # Ein Link in den eigenen Klon liest den Arbeitsbaum; der gehört git und wird nie beschrieben.
    ST[i]=anders
    LOCALF[i]="$TMP/local.$i"
    "$u" <"$dest" >"${LOCALF[$i]}"
    if [ "$own" = 1 ]; then NOTE[i]="Arbeitsbaum des Klons weicht von HEAD ab"; fi
    if [ -n "$foreign" ]; then NOTE[i]="Link zeigt auf $foreign (anderer Klon)"; fi
    make_proposal "$i" f_link
}

block_marks_ok() { # Datei Name: genau ein BEGIN vor genau einem END
    local file=$1 name=$2 nb ne lb le
    nb=$(grep -cxF "# BEGIN $name" "$file" || true)
    ne=$(grep -cxF "# END $name" "$file" || true)
    [ "$nb" = 1 ] && [ "$ne" = 1 ] || return 1
    lb=$(grep -nxF "# BEGIN $name" "$file" | cut -d: -f1)
    le=$(grep -nxF "# END $name" "$file" | cut -d: -f1)
    [ "$lb" -lt "$le" ]
}

block_extract() { # Datei Name: Inhalt zwischen den Markierungen
    awk -v name="$2" '
        $0 == "# END " name { f = 0 }
        f { print }
        $0 == "# BEGIN " name { f = 1 }
    ' "$1"
}

classify_block() {
    local i=$1 src dest name
    src=${IT_SRC[$i]}
    dest=${IT_DEST[$i]}
    name=${IT_NAME[$i]}
    ART[i]="Block"
    AFTER[i]="$TMP/head.$i"
    g cat-file blob "HEAD:$src" | f_block >"${AFTER[$i]}"
    RAWF[i]=${AFTER[$i]}
    if [ ! -f "$dest" ] || ! grep -qxF "# BEGIN $name" "$dest"; then
        ST[i]=fehlt
        return 0
    fi
    if ! block_marks_ok "$dest" "$name"; then
        ST[i]=problem
        NOTE[i]="Markierungen # BEGIN/# END $name fehlen oder sind doppelt, bitte von Hand prüfen"
        return 0
    fi
    block_extract "$dest" "$name" >"$TMP/local.$i"
    if cmp -s "$TMP/local.$i" "${AFTER[$i]}"; then
        ST[i]=gleich
    elif history_match "$src" "$TMP/local.$i" f_block; then
        ST[i]=neuer
    else
        ST[i]=anders
        LOCALF[i]="$TMP/local.$i"
        make_proposal "$i" f_block
    fi
}

# shellcheck disable=SC2016  # jq-Programm, keine Shell-Variablen
MERGE_JQ='
def lookup($o; $p; $at):
    if ($p | length) == 0 then {present: true, v: $o, at: $at}
    elif ($o | type) != "object" then {present: true, v: $o, at: $at, blocked: true}
    elif ($o | has($p[0])) then lookup($o[$p[0]]; $p[1:]; $at + [$p[0]])
    else {present: false} end;
$R[0] as $r | $L[0] as $l
| [ $r | paths(type != "object" or length == 0) | select(all(.[]; type == "string")) ]
| map(. as $p
    | ($r | getpath($p)) as $rv
    | lookup($l; $p; []) as $x
    | {path: $p, local: $x.v, at: $x.at, status:
        (if ($x.present | not) then "fehlt"
         elif ($x.blocked // false) then "anders"
         elif $x.v == $rv then "gleich"
         elif ($rv | type) == "object" and ($x.v | type) == "object" then "gleich"
         elif any($H[]; lookup(.; $p; []) as $y | ($y.present and (($y.blocked // false) | not) and $y.v == $x.v)) then "alt"
         else "anders" end)})
'

classify_merge() {
    local i=$1 src dest c keys
    local hist="$TMP/hist.$i" an="$TMP/an.$i"
    src=${IT_SRC[$i]}
    dest=${IT_DEST[$i]}
    ART[i]="Einstellungen"
    AFTER[i]="$TMP/head.$i"
    g cat-file blob "HEAD:$src" >"${AFTER[$i]}"
    RAWF[i]="$TMP/raw.$i"
    jq . "${AFTER[$i]}" >"${RAWF[$i]}"
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        ST[i]=fehlt
        return 0
    fi
    if [ ! -e "$dest" ]; then
        ST[i]=fehlt
        return 0
    fi
    if ! jq -e 'type == "object"' "$dest" >/dev/null 2>&1; then
        ST[i]=problem
        NOTE[i]="kein gültiges JSON-Objekt, bitte von Hand prüfen"
        return 0
    fi
    : >"$hist"
    while IFS= read -r c; do
        g cat-file blob "$c:$src" 2>/dev/null | jq -c . >>"$hist" 2>/dev/null || true
    done < <(g rev-list HEAD -- "$src")
    jq -n --slurpfile L "$dest" --slurpfile H "$hist" --slurpfile R "${AFTER[$i]}" "$MERGE_JQ" >"$an"
    if [ "$(jq '[.[] | select(.status == "anders")] | length' "$an")" -gt 0 ]; then
        ST[i]=anders
        SUM[i]="Schlüssel $(jq -r '[.[] | select(.status == "anders") | (.at | join("."))] | unique | join(", ")' "$an")"
        jq '[.[] | select(.status == "anders")]' "$an" >"$TMP/anders.$i"
        PROPF[i]="$TMP/prop.$i"
        LOCALF[i]=${PROPF[$i]}
        jq --slurpfile A "$TMP/anders.$i" 'reduce $A[0][] as $x (.; setpath($x.at; $x.local))' "${AFTER[$i]}" >"${PROPF[$i]}"
    else
        keys=$(jq -r '[.[] | select(.status != "gleich") | (.path | join("."))] | join(", ")' "$an")
        if [ -n "$keys" ]; then
            ST[i]=neuer
            NOTE[i]="Schlüssel $keys"
        else
            ST[i]=gleich
        fi
    fi
}

# Durch einen Symlink wird nie geschrieben (zum Beispiel ~/.bashrc als Link in ein Dotfiles-Repo).
guard_symlink() { # Index
    local i=$1 dest=${IT_DEST[$1]}
    if [ "${IT_CLASS[$i]}" = link ] || [ ! -L "$dest" ]; then return 0; fi
    if [ "${ST[$i]}" = neuer ] || [ "${ST[$i]}" = fehlt ]; then
        ST[i]=problem
        NOTE[i]="Ziel ist ein Symlink (-> $(readlink "$dest")), nichts geschrieben"
    fi
}

classify_items() {
    local i
    for i in "${!IT_CLASS[@]}"; do
        case "${IT_CLASS[$i]}" in
        link) classify_plain "$i" f_link f_link ;;
        template) classify_plain "$i" f_tpl f_tpl_back ;;
        block) classify_block "$i" ;;
        merge) classify_merge "$i" ;;
        esac
        guard_symlink "$i"
        if [ "${ST[$i]}" = anders ]; then
            if [ -n "$FF_CHANGED" ] && printf '%s\n' "$FF_CHANGED" | grep -qxF -- "${IT_SRC[$i]}"; then
                NOTE[i]="${NOTE[$i]:+${NOTE[$i]}; }Repo hat sich ebenfalls geändert"
            fi
        fi
    done
}

# ---------------------------------------------------------------- Nachziehen und Anlegen

backup_path() { # wie die Installer: ~/.shdft-backup/<Zeitstempel>/<Pfad unter $HOME>; sichert den Inhalt
    local path=$1 rel=${1#"$HOME"/} dest
    if [ -z "$BACKUP" ]; then BACKUP="$HOME/.shdft-backup/$(date +%Y%m%d-%H%M%S)"; fi
    dest="$BACKUP/$rel"
    if [ -e "$dest" ] || [ -L "$dest" ]; then return 0; fi
    mkdir -p "$(dirname "$dest")" || return 1
    if [ -L "$path" ] && [ ! -e "$path" ]; then
        cp -P -p "$path" "$dest"
    else
        cp -L -p "$path" "$dest"
    fi
}

# Schreibt nur, wenn das Ziel kein Symlink ist und die Sicherung des bisherigen Inhalts gelang.
# set -e gilt in den aufrufenden if-Bedingungen nicht, darum prüft alles hier ausdrücklich.
write_over() { # Quelle Ziel
    local tmp=$1 dest=$2
    if [ -L "$dest" ]; then
        APPLY_ERR="Ziel ist ein Symlink, nichts geschrieben"
        return 1
    fi
    if [ -e "$dest" ] && ! backup_path "$dest"; then
        APPLY_ERR="Sicherung fehlgeschlagen, nichts überschrieben"
        return 1
    fi
    if ! mkdir -p "$(dirname "$dest")" || ! cat "$tmp" >"$dest"; then
        APPLY_ERR="Schreiben fehlgeschlagen"
        return 1
    fi
}

block_write() { # Index: Block ersetzen oder anhängen wie install.sh
    local i=$1 file=${IT_DEST[$1]} name=${IT_NAME[$1]} content=${AFTER[$1]} tmp
    tmp=$(mktemp "$TMP/blk.XXXXXX")
    if [ -e "$file" ] && grep -qxF "# BEGIN $name" "$file"; then
        awk -v name="$name" -v content="$content" '
            $0 == "# BEGIN " name { print; while ((getline line < content) > 0) print line; skip = 1; next }
            $0 == "# END " name { skip = 0 }
            !skip { print }
        ' "$file" >"$tmp" || return 1
    else
        {
            if [ -e "$file" ]; then cat "$file"; fi
            printf '\n# BEGIN %s\n' "$name"
            cat "$content"
            printf '# END %s\n' "$name"
        } >"$tmp" || return 1
    fi
    write_over "$tmp" "$file"
}

apply_one() { # Index
    local i=$1 dest=${IT_DEST[$1]} tmp
    APPLY_ERR=""
    case "${IT_CLASS[$i]}" in
    link)
        if [ "${ST[$i]}" = fehlt ]; then
            if [ -L "$dest" ] && ! backup_path "$dest"; then
                APPLY_ERR="Sicherung fehlgeschlagen, nichts überschrieben"
                return 1
            fi
            if ! mkdir -p "$(dirname "$dest")" || ! ln -sfn "$REPO/${IT_SRC[$i]}" "$dest"; then
                APPLY_ERR="Link konnte nicht angelegt werden"
                return 1
            fi
        else
            write_over "${AFTER[$i]}" "$dest" || return 1
        fi
        ;;
    template) write_over "${AFTER[$i]}" "$dest" || return 1 ;;
    block) block_write "$i" || return 1 ;;
    merge)
        tmp=$(mktemp "$TMP/mrg.XXXXXX")
        if [ "${ST[$i]}" = fehlt ]; then
            jq . "${AFTER[$i]}" >"$tmp" || return 1
        else
            jq -s '.[0] * .[1]' "$dest" "${AFTER[$i]}" >"$tmp" || return 1
        fi
        write_over "$tmp" "$dest" || return 1
        ;;
    esac
}

apply_actions() {
    local i
    ANY_PRESENT=0
    for i in "${!IT_CLASS[@]}"; do
        if [ "${ST[$i]}" != fehlt ]; then ANY_PRESENT=1; fi
    done
    for i in "${!IT_CLASS[@]}"; do
        case "${ST[$i]}" in
        gleich) N_GLEICH=$((N_GLEICH + 1)) ;;
        neuer | fehlt)
            if [ "${ST[$i]}" = fehlt ] && [ "$ANY_PRESENT" = 0 ]; then
                N_MISSING=$((N_MISSING + 1))
            elif [ "$ALLOW_WRITE" = 0 ]; then
                HELD+=("${IT_LABEL[$i]} (${ST[$i]/neuer/Repo neuer})")
            elif [ "$OPT_DRY" = 1 ] || apply_one "$i"; then
                if [ "${ST[$i]}" = neuer ]; then
                    N_PULLED=$((N_PULLED + 1))
                    PULLED+=("${IT_LABEL[$i]} (Repo neuer${NOTE[$i]:+: ${NOTE[$i]}})")
                else
                    N_CREATED=$((N_CREATED + 1))
                    CREATED+=("${IT_LABEL[$i]}")
                fi
            else
                ST[i]=problem
                NOTE[i]="${APPLY_ERR:-Schreiben fehlgeschlagen}"
                N_DEV=$((N_DEV + 1))
            fi
            ;;
        anders | problem) N_DEV=$((N_DEV + 1)) ;;
        esac
    done
    if [ "${#HELD[@]}" -gt 0 ]; then
        NOTES+=("Nachziehen und Anlegen ausgesetzt, die Dateien werden nur verglichen: $REPO_MSG")
    fi
}

# ---------------------------------------------------------------- Sicherheitsprüfung

mask() { printf '%s***' "${1:0:4}"; }
mask_mail() { printf '***@%s' "${1#*@}"; }

is_placeholder() { # Wert: $NAME, ${NAME}, <...>, @NAME@ oder strata-local
    local v=$1 re
    for re in '^\$[A-Za-z_][A-Za-z0-9_]*$' '^\$\{[A-Za-z_][A-Za-z0-9_]*\}$' '^<[^<>]+>$' '^@[A-Za-z0-9_]+@$'; do
        if [[ $v =~ $re ]]; then return 0; fi
    done
    [ "$v" = strata-local ]
}

scan_text() { # Text: je Fund eine Zeile "Art<TAB>Auszug"
    local text=$1 entry kind rest ci re m val rest_text after nc=0
    if shopt -q nocasematch; then nc=1; fi
    for entry in "${SCAN_PATTERNS[@]}"; do
        kind=${entry%%|*}
        rest=${entry#*|}
        ci=${rest%%|*}
        re=${rest#*|}
        if [ "$ci" = 1 ]; then shopt -s nocasematch; else shopt -u nocasematch; fi
        if [[ $text =~ $re ]]; then printf '%s\t%s\n' "$kind" "$(mask "${BASH_REMATCH[0]}")"; fi
    done
    shopt -s nocasematch
    rest_text=$text
    while [[ $rest_text =~ $SCAN_PASSWORD_RE ]]; do
        m=${BASH_REMATCH[0]}
        val=${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
        if ! is_placeholder "$val"; then
            printf 'Kennwort\t%s\n' "$(mask "$m")"
            break
        fi
        rest_text=${rest_text#*"$m"}
    done
    rest_text=$text
    while [[ $rest_text =~ $SCAN_MAIL_RE ]]; do
        m=${BASH_REMATCH[0]}
        after=${rest_text#*"$m"}
        # git@host:pfad ist die scp-Form eines Klons, keine Mailadresse
        if [[ $m == *@users.noreply.github.com || $m == noreply@* || $after =~ ^:[^[:space:]] ]]; then
            rest_text=$after
            continue
        fi
        printf 'Mailadresse\t%s\n' "$(mask_mail "$m")"
        break
    done
    if [ "$nc" = 1 ]; then shopt -s nocasematch; else shopt -u nocasematch; fi
}

scan_item() { # Index: prüft nur die gegenüber HEAD neu hinzugekommenen Zeilen; Funde in $TMP/find.<i>
    local i=$1 line n text kind excerpt
    : >"$TMP/find.$i"
    : >"$TMP/flag.$i"
    while IFS= read -r line || [ -n "$line" ]; do
        n=${line%%:*}
        text=${line#*:}
        while IFS=$'\t' read -r kind excerpt; do
            [ -n "$kind" ] || continue
            printf '%s\t%s\t%s\n' "$n" "$kind" "$excerpt" >>"$TMP/find.$i"
            printf '%s\n' "$text" >>"$TMP/flag.$i"
        done < <(scan_text "$text")
    done < <(diff --old-line-format= --unchanged-line-format= --new-line-format='%dn:%L' "${RAWF[$i]}" "${PROPF[$i]:-${LOCALF[$i]}}" || true)
}

# ---------------------------------------------------------------- Schritt 3: Vorschlag

is_noreply() { case "${1,,}" in ?*@users.noreply.github.com) return 0 ;; esac; return 1; }

noreply_login() { # <id>+<login>@users.noreply.github.com oder <login>@users...: der Login
    local l=${1%@users.noreply.github.com}
    l=${l#*+}
    printf '%s' "${l,,}"
}

origin_owner() { # Besitzer aus der origin-URL (github.com/<besitzer>/... oder git@github.com:<besitzer>/...)
    local url re='github\.com[:/]+([^/]+)/'
    url=$(g config --get remote.origin.url 2>/dev/null || true)
    if [[ $url =~ $re ]]; then printf '%s' "${BASH_REMATCH[1],,}"; fi
}

# Setzt ID_NAME und ID_EMAIL, sonst Rückgabe 1. Nie die globale Git-Identität, nie ein fremder Autor:
# 1. Repo-Konfiguration (git config --local), nur mit Noreply-Adresse
# 2. SHDFT_AUTHOR="Name <adresse>", nur mit Noreply-Adresse
# 3. jüngster Commit auf origin/main, dessen Noreply-Adresse den Besitzer der origin-URL als Login trägt
git_identity() {
    local n e owner re='^(.+) <([^<>]+)>$'
    n=$(g config --local --get user.name || true)
    e=$(g config --local --get user.email || true)
    if [ -n "$n" ] && is_noreply "$e"; then
        ID_NAME=$n
        ID_EMAIL=$e
        return 0
    fi
    if [[ ${SHDFT_AUTHOR:-} =~ $re ]] && is_noreply "${BASH_REMATCH[2]}"; then
        ID_NAME=${BASH_REMATCH[1]}
        ID_EMAIL=${BASH_REMATCH[2]}
        return 0
    fi
    owner=$(origin_owner)
    if [ -z "$owner" ]; then return 1; fi
    while IFS=$'\t' read -r n e; do
        if is_noreply "$e" && [ "$(noreply_login "$e")" = "$owner" ]; then
            ID_NAME=$n
            ID_EMAIL=$e
            return 0
        fi
    done < <(g log -n 200 --format='%an%x09%ae' "$REMOTE_REF" 2>/dev/null)
    return 1
}

worktree_of() { # Zweig: Pfad des Arbeitsbaums, falls vorhanden
    g worktree list --porcelain | awk -v b="refs/heads/$1" '
        $1 == "worktree" { p = substr($0, 10) }
        $1 == "branch" && $2 == b { print p; exit }
    '
}

# Gibt einen anderen Zweig shdftupdate/* mit gleichem Stand aus: gleicher Baum auf gleicher Basis, und zwar
# committet gegen committet beziehungsweise vorbereitet (Zweig steht auf der Basis) gegen vorbereitet.
find_duplicate() { # eigener Zweig, Baum, Basis, committet (0 oder 1)
    local own=$1 tree=$2 base=$3 committed=$4 b tip w
    while IFS= read -r b; do
        if [ "$b" = "$own" ]; then continue; fi
        tip=$(g rev-parse "$b^{commit}" 2>/dev/null || true)
        if [ "$committed" = 1 ]; then
            if [ "$tip" != "$base" ] && [ "$(g rev-parse "$b^" 2>/dev/null || true)" = "$base" ] &&
                [ "$(g rev-parse "$b^{tree}" 2>/dev/null || true)" = "$tree" ]; then
                printf '%s\n' "$b"
                return 0
            fi
        elif [ "$tip" = "$base" ]; then
            w=$(worktree_of "$b")
            if [ -d "$w" ] && [ "$(git -C "$w" write-tree 2>/dev/null || true)" = "$tree" ]; then
                printf '%s\n' "$b"
                return 0
            fi
        fi
    done < <(g for-each-ref --format='%(refname:short)' "refs/heads/shdftupdate/")
    return 1
}

discard_worktree() { # Arbeitsbaum und Zweig, die dieser Lauf eben selbst angelegt hat
    case "$1" in
    "$STATE_DIR"/proposals/*) rm -rf "$1" ;;
    esac
    g worktree prune >/dev/null 2>&1 || true
    g branch -D "$2" >/dev/null 2>&1 || true
}

propose() {
    local i cand=() blocked=() skipped=() paths=() ts branch wt n out msg tree base headline dup="" commit_ok=0
    PROPOSAL=()
    for i in "${!IT_CLASS[@]}"; do
        if [ "${ST[$i]}" = anders ]; then
            if [ -n "${PROPSKIP[$i]:-}" ]; then
                skipped+=("$i")
            elif [ -s "$TMP/find.$i" ]; then
                blocked+=("$i")
            else
                cand+=("$i")
            fi
        fi
    done
    if [ $((${#cand[@]} + ${#blocked[@]} + ${#skipped[@]})) = 0 ]; then return 0; fi
    if [ "$OPT_NO_PROPOSE" = 1 ]; then
        PROPOSAL+=("nicht vorgeschlagen: --no-propose")
        return 0
    fi
    if [ "$OPT_DRY" = 1 ]; then
        PROPOSAL+=("nicht vorgeschlagen: Trockenlauf")
        return 0
    fi
    if [ -n "$PROPOSE_REASON" ]; then
        PROPOSAL+=("nicht vorgeschlagen: $PROPOSE_REASON")
        return 0
    fi
    if [ "${#cand[@]}" = 0 ]; then
        if [ "${#skipped[@]}" = 0 ]; then
            PROPOSAL+=("nicht vorgeschlagen: alle abweichenden Dateien haben einen Sicherheitsfund")
        else
            PROPOSAL+=("nicht vorgeschlagen: keine abweichende Datei ist vorschlagbar (Sicherheitsfund, Merge-Konflikt oder schon im Repo)")
        fi
        return 0
    fi

    ts=$(date +%Y%m%d-%H%M%S)
    branch="shdftupdate/$ts"
    wt="$STATE_DIR/proposals/$ts"
    n=1
    while g show-ref --verify --quiet "refs/heads/$branch" || [ -e "$wt" ]; do
        n=$((n + 1))
        branch="shdftupdate/$ts-$n"
        wt="$STATE_DIR/proposals/$ts-$n"
    done
    if ! out=$(g worktree add --quiet --no-track -b "$branch" "$wt" "$REMOTE_REF" 2>&1); then
        PROPOSAL+=("nicht vorgeschlagen: Arbeitsbaum konnte nicht angelegt werden: $(first_line "$out")")
        PROPOSAL_ERROR=1
        return 0
    fi
    for i in "${cand[@]}"; do
        mkdir -p "$wt/$(dirname "${IT_SRC[$i]}")"
        cat "${PROPF[$i]}" >"$wt/${IT_SRC[$i]}"
        paths+=("${IT_SRC[$i]}")
    done
    git -C "$wt" add -- "${paths[@]}"
    tree=$(git -C "$wt" write-tree)
    base=$(g rev-parse "$REMOTE_REF")
    msg="Lokale Änderungen übernehmen: $(join_by ', ' "${paths[@]}")."

    if git_identity; then
        if ! out=$(env GIT_AUTHOR_NAME="$ID_NAME" GIT_AUTHOR_EMAIL="$ID_EMAIL" GIT_COMMITTER_NAME="$ID_NAME" GIT_COMMITTER_EMAIL="$ID_EMAIL" \
            git -C "$wt" -c user.name="$ID_NAME" -c user.email="$ID_EMAIL" -c commit.gpgsign=false commit --quiet -m "$msg" 2>&1); then
            headline="$branch in $wt (Dateien vorbereitet, Commit fehlgeschlagen: $(first_line "$out"))"
            PROPOSAL_ERROR=1
        else
            commit_ok=1
            headline="$branch in $wt (committet)"
        fi
    else
        headline="$branch in $wt (Dateien vorbereitet, nicht committet: keine Noreply-Identität in der Repo-Konfiguration, in SHDFT_AUTHOR oder bei einem Commit des Repo-Besitzers auf $REMOTE_REF)"
    fi
    if [ "$PROPOSAL_ERROR" = 0 ] && dup=$(find_duplicate "$branch" "$tree" "$base" "$commit_ok"); then
        discard_worktree "$wt" "$branch"
        branch=$dup
        wt=$(worktree_of "$dup")
        headline="$branch${wt:+ in $wt} (schon vorbereitet, nichts Neues angelegt)"
    fi
    PROPOSAL+=("$headline")
    PROPOSAL+=("Dateien: $(join_by ', ' "${paths[@]}")")
    if [ "$commit_ok" = 0 ] && [ "$PROPOSAL_ERROR" = 0 ]; then
        PROPOSAL+=("Zum Committen (Name und Noreply-Adresse des Nutzers einsetzen):")
        PROPOSAL+=("  git -C $(printf '%q' "${wt:-$STATE_DIR}") -c user.name=<Name> -c user.email=<id>+<name>@users.noreply.github.com commit -m $(printf '%q' "$msg")")
    fi
    PROPOSAL+=("Zum Veröffentlichen (führt dieses Skript nie aus, nur auf ausdrückliches Wort des Nutzers):")
    PROPOSAL+=("  git -C $(printf '%q' "$REPO") push -u origin $(printf '%q' "$branch")")
    PROPOSAL+=("  ( cd $(printf '%q' "$REPO") && gh pr create --base $MAIN_BRANCH --head $(printf '%q' "$branch") --fill )")
}

# ---------------------------------------------------------------- Schritt 5: Ausgabe

show_diff() { # Index: gekürzter Unified-Diff, Zeilen mit Sicherheitsfund gesperrt
    local i=$1 l t count=0
    while IFS= read -r l; do
        count=$((count + 1))
        if [ "$count" -gt 40 ]; then
            echo "    ... gekürzt"
            break
        fi
        case "$l" in
        '+++'*) printf '    %s\n' "$l" ;;
        '+'*)
            t=${l#+}
            if [ -s "$TMP/flag.$i" ] && grep -qxF -- "$t" "$TMP/flag.$i"; then
                echo "    + [Zeile gesperrt: Sicherheitsfund]"
            else
                printf '    %s\n' "$l"
            fi
            ;;
        *) printf '    %s\n' "$l" ;;
        esac
    done < <(diff -u --label Repo --label lokal "${RAWF[$i]}" "${PROPF[$i]:-${LOCALF[$i]}}" || true)
}

report() {
    local i a d line result found=0 label
    say "Repo:" "$REPO, $BRANCH_LABEL, $REPO_MSG"
    for line in "${NOTES[@]}"; do say "Hinweis:" "$line"; done
    if [ "$OPT_DRY" = 1 ]; then
        say "Dateien:" "$N_GLEICH gleich, $N_PULLED nachzuziehen, $N_CREATED anzulegen, $N_DEV abweichend"
    else
        say "Dateien:" "$N_GLEICH gleich, $N_PULLED nachgezogen, $N_CREATED neu angelegt, $N_DEV abweichend"
    fi
    if [ "$PROFILE" = windows-wsl ]; then
        say "Hinweis:" "Windows-Seite (profiles/windows-wsl/windows/, .wslconfig, install.ps1) wird hier nicht geprüft"
    fi
    if [ "$ANY_PRESENT" = 0 ]; then
        say "Hinweis:" "shdft ist hier nicht eingerichtet, profiles/$PROFILE/install.sh ausführen"
    fi
    label="nachgezogen:"
    if [ "$OPT_DRY" = 1 ]; then label="würde ziehen:"; fi
    for line in "${PULLED[@]}"; do say "$label" "$line"; done
    for line in "${HELD[@]}"; do say "nicht gezogen:" "$line"; done
    label="neu angelegt:"
    if [ "$OPT_DRY" = 1 ]; then label="würde anlegen:"; fi
    for line in "${CREATED[@]}"; do say "$label" "$line"; done
    for i in "${!IT_CLASS[@]}"; do
        case "${ST[$i]}" in
        anders)
            a=$(diff "${RAWF[$i]}" "${PROPF[$i]:-${LOCALF[$i]}}" | grep -c '^>' || true)
            d=$(diff "${RAWF[$i]}" "${PROPF[$i]:-${LOCALF[$i]}}" | grep -c '^<' || true)
            result="lokal anders: ${SUM[$i]:-+$a/-$d Zeilen}"
            if [ -n "${NOTE[$i]:-}" ]; then result+=" (${NOTE[$i]})"; fi
            if [ -n "${PROPSKIP[$i]:-}" ]; then result+="; nicht vorgeschlagen: ${PROPSKIP[$i]}"; fi
            say "abweichend:" "${IT_LABEL[$i]} [${ART[$i]}] - $result"
            if [ "$OPT_VERBOSE" = 1 ]; then show_diff "$i"; fi
            ;;
        problem) say "abweichend:" "${IT_LABEL[$i]} [${ART[$i]:-Datei}] - ${NOTE[$i]:-unbekannter Fehler}" ;;
        esac
    done
    for i in "${!IT_CLASS[@]}"; do
        if [ "${ST[$i]}" = anders ] && [ -s "$TMP/find.$i" ]; then
            found=1
            while IFS=$'\t' read -r a d line; do
                say "Sicherheit:" "${IT_LABEL[$i]} Zeile $a: $d ($line), Datei bleibt aus dem Vorschlag"
            done <"$TMP/find.$i"
        fi
    done
    if [ "${#PROPOSAL[@]}" -gt 0 ]; then
        say "Vorschlag:" "${PROPOSAL[0]}"
        for line in "${PROPOSAL[@]:1}"; do say "" "$line"; done
    fi
    RESULT_FOUND=$found
}

local_result() { # setzt RC und gibt die Ergebniszeile aus
    local result
    if [ "$N_DEV" -gt 0 ] || [ "$REPO_PROBLEM" = 1 ] || [ "$RESULT_FOUND" = 1 ] || [ "$PROPOSAL_ERROR" = 1 ]; then
        result="Abweichungen gemeldet"
        RC=1
    elif [ "$ANY_PRESENT" = 0 ]; then
        result="nicht eingerichtet"
    elif [ "$OPT_DRY" = 1 ] && [ $((N_PULLED + N_CREATED)) -gt 0 ]; then
        result="würde nachziehen"
    elif [ $((N_PULLED + N_CREATED)) -gt 0 ] || [ "$REPO_STATE" = aktualisiert ]; then
        result="nachgezogen"
    else
        result="aktuell"
    fi
    say "Ergebnis:" "$result"
}

run_local() {
    local i
    HOST=$(host_name)
    echo "== $HOST ($PROFILE) =="
    if ! command -v git >/dev/null 2>&1 || ! find_repo; then
        say "Repo:" "kein shdft-Repo auf diesem Rechner"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "Fehler: jq fehlt (sudo apt install jq / sudo pacman -S jq)." >&2
        exit 2
    fi
    NOTES=() PULLED=() CREATED=() HELD=() PROPOSAL=() PROPOSAL_ERROR=0
    N_GLEICH=0 N_PULLED=0 N_CREATED=0 N_DEV=0 N_MISSING=0
    BACKUP="" ANY_PRESENT=0 RESULT_FOUND=0
    step_repo
    build_items
    classify_items
    apply_actions
    for i in "${!IT_CLASS[@]}"; do
        if [ "${ST[$i]}" = anders ]; then scan_item "$i"; fi
    done
    propose
    report
    local_result
}

main() {
    local fwd=() self alias hosts=() out rc last
    parse_args "$@"
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    export GIT_TERMINAL_PROMPT=0
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    CONFIG_DIR=${SHDFT_CONFIG_DIR:-$HOME/.config/shdft}
    STATE_DIR=${SHDFT_STATE_DIR:-$HOME/.local/state/shdft}
    RC=0
    detect_profile
    run_local

    [ "$OPT_LOCAL" = 0 ] || return "$RC"
    [ -f "$CONFIG_DIR/hosts" ] || return "$RC"
    self=${BASH_SOURCE[0]:-}
    [ -f "$self" ] || return "$RC"
    [ "$OPT_DRY" = 0 ] || fwd+=(--dry-run)
    [ "$OPT_NO_PROPOSE" = 0 ] || fwd+=(--no-propose)
    [ "$OPT_VERBOSE" = 0 ] || fwd+=(-v)
    mapfile -t hosts < <(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]].*//' "$CONFIG_DIR/hosts" | grep -v '^$' || true)
    for alias in "${hosts[@]}"; do
        echo
        if [[ ! $alias =~ ^[A-Za-z0-9][A-Za-z0-9._@:-]*$ ]]; then
            echo "== $alias =="
            say "Ergebnis:" "übersprungen, kein gültiger ssh-Alias"
            RC=1
            continue
        fi
        rc=0
        out=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$alias" "bash -s -- --local ${fwd[*]}" <"$self" 2>&1) || rc=$?
        case "$rc" in
        0 | 1)
            printf '%s\n' "$out"
            if [ "$rc" = 1 ]; then RC=1; fi
            ;;
        255)
            echo "== $alias =="
            last=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -n 1 || true)
            say "Ergebnis:" "nicht erreichbar${last:+ ($last)}"
            RC=1
            ;;
        *)
            echo "== $alias =="
            printf '%s\n' "$out"
            say "Ergebnis:" "Fehler (Exit $rc)"
            RC=1
            ;;
        esac
    done
    return "$RC"
}

main "$@"
exit $?
