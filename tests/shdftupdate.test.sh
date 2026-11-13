#!/usr/bin/env bash
# Tests für profiles/shared/shdftupdate.sh: reine bash-Tests mit temporären Repos
# (bare Origin, Klon, Arbeits-HOME), ohne Netzwerk und ohne das echte $HOME.
# shellcheck disable=SC2016  # Shell-Variablen stehen hier absichtlich als Text in Einzelhochkommata
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$HERE/.." && pwd -P)
SCRIPT=${SHDFTUPDATE_SCRIPT:-$ROOT/profiles/shared/shdftupdate.sh}

# Nichts aus der Umgebung des Aufrufers darf in die Tests hineinwirken.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE SHDFT_REPO SHDFT_PROFILE SHDFT_CONFIG_DIR SHDFT_STATE_DIR WSL_DISTRO_NAME
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

BASE=$(mktemp -d "${TMPDIR:-/tmp}/shdftupdate-test.XXXXXX")
trap 'rm -rf "$BASE"' EXIT

# Die globale Git-Identität ist hier absichtlich die "Firmenadresse": sie darf in keinem Vorschlag auftauchen.
CORP_EMAIL="firma@corp.example"
export GIT_CONFIG_GLOBAL="$BASE/gitconfig-global"
export GIT_CONFIG_SYSTEM=/dev/null
printf '[user]\n\tname = Firma\n\temail = %s\n' "$CORP_EMAIL" >"$GIT_CONFIG_GLOBAL"

NOREPLY="Tester <1+tester@users.noreply.github.com>"
PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); }
fail() {
    FAIL=$((FAIL + 1))
    printf 'FEHLER: %s\n' "$1" >&2
    if [ -n "${2:-}" ]; then printf '%s\n' "$2" | sed 's/^/    /' >&2; fi
}
assert_eq() { if [ "$2" = "$3" ]; then pass; else fail "$1" "erwartet: $2
erhalten: $3"; fi; }
assert_rc() { assert_eq "$1 (Exit-Code)" "$2" "$RC"; }
assert_match() { # Beschreibung Regex [Text]
    if printf '%s\n' "${3:-$OUT}" | grep -Eq -- "$2"; then pass; else fail "$1" "gesucht: $2
Ausgabe:
${3:-$OUT}"; fi
}
assert_lacks() { # Beschreibung Text-der-nicht-vorkommen-darf [Text]
    if printf '%s\n' "${3:-$OUT}" | grep -qF -- "$2"; then fail "$1" "unerwartet: $2
Ausgabe:
${3:-$OUT}"; else pass; fi
}
assert_ok() { # Beschreibung Befehl...
    local d=$1
    shift
    if "$@" >/dev/null 2>&1; then pass; else fail "$d" "Befehl schlug fehl: $*"; fi
}
assert_no() { # Beschreibung Befehl...
    local d=$1
    shift
    if "$@" >/dev/null 2>&1; then fail "$d" "Befehl hatte Erfolg: $*"; else pass; fi
}

rep() { printf "%${2}s" '' | tr ' ' "$1"; }
tg() { git -c user.name=Tester -c user.email=1+tester@users.noreply.github.com -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------- Fixtures

write_fixture() { # Verzeichnis Version (1 oder 2)
    local d=$1 v=$2
    mkdir -p "$d/home/.claude" "$d/home/.pi/agent" "$d/home/.agents" "$d/home/.config/herdr" "$d/shell" \
        "$d/profiles/linux/shell" "$d/profiles/windows-wsl/shell" \
        "$d/profiles/windows-wsl/home/.local/bin" "$d/profiles/windows-wsl/home/.local/share/applications"
    mkdir -p "$d/home/.claude/skills"
    printf '# Größe\nklein\n' >"$d/home/.claude/skills/größe.md"
    printf '# Claude\nzeile eins\n' >"$d/home/.claude/CLAUDE.md"
    printf '# Agenten\nregel eins\n' >"$d/home/.agents/AGENTS.md"
    printf '{"theme":"dark","language":"Deutsch"}\n' >"$d/home/.claude/settings.json"
    printf '{"httpIdleTimeoutMs":1800000}\n' >"$d/home/.pi/agent/settings.json"
    printf '[ui]\nname = "x"\n' >"$d/home/.config/herdr/config.toml"
    printf "alias ll='ls -l'\n" >"$d/shell/bashrc-shdft.sh"
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >"$d/profiles/linux/shell/bashrc-profile.sh"
    printf '# login\nexport PATH="$HOME/.local/bin:$PATH"\n' >"$d/profiles/linux/shell/profile-profile.sh"
    printf 'return {}\n' >"$d/profiles/linux/wezterm.lua"
    printf 'export BROWSER="$HOME/.local/bin/win-browser"\n' >"$d/profiles/windows-wsl/shell/bashrc-profile.sh"
    printf 'export BROWSER="$HOME/.local/bin/win-browser"\n' >"$d/profiles/windows-wsl/shell/profile-profile.sh"
    printf '#!/bin/sh\nexit 0\n' >"$d/profiles/windows-wsl/home/.local/bin/win-browser"
    chmod +x "$d/profiles/windows-wsl/home/.local/bin/win-browser"
    printf '[Desktop Entry]\nName=Windows-Browser\nExec=@HOME@/.local/bin/win-browser %%u\n' \
        >"$d/profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in"
    if [ "$v" = 2 ]; then
        printf '# Claude\nzeile eins\nzeile zwei\n' >"$d/home/.claude/CLAUDE.md"
        printf '# Agenten\nregel eins\nregel zwei\n' >"$d/home/.agents/AGENTS.md"
        printf '{"theme":"light","language":"Deutsch","editorMode":"normal"}\n' >"$d/home/.claude/settings.json"
        printf "alias ll='ls -l'\nalias la='ls -la'\n" >"$d/shell/bashrc-shdft.sh"
    fi
}

# origin zeigt auf github.com/<besitzer>/shdft, geholt wird aber aus dem lokalen bare Origin.
set_origin_owner() {
    git -C "$CLONE" config remote.origin.url "https://github.com/$1/shdft.git"
    git -C "$CLONE" config "url.$ORIGIN.insteadOf" "https://github.com/$1/shdft.git"
}

new_sandbox() {
    CASES=$((CASES + 1))
    SB="$BASE/s$CASES"
    ORIGIN="$SB/origin.git"
    SEED="$SB/seed"
    CLONE="$SB/clone"
    H="$SB/home"
    mkdir -p "$SB/bin" "$H"
    git init -q --bare -b main "$ORIGIN"
    git init -q -b main "$SEED"
    write_fixture "$SEED" 1
    git -C "$SEED" add -A
    tg -C "$SEED" commit -q -m "Fixture 1"
    git -C "$SEED" remote add origin "$ORIGIN"
    git -C "$SEED" push -q origin main
    git clone -q "$ORIGIN" "$CLONE"
    set_origin_owner tester
    SUT_ENV=()
    # gh darf nie aufgerufen werden: die Attrappe protokolliert jeden Aufruf.
    printf '#!/bin/sh\necho "$*" >>"%s/gh.log"\n' "$SB" >"$SB/bin/gh"
    chmod +x "$SB/bin/gh"
    PROFILE_T=linux
}

push_v2() {
    write_fixture "$SEED" 2
    git -C "$SEED" add -A
    tg -C "$SEED" commit -q -m "Fixture 2"
    git -C "$SEED" push -q origin main
}

put_block() { # Datei Name Quelle
    {
        printf '\n# BEGIN %s\n' "$2"
        cat "$3"
        printf '# END %s\n' "$2"
    } >>"$1"
}

# Rechner, wie ihn die Installer hinterlassen: Links ins Klon, eine Kopie, Blöcke, gemischte Einstellungen.
install_state() { # [Profil]
    local p=${1:-linux}
    mkdir -p "$H/.claude" "$H/.agents" "$H/.pi/agent" "$H/.config/herdr"
    ln -s "$CLONE/home/.claude/CLAUDE.md" "$H/.claude/CLAUDE.md"
    mkdir -p "$H/.claude/skills"
    ln -s "$CLONE/home/.claude/skills/größe.md" "$H/.claude/skills/größe.md"
    ln -s "$CLONE/home/.config/herdr/config.toml" "$H/.config/herdr/config.toml"
    cp "$CLONE/home/.agents/AGENTS.md" "$H/.agents/AGENTS.md"
    jq '. + {permissions: {allow: ["Bash(ls)"]}}' "$CLONE/home/.claude/settings.json" >"$H/.claude/settings.json"
    jq . "$CLONE/home/.pi/agent/settings.json" >"$H/.pi/agent/settings.json"
    printf '# meine bashrc\nexport FOO=1\n' >"$H/.bashrc"
    put_block "$H/.bashrc" shdft "$CLONE/shell/bashrc-shdft.sh"
    put_block "$H/.bashrc" shdft-profile "$CLONE/profiles/$p/shell/bashrc-profile.sh"
    printf '# mein profile\n' >"$H/.profile"
    put_block "$H/.profile" shdft-profile "$CLONE/profiles/$p/shell/profile-profile.sh"
    if [ "$p" = linux ]; then
        mkdir -p "$H/.config/wezterm"
        ln -s "$CLONE/profiles/linux/wezterm.lua" "$H/.config/wezterm/wezterm.lua"
    else
        mkdir -p "$H/.local/bin" "$H/.local/share/applications"
        ln -s "$CLONE/profiles/windows-wsl/home/.local/bin/win-browser" "$H/.local/bin/win-browser"
        sed "s#@HOME@#$H#g" "$CLONE/profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in" \
            >"$H/.local/share/applications/win-browser.desktop"
    fi
}

run_sut() {
    OUT=$(env HOME="$H" SHDFT_REPO="$CLONE" SHDFT_PROFILE="$PROFILE_T" \
        SHDFT_CONFIG_DIR="$SB/config" SHDFT_STATE_DIR="$SB/state" PATH="$SB/bin:$PATH" "${SUT_ENV[@]}" \
        bash "$SCRIPT" "$@" 2>&1) && RC=0 || RC=$?
}

snapshot() { # Verzeichnis...: Inhalt, Linkziele und Modus ohne .git
    local p f
    for p in "$@"; do
        find "$p" -path "$p/.git" -prune -o \( -type f -o -type l \) -print0 | sort -z |
            while IFS= read -r -d '' f; do
                if [ -L "$f" ]; then
                    printf 'L %s -> %s\n' "$f" "$(readlink "$f")"
                else
                    printf 'F %s %s\n' "$f" "$(sha256sum <"$f" | cut -c1-64)"
                fi
            done
    done
}
clone_state() { printf '%s\n%s\n%s\n' "$(git -C "$CLONE" rev-parse HEAD)" "$(git -C "$CLONE" status --porcelain)" "$(snapshot "$CLONE")"; }

branches() { git -C "$CLONE" for-each-ref --format='%(refname:short)' 'refs/heads/shdftupdate/'; }

# ---------------------------------------------------------------- Fälle

t_gleich() {
    echo "-- 1 gleich"
    new_sandbox
    install_state
    local before
    before=$(snapshot "$H")
    run_sut
    assert_rc "gleich" 0
    assert_match "gleich: Ergebnis aktuell" '^Ergebnis: +aktuell'
    assert_match "gleich: nichts abweichend" '0 abweichend'
    assert_eq "gleich: HOME unverändert" "$before" "$(snapshot "$H")"
    assert_no "gleich: keine Sicherung angelegt" test -e "$H/.shdft-backup"
    assert_no "gleich: kein Vorschlag" test -n "$(branches)"
}

t_repo_neuer() {
    echo "-- 2 Repo neuer"
    new_sandbox
    install_state
    push_v2
    run_sut
    assert_rc "Repo neuer" 0
    assert_match "Repo neuer: Klon aktualisiert" '^Repo: .*aktualisiert [0-9a-f]+\.\.[0-9a-f]+ \(1 Commit\)'
    assert_match "Repo neuer: Kopie nachgezogen" 'nachgezogen: +~/\.agents/AGENTS\.md \(Repo neuer\)'
    assert_match "Repo neuer: Block nachgezogen" 'nachgezogen: +~/\.bashrc \(Block shdft\) \(Repo neuer\)'
    assert_match "Repo neuer: Einstellungen nachgezogen" 'nachgezogen: +~/\.claude/settings\.json \(Repo neuer: Schlüssel '
    assert_match "Repo neuer: Ergebnis" '^Ergebnis: +nachgezogen'
    assert_ok "Repo neuer: Kopie entspricht dem Klon" cmp -s "$H/.agents/AGENTS.md" "$CLONE/home/.agents/AGENTS.md"
    assert_ok "Repo neuer: Block enthält die neue Zeile" grep -q "alias la=" "$H/.bashrc"
    assert_ok "Repo neuer: eigene Zeile der bashrc bleibt" grep -qx 'export FOO=1' "$H/.bashrc"
    assert_eq "Repo neuer: Block nur einmal" 1 "$(grep -cx '# BEGIN shdft' "$H/.bashrc")"
    assert_eq "Repo neuer: theme nachgezogen" light "$(jq -r .theme "$H/.claude/settings.json")"
    assert_eq "Repo neuer: neuer Schlüssel" normal "$(jq -r .editorMode "$H/.claude/settings.json")"
    assert_eq "Repo neuer: lokale Schlüssel bleiben" 'Bash(ls)' "$(jq -r '.permissions.allow[0]' "$H/.claude/settings.json")"
    local saved
    saved=$(find "$H/.shdft-backup" -path '*/.agents/AGENTS.md' | head -n 1)
    assert_ok "Repo neuer: Sicherung der Kopie" test -f "$saved"
    assert_eq "Repo neuer: Sicherung hält den alten Stand" "$(git -C "$SEED" show HEAD~1:home/.agents/AGENTS.md)" "$(cat "$saved")"
    assert_ok "Repo neuer: Sicherung der bashrc" test -f "$(find "$H/.shdft-backup" -name .bashrc | head -n 1)"
    run_sut
    assert_rc "Repo neuer: zweiter Lauf" 0
    assert_match "Repo neuer: zweiter Lauf aktuell" '^Ergebnis: +aktuell'
}

t_lokal_anders() {
    echo "-- 3 lokal anders"
    new_sandbox
    install_state
    printf 'lokale Zeile\n' >>"$H/.agents/AGENTS.md"
    sed -i "s/alias ll='ls -l'/alias ll='ls -lah'/" "$H/.bashrc"
    jq '.theme = "weird"' "$H/.claude/settings.json" >"$SB/s.json" && cat "$SB/s.json" >"$H/.claude/settings.json"
    printf 'lokal im Klon\n' >>"$CLONE/home/.claude/CLAUDE.md"
    local before_home before_clone
    before_home=$(snapshot "$H")
    before_clone=$(clone_state)
    run_sut
    assert_rc "lokal anders" 1
    assert_eq "lokal anders: HOME unverändert (nichts überschrieben)" "$before_home" "$(snapshot "$H")"
    assert_eq "lokal anders: Klon unverändert" "$before_clone" "$(clone_state)"
    assert_match "lokal anders: Kopie gemeldet" 'abweichend: +~/\.agents/AGENTS\.md \[Kopie\] - lokal anders: \+1/-0 Zeilen'
    assert_match "lokal anders: Block gemeldet" 'abweichend: +~/\.bashrc \(Block shdft\) \[Block\] - lokal anders'
    assert_match "lokal anders: Einstellungen gemeldet" 'abweichend: +~/\.claude/settings\.json \[Einstellungen\] - lokal anders: Schlüssel theme'
    assert_match "lokal anders: Link-Datei mit Klon-Änderung gemeldet" 'abweichend: +~/\.claude/CLAUDE\.md \[Link\] - lokal anders'
    assert_match "lokal anders: Ergebnis" '^Ergebnis: +Abweichungen gemeldet'
    local b wt
    b=$(branches)
    assert_match "lokal anders: Zweig angelegt" '^shdftupdate/[0-9]{8}-[0-9]{6}$' "$b"
    assert_eq "lokal anders: genau ein Zweig" 1 "$(printf '%s\n' "$b" | grep -c .)"
    assert_eq "lokal anders: Autor ist die Noreply-Adresse" "1+tester@users.noreply.github.com" "$(git -C "$CLONE" log -1 --format=%ae "$b")"
    assert_eq "lokal anders: Committer ist die Noreply-Adresse" "1+tester@users.noreply.github.com" "$(git -C "$CLONE" log -1 --format=%ce "$b")"
    assert_lacks "lokal anders: keine Firmenadresse im Commit" "$CORP_EMAIL" "$(git -C "$CLONE" log -1 --format='%an %ae %cn %ce%n%B' "$b")"
    assert_lacks "lokal anders: kein Co-Autor" "Co-authored-by" "$(git -C "$CLONE" log -1 --format=%B "$b")"
    assert_match "lokal anders: Commit-Meldung" '^Lokale Änderungen übernehmen: ' "$(git -C "$CLONE" log -1 --format=%s "$b")"
    assert_eq "lokal anders: Basis ist origin/main" "$(git -C "$CLONE" rev-parse origin/main)" "$(git -C "$CLONE" rev-parse "$b^")"
    assert_eq "lokal anders: vier Dateien im Commit" \
        "home/.agents/AGENTS.md
home/.claude/CLAUDE.md
home/.claude/settings.json
shell/bashrc-shdft.sh" "$(git -C "$CLONE" show --name-only --format= "$b" | sort)"
    assert_match "lokal anders: Kopie im Vorschlag" 'lokale Zeile' "$(git -C "$CLONE" show "$b:home/.agents/AGENTS.md")"
    assert_match "lokal anders: Klon-Änderung im Vorschlag" 'lokal im Klon' "$(git -C "$CLONE" show "$b:home/.claude/CLAUDE.md")"
    assert_match "lokal anders: Block im Vorschlag" "alias ll='ls -lah'" "$(git -C "$CLONE" show "$b:shell/bashrc-shdft.sh")"
    assert_eq "lokal anders: Einstellungen mit lokalem Wert" weird "$(git -C "$CLONE" show "$b:home/.claude/settings.json" | jq -r .theme)"
    assert_eq "lokal anders: nur lokale Schlüssel bleiben draußen" null "$(git -C "$CLONE" show "$b:home/.claude/settings.json" | jq -r .permissions)"
    wt=$(git -C "$CLONE" worktree list --porcelain | awk -v b="refs/heads/$b" '$1=="worktree"{p=substr($0,10)} $1=="branch"&&$2==b{print p}')
    assert_ok "lokal anders: Arbeitsbaum liegt unter SHDFT_STATE_DIR" test -d "$SB/state/proposals" -a -d "$wt"
    assert_match "lokal anders: Push-Befehl als Text" "git -C $CLONE push -u origin $b"
    assert_match "lokal anders: gh-Befehl als Text" 'gh pr create --base main --head shdftupdate/'
    assert_no "lokal anders: gh nie aufgerufen" test -e "$SB/gh.log"

    run_sut
    assert_match "lokal anders: zweiter Lauf erkennt den Vorschlag" 'schon vorbereitet, nichts Neues angelegt'
    assert_eq "lokal anders: weiterhin genau ein Zweig" 1 "$(branches | grep -c .)"
}

t_beide_geaendert() {
    echo "-- 3b lokal anders und Repo hat sich ebenfalls geändert: Merge-Konflikt"
    new_sandbox
    install_state
    printf 'lokale Zeile\n' >>"$H/.agents/AGENTS.md"
    push_v2
    run_sut
    assert_rc "Konflikt" 1
    assert_match "Konflikt: Hinweis" 'abweichend: +~/\.agents/AGENTS\.md \[Kopie\] - lokal anders: .*\(Repo hat sich ebenfalls geändert\); nicht vorgeschlagen: Repo hat sich ebenfalls geändert, Merge-Konflikt'
    assert_eq "Konflikt: Kopie nie überschrieben" "# Agenten
regel eins
lokale Zeile" "$(cat "$H/.agents/AGENTS.md")"
    assert_match "Konflikt: Veraltetes wird trotzdem nachgezogen" 'nachgezogen: +~/\.bashrc \(Block shdft\)'
    assert_match "Konflikt: Klon trotzdem aktualisiert" 'aktualisiert [0-9a-f]+\.\.[0-9a-f]+'
    assert_match "Konflikt: nichts vorschlagbar" 'nicht vorgeschlagen: keine abweichende Datei ist vorschlagbar'
    assert_eq "Konflikt: kein Zweig" "" "$(branches)"

    echo "-- 3c lokal anders und Repo hat sich ebenfalls geändert: sauberer Merge, nie Upstream zurückdrehen"
    new_sandbox
    install_state
    printf 'lokale Zeile\n' | cat - "$CLONE/home/.agents/AGENTS.md" >"$H/.agents/AGENTS.md"
    push_v2
    run_sut
    assert_rc "Merge" 1
    local b
    b=$(branches)
    assert_match "Merge: Vorschlag entsteht" 'Vorschlag: +shdftupdate/'
    assert_eq "Merge: Vorschlag gegen origin/main enthält nur die lokale Zeile" "1	0	home/.agents/AGENTS.md" "$(git -C "$CLONE" diff --numstat origin/main "$b")"
    assert_eq "Merge: lokale Zeile und Repo-Stand" "lokale Zeile
# Agenten
regel eins
regel zwei" "$(git -C "$CLONE" show "$b:home/.agents/AGENTS.md")"
    assert_eq "Merge: Kopie selbst bleibt unverändert" "lokale Zeile
# Agenten
regel eins" "$(cat "$H/.agents/AGENTS.md")"
}

t_nachziehbedingung() {
    echo "-- 4c Nachziehen nur auf main mit HEAD == origin/main"
    local before
    # anderer Zweig, HEAD aktuell: die Datei ist gegenüber HEAD veraltet, wird aber nicht angefasst
    new_sandbox
    install_state
    push_v2
    git -C "$CLONE" fetch -q
    git -C "$CLONE" checkout -q -b feature
    git -C "$CLONE" merge -q --ff-only origin/main
    before=$(snapshot "$H")
    run_sut
    assert_rc "Zweig mit veralteter Kopie" 1
    assert_match "Zweig: ausgesetzt gemeldet" 'Hinweis: +Nachziehen und Anlegen ausgesetzt, die Dateien werden nur verglichen: Zweig feature'
    assert_match "Zweig: Datei als nicht gezogen" 'nicht gezogen: +~/\.agents/AGENTS\.md \(Repo neuer\)'
    assert_eq "Zweig: HOME unverändert" "$before" "$(snapshot "$H")"
    assert_no "Zweig: keine Sicherung" test -e "$H/.shdft-backup"
    # main, aber HEAD voraus
    new_sandbox
    install_state
    push_v2
    git -C "$CLONE" fetch -q
    git -C "$CLONE" merge -q --ff-only origin/main
    printf 'lokal\n' >"$CLONE/LOKAL.md"
    git -C "$CLONE" add LOKAL.md
    tg -C "$CLONE" commit -q -m lokal
    before=$(snapshot "$H")
    run_sut
    assert_rc "voraus mit veralteter Kopie" 1
    assert_match "voraus: nicht gezogen" 'nicht gezogen: +~/\.agents/AGENTS\.md \(Repo neuer\)'
    assert_eq "voraus: HOME unverändert" "$before" "$(snapshot "$H")"
    # offline auf main: Nachziehen gegen den lokalen Stand bleibt erlaubt
    new_sandbox
    install_state
    push_v2
    git -C "$CLONE" fetch -q
    git -C "$CLONE" merge -q --ff-only origin/main
    git -C "$CLONE" remote set-url origin "$SB/gibt-es-nicht.git"
    run_sut
    assert_rc "offline mit veralteter Kopie" 1
    assert_match "offline: Meldung" 'Offline oder origin nicht erreichbar'
    assert_match "offline: trotzdem nachgezogen" 'nachgezogen: +~/\.agents/AGENTS\.md \(Repo neuer\)'
    assert_ok "offline: Kopie entspricht dem Klon" cmp -s "$H/.agents/AGENTS.md" "$CLONE/home/.agents/AGENTS.md"
}

t_symlink() {
    echo "-- 1 nie durch einen Symlink schreiben"
    # Link in den Klon: Arbeitsbaum auf einem älteren Repo-Stand ist "lokal anders", nie "Repo neuer"
    new_sandbox
    install_state
    push_v2
    git -C "$CLONE" fetch -q
    git -C "$CLONE" merge -q --ff-only origin/main
    git -C "$CLONE" show HEAD~1:home/.claude/CLAUDE.md >"$CLONE/home/.claude/CLAUDE.md"
    local old_content
    old_content=$(cat "$CLONE/home/.claude/CLAUDE.md")
    run_sut
    assert_rc "Link: Arbeitsbaum auf älterem Stand" 1
    assert_match "Link: als lokal anders (Arbeitsbaum) gemeldet" 'abweichend: +~/\.claude/CLAUDE\.md \[Link\] - lokal anders: .*\(Arbeitsbaum des Klons weicht von HEAD ab\)'
    assert_match "Link: restore als Hinweis" "git -C $CLONE restore <datei>"
    assert_lacks "Link: nicht als Repo neuer nachgezogen" "nachgezogen: ~/.claude/CLAUDE.md"
    assert_eq "Link: Klon-Datei nie beschrieben" "$old_content" "$(cat "$CLONE/home/.claude/CLAUDE.md")"
    assert_eq "Link: kein Vorschlag aus einem alten Stand" "" "$(branches)"
    # ~/.bashrc und settings.json als Symlink: nie hindurchschreiben
    new_sandbox
    install_state
    push_v2
    mv "$H/.bashrc" "$SB/echte-bashrc"
    ln -s "$SB/echte-bashrc" "$H/.bashrc"
    mv "$H/.claude/settings.json" "$SB/echte-settings.json"
    ln -s "$SB/echte-settings.json" "$H/.claude/settings.json"
    local b_bashrc b_settings
    b_bashrc=$(sha256sum <"$SB/echte-bashrc")
    b_settings=$(sha256sum <"$SB/echte-settings.json")
    run_sut
    assert_rc "Symlink-Ziele" 1
    assert_match "Symlink: Block gemeldet" 'abweichend: +~/\.bashrc \(Block shdft\) \[Block\] - Ziel ist ein Symlink \(-> .*echte-bashrc\), nichts geschrieben'
    assert_match "Symlink: Einstellungen gemeldet" 'abweichend: +~/\.claude/settings\.json \[Einstellungen\] - Ziel ist ein Symlink'
    assert_eq "Symlink: bashrc unverändert" "$b_bashrc" "$(sha256sum <"$SB/echte-bashrc")"
    assert_eq "Symlink: settings unverändert" "$b_settings" "$(sha256sum <"$SB/echte-settings.json")"
    assert_ok "Symlink: Links bleiben Links" test -L "$H/.bashrc" -a -L "$H/.claude/settings.json"
}

t_sicherung_fehlt() {
    echo "-- 2 Sicherung schlägt fehl: nichts überschreiben"
    new_sandbox
    install_state
    push_v2
    printf 'ich bin kein Verzeichnis\n' >"$H/.shdft-backup"
    local before
    before=$(snapshot "$H")
    run_sut
    assert_rc "Sicherung fehlgeschlagen" 1
    assert_match "Sicherung: Meldung je Datei" 'abweichend: +~/\.agents/AGENTS\.md \[Kopie\] - Sicherung fehlgeschlagen, nichts überschrieben'
    assert_match "Sicherung: Block" 'abweichend: +~/\.bashrc \(Block shdft\) \[Block\] - Sicherung fehlgeschlagen'
    assert_match "Sicherung: Ergebnis" '^Ergebnis: +Abweichungen gemeldet'
    assert_eq "Sicherung: HOME unverändert" "$before" "$(snapshot "$H")"
}

t_nonascii() {
    echo "-- 5 Nicht-ASCII-Pfade"
    new_sandbox
    install_state
    run_sut
    assert_rc "größe: gleich" 0
    assert_match "größe: gleich gezählt" '0 abweichend'
    printf 'lokal\n' >>"$CLONE/home/.claude/skills/größe.md"
    run_sut
    assert_rc "größe: lokal anders" 1
    assert_match "größe: Datei lesbar genannt" 'abweichend: +~/\.claude/skills/größe\.md \[Link\]'
    assert_match "größe: Klon-Änderung lesbar genannt" 'Klon hat lokale Änderungen .*home/\.claude/skills/größe\.md'
    local b
    b=$(branches)
    assert_eq "größe: Vorschlag enthält die Datei" "home/.claude/skills/größe.md" "$(git -C "$CLONE" -c core.quotePath=false show --name-only --format= "$b")"
    assert_match "größe: Commit-Meldung mit dem Namen" 'größe\.md' "$(git -C "$CLONE" log -1 --format=%s "$b")"
    # Repo ändert die Datei und der Klon zieht per Fast-Forward nach
    new_sandbox
    install_state
    printf 'neu\n' >>"$SEED/home/.claude/skills/größe.md"
    git -C "$SEED" add -A
    tg -C "$SEED" commit -q -m "größe neu"
    git -C "$SEED" push -q origin main
    rm "$H/.claude/skills/größe.md"
    cp "$CLONE/home/.claude/skills/größe.md" "$H/.claude/skills/größe.md"
    run_sut
    assert_rc "größe: Repo neuer" 0
    assert_match "größe: Kopie nachgezogen" 'nachgezogen: +~/\.claude/skills/größe\.md \(Repo neuer\)'
}

t_ssh_befehl() {
    echo "-- 7 GIT_SSH_COMMAND nur setzen, wenn nichts eigenes da ist"
    new_sandbox
    install_state
    printf '#!/bin/sh\necho "$*" >>"%s/ssh-aufrufe"\nexit 1\n' "$SB" >"$SB/meine-ssh"
    chmod +x "$SB/meine-ssh"
    git -C "$CLONE" config remote.origin.url "ssh://git@example.invalid/tester/shdft.git"
    git -C "$CLONE" config core.sshCommand "$SB/meine-ssh"
    run_sut
    assert_ok "core.sshCommand wird benutzt" test -s "$SB/ssh-aufrufe"
    assert_lacks "core.sshCommand ohne BatchMode-Zusatz" "BatchMode" "$(cat "$SB/ssh-aufrufe")"
    rm "$SB/ssh-aufrufe"
    git -C "$CLONE" config --unset core.sshCommand
    SUT_ENV=("GIT_SSH_COMMAND=$SB/meine-ssh")
    run_sut
    assert_ok "GIT_SSH_COMMAND der Umgebung wird benutzt" test -s "$SB/ssh-aufrufe"
    rm "$SB/ssh-aufrufe"
    SUT_ENV=()
    printf '#!/bin/sh\necho "$*" >>"%s/ssh-aufrufe"\nexit 1\n' "$SB" >"$SB/bin/ssh"
    chmod +x "$SB/bin/ssh"
    run_sut
    assert_match "ohne eigene Einstellung: BatchMode" 'BatchMode=yes' "$(cat "$SB/ssh-aufrufe")"
}

t_aufraeumen() {
    echo "-- 9 keine Anhäufung ohne Identität, kein Rechnername"
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    set_origin_owner jemand-anderes
    run_sut
    assert_match "ohne Identität: vorbereitet" 'Dateien vorbereitet, nicht committet'
    assert_match "ohne Identität: Zweigname ohne Rechner" 'Vorschlag: +shdftupdate/[0-9]{8}-[0-9]{6} in '
    assert_match "ohne Identität: Commit-Befehl" 'commit -m .*home/\.agents/AGENTS\.md'
    local host
    host=$(uname -n | cut -d. -f1)
    assert_lacks "kein Rechnername im Zweig" "$host" "$(branches)"
    run_sut
    run_sut
    assert_match "ohne Identität: zweiter Lauf erkennt den Arbeitsbaum" 'schon vorbereitet, nichts Neues angelegt'
    assert_eq "ohne Identität: weiterhin ein Zweig" 1 "$(branches | grep -c .)"
    assert_eq "ohne Identität: ein Arbeitsbaum" 1 "$(find "$SB/state/proposals" -mindepth 1 -maxdepth 1 | grep -c .)"
    assert_eq "ohne Identität: Worktree-Liste ohne Reste" 2 "$(git -C "$CLONE" worktree list | grep -c .)"
}

t_leeres_objekt() {
    echo "-- 10 leeres Objekt im Repo gegen lokalen Wert"
    new_sandbox
    install_state
    printf '{"theme":"dark","language":"Deutsch","extra":{}}\n' >"$SEED/home/.claude/settings.json"
    git -C "$SEED" add -A
    tg -C "$SEED" commit -q -m "extra"
    git -C "$SEED" push -q origin main
    jq '.extra = "text"' "$H/.claude/settings.json" >"$SB/s.json"
    cat "$SB/s.json" >"$H/.claude/settings.json"
    local before
    before=$(sha256sum <"$H/.claude/settings.json")
    run_sut
    assert_rc "extra lokal Text" 1
    assert_match "extra lokal Text: gemeldet" 'abweichend: +~/\.claude/settings\.json \[Einstellungen\] - lokal anders: Schlüssel extra'
    assert_eq "extra lokal Text: nie überschrieben" "$before" "$(sha256sum <"$H/.claude/settings.json")"
    jq '.extra = {"k": 1}' "$H/.claude/settings.json" >"$SB/s.json"
    cat "$SB/s.json" >"$H/.claude/settings.json"
    run_sut
    assert_rc "extra lokal Objekt" 0
    assert_match "extra lokal Objekt: gleich" '0 abweichend'
}

t_fehlt() {
    echo "-- 4 lokal fehlt"
    new_sandbox
    install_state
    rm "$H/.agents/AGENTS.md" "$H/.config/herdr/config.toml" "$H/.pi/agent/settings.json" "$H/.profile"
    ln -sfn "$SB/gibt-es-nicht" "$H/.claude/CLAUDE.md"
    run_sut
    assert_rc "fehlt" 0
    assert_match "fehlt: neu angelegt" 'neu angelegt: +~/\.agents/AGENTS\.md'
    assert_match "fehlt: Zähler" '5 neu angelegt'
    assert_eq "fehlt: Link auf den Klon" "$CLONE/home/.agents/AGENTS.md" "$(readlink "$H/.agents/AGENTS.md")"
    assert_eq "fehlt: kaputter Link ersetzt" "$CLONE/home/.claude/CLAUDE.md" "$(readlink "$H/.claude/CLAUDE.md")"
    assert_eq "fehlt: Einstellungen aus dem Repo" 1800000 "$(jq -r .httpIdleTimeoutMs "$H/.pi/agent/settings.json")"
    assert_ok "fehlt: Block in neuer .profile" grep -qx '# BEGIN shdft-profile' "$H/.profile"
    assert_ok "fehlt: kaputter Link gesichert" test -L "$(find "$H/.shdft-backup" -path '*/.claude/CLAUDE.md' | head -n 1)"

    echo "-- 4b Rechner ohne jede verwaltete Datei"
    new_sandbox
    run_sut
    assert_rc "leer" 0
    assert_match "leer: nicht eingerichtet" 'nicht eingerichtet, profiles/linux/install\.sh ausführen'
    assert_match "leer: Ergebnis" '^Ergebnis: +nicht eingerichtet'
    assert_eq "leer: nichts angelegt" "" "$(find "$H" -mindepth 1)"
}

t_divergenz() {
    echo "-- 5 Divergenz, voraus, umgeschrieben, Zweig, offline, Fast-Forward blockiert"
    local before after
    # divergiert
    new_sandbox
    install_state
    printf 'lokal\n' >"$CLONE/LOKAL.md"
    git -C "$CLONE" add LOKAL.md
    tg -C "$CLONE" commit -q -m lokal
    push_v2
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "divergiert" 1
    assert_match "divergiert: Meldung" 'divergiert: 1 lokal, 1 auf origin/main'
    assert_match "divergiert: kein Vorschlag nötig, kein Fehler" '^Ergebnis: +Abweichungen gemeldet'
    after=$(clone_state; snapshot "$H")
    assert_eq "divergiert: HEAD, Arbeitsbaum und HOME unverändert" "$before" "$after"
    # voraus
    new_sandbox
    install_state
    printf 'lokal\n' >"$CLONE/LOKAL.md"
    git -C "$CLONE" add LOKAL.md
    tg -C "$CLONE" commit -q -m lokal
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "voraus" 1
    assert_match "voraus: Meldung" '1 Commit nicht gepusht'
    assert_eq "voraus: unverändert" "$before" "$(clone_state; snapshot "$H")"
    # origin/main umgeschrieben
    new_sandbox
    install_state
    run_sut
    assert_rc "umgeschrieben: erster Lauf" 0
    local other="$SB/other"
    git init -q -b main "$other"
    write_fixture "$other" 2
    git -C "$other" add -A
    tg -C "$other" commit -q -m "Andere Geschichte"
    git -C "$other" push -q "$ORIGIN" main:refs/heads/neu
    git -C "$ORIGIN" update-ref refs/heads/main refs/heads/neu
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "umgeschrieben" 1
    assert_match "umgeschrieben: Meldung" 'wurde umgeschrieben .*nichts erzwungen'
    assert_eq "umgeschrieben: unverändert" "$before" "$(clone_state; snapshot "$H")"
    # anderer Zweig
    new_sandbox
    install_state
    git -C "$CLONE" checkout -q -b feature
    push_v2
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "Zweig" 1
    assert_match "Zweig: Meldung" 'Zweig feature statt main, kein Fast-Forward'
    assert_eq "Zweig: unverändert" "$before" "$(clone_state; snapshot "$H")"
    # offline
    new_sandbox
    install_state
    git -C "$CLONE" remote set-url origin "$SB/gibt-es-nicht.git"
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "offline" 1
    assert_match "offline: Meldung" 'Offline oder origin nicht erreichbar'
    assert_eq "offline: unverändert" "$before" "$(clone_state; snapshot "$H")"
    # Fast-Forward durch lokale Änderung blockiert
    new_sandbox
    install_state
    printf 'lokal im Klon\n' >>"$CLONE/home/.claude/CLAUDE.md"
    push_v2
    before=$(clone_state; snapshot "$H")
    run_sut
    assert_rc "ff blockiert" 1
    assert_match "ff blockiert: Meldung mit Datei" 'Fast-Forward nicht möglich: lokale Änderungen in home/\.claude/CLAUDE\.md'
    assert_match "ff blockiert: restore als Hinweis für den Nutzer" "git -C $CLONE restore <datei>"
    assert_eq "ff blockiert: unverändert" "$before" "$(clone_state; snapshot "$H")"
}

sec_case() { # Art Zeile Geheimnis
    local kind=$1 line=$2 secret=$3
    cp "$CLONE/home/.agents/AGENTS.md" "$H/.agents/AGENTS.md"
    printf '%s\n' "$line" >>"$H/.agents/AGENTS.md"
    run_sut
    assert_rc "Sicherheit $kind: Exit" 1
    assert_match "Sicherheit $kind: Fund gemeldet" "Sicherheit: +~/\.agents/AGENTS\.md Zeile 3: $kind \("
    assert_lacks "Sicherheit $kind: Klartext fehlt in der Ausgabe" "$secret"
    assert_match "Sicherheit $kind: nicht vorgeschlagen" 'nicht vorgeschlagen: alle abweichenden Dateien haben einen Sicherheitsfund'
    assert_eq "Sicherheit $kind: kein Zweig" "" "$(branches)"
    run_sut -v
    assert_lacks "Sicherheit $kind: Klartext fehlt auch mit -v" "$secret"
    assert_match "Sicherheit $kind: -v sperrt die Zeile" 'Zeile gesperrt'
}

t_sicherheit() {
    echo "-- 6 Sicherheitsfund"
    new_sandbox
    install_state
    local ghp pat sk xox akia aiza jwt
    ghp=$(printf 'ghp_%s' "$(rep a 36)")
    pat=$(printf 'github_pat_%s' "$(rep b 30)")
    sk=$(printf 'sk-%s' "$(rep c 30)")
    xox=$(printf 'xoxb-%s' "$(rep 1 14)")
    akia=$(printf 'AKIA%s' "$(rep A 16)")
    aiza=$(printf 'AIza%s' "$(rep d 35)")
    jwt=$(printf 'eyJ%s.eyJ%s' "$(rep e 12)" "$(rep f 12)")
    sec_case Token "notiert: $ghp" "$ghp"
    sec_case Token "notiert: $pat" "$pat"
    sec_case Token "notiert: $sk" "$sk"
    sec_case Token "notiert: $xox" "$xox"
    sec_case Token "notiert: $akia" "$akia"
    sec_case Token "notiert: $aiza" "$aiza"
    sec_case Token "notiert: $jwt" "$jwt"
    sec_case Token "Authorization: Bearer $(rep Z 30)" "$(rep Z 30)"
    sec_case Schlüssel "-----BEGIN $(printf 'OPENSSH PRIV')ATE KEY-----" "OPENSSH"
    sec_case Schlüssel "ssh-ed25519 AAAA$(rep Q 30) me" "$(rep Q 30)"
    sec_case Schlüssel "ssh-rsa AAAA$(rep W 30) me" "$(rep W 30)"
    sec_case Kennwort "pass""word=hunter2hunter2" "hunter2hunter2"
    sec_case Kennwort "\"api_key\": \"geheimgeheim99\"" "geheimgeheim99"
    sec_case Kennwort "SECRET: abcdef123456" "abcdef123456"
    sec_case "private IP" "Server im LAN: 192.168.10.20" "192.168.10.20"
    sec_case "private IP" "Server: 10.1.2.3" "10.1.2.3"
    sec_case "private IP" "Server: 172.20.5.6" "172.20.5.6"
    sec_case "private IP" "Server: 100.100.7.8" "100.100.7.8"
    sec_case Mailadresse "Kontakt: maxmustermann@firma-beispiel.de" "maxmustermann"
    assert_match "Sicherheit Mailadresse: nur die Domain im Auszug" '\(\*\*\*@firma-beispiel\.de\)'
    sec_case Token "notiert: $(printf 'npm_%s' "$(rep a 36)")" "$(rep a 36)"
    sec_case Token "notiert: $(printf 'glpat-%s' "$(rep b 24)")" "$(rep b 24)"
    sec_case Token "notiert: $(printf 'hf_%s' "$(rep c 36)")" "$(rep c 36)"
    sec_case Token "notiert: $(printf 'sk_%s_%s' live "$(rep d 26)")" "$(rep d 26)"
    sec_case Token "notiert: $(printf 'sk_%s_%s' test "$(rep e 26)")" "$(rep e 26)"
    sec_case Token "notiert: $(printf 'pk_%s_%s' live "$(rep f 26)")" "$(rep f 26)"
    sec_case Token "notiert: $(printf 'ghs_%s' "$(rep g 36)")" "$(rep g 36)"
    sec_case Token "notiert: $(printf 'dop_v1_%s' "$(rep 4 44)")" "$(rep 4 44)"
    sec_case Token "Authorization: Basic $(rep Q 20)" "$(rep Q 20)"
    sec_case Token "Authorization: Bearer $(rep R 12)" "$(rep R 12)"
    sec_case Kennwort "curl -s -u admin:geheimwort123 https://beispiel.example/api" "geheimwort123"
    sec_case Kennwort "export DB_PASS=abc12345xyz" "abc12345xyz"
    sec_case Kennwort "AWS_SECRET_ACCESS_KEY=$(rep w 20)" "$(rep w 20)"
    sec_case Kennwort "pwd: abc12345xyz" "abc12345xyz"
    sec_case Kennwort "passphrase=correct-horse-battery" "correct-horse-battery"
    sec_case Kennwort "token=<offen" "offen"
    sec_case Kennwort "secret=@WERTOHNEENDE" "WERTOHNEENDE"
    sec_case Kennwort 'password=$' 'password=$'
    sec_case Benutzerpfad "Skript in /mnt/d/Users/maxmustermann/bin" "maxmustermann"
    sec_case Benutzerpfad 'Freigabe \\server01\freigabe' "server01"
    sec_case "private IP" "Adresse fd12:3456:789a::1" "fd12:3456"
    sec_case Benutzerpfad "Skript in /home/maxmustermann/bin" "maxmustermann"
    sec_case Benutzerpfad "Skript in /Users/maxmustermann/bin" "maxmustermann"
    sec_case Benutzerpfad "Skript in /mnt/c/Users/maxmustermann/bin" "maxmustermann"
    sec_case Benutzerpfad "Skript in C:\\Users\\maxmustermann\\bin" "maxmustermann"
    sec_case Verbindungszeichenfolge "ziel: postgres://db.beispiel/daten" "db.beispiel"
    sec_case Verbindungszeichenfolge "ziel: https://nutzer:geheimwort@host.beispiel/x" "geheimwort"
    sec_case Verbindungszeichenfolge "ziel: jdbc:db2://host.beispiel/x" "host.beispiel"
    sec_case Verbindungszeichenfolge "ziel: Server=x;Pass""word=abc123;" "abc123"

    echo "-- 6b Platzhalter sind erlaubt, eine saubere Datei läuft trotz Fund in einer anderen weiter"
    cp "$CLONE/home/.agents/AGENTS.md" "$H/.agents/AGENTS.md"
    {
        printf 'apiKey: "strata-local"\n'
        printf 'token=$TOKEN\n'
        printf 'password: <geheim>\n'
        printf 'secret=@WERT@\n'
        printf 'Loopback 127.0.0.1\n'
        printf 'x@users.noreply.github.com und noreply@example.com\n'
        printf 'Pfad /home/<name>/x und $HOME/x\n'
        printf 'Version 2.10.1.5 und tasks-und-risks-of-this-assessment-process\n'
        printf 'git clone git@github.com:beispiel/repo.git und git@host:pfad\n'
        printf 'Authorization: Bearer $TOKEN und token=${TOKEN_DATEI}\n'
        printf 'curl -u $USER:$PASS https://beispiel.example\n'
        printf 'Windows-Pfad C:\\Users\\<name>\\x und \\n\\t\n'
    } >>"$H/.agents/AGENTS.md"
    run_sut
    assert_lacks "Platzhalter: kein Sicherheitsfund" "Sicherheit:"
    assert_eq "Platzhalter: Vorschlag entsteht" 1 "$(branches | grep -c .)"

    echo "-- 6c Sicherheitsprüfung in der Klasse Einstellungen"
    new_sandbox
    install_state
    jq --arg t "$ghp" '.theme = $t' "$H/.claude/settings.json" >"$SB/s.json"
    cat "$SB/s.json" >"$H/.claude/settings.json"
    run_sut -v
    assert_rc "Einstellungen mit Token" 1
    assert_match "Einstellungen: Fund genannt" 'Sicherheit: +~/\.claude/settings\.json Zeile [0-9]+: Token'
    assert_lacks "Einstellungen: Klartext fehlt" "$ghp"
    assert_lacks "Einstellungen: Klartext fehlt auch ohne ghp-Präfix" "$(rep a 36)"
    assert_eq "Einstellungen: kein Zweig" "" "$(branches)"

    new_sandbox
    install_state
    printf 'sauber\n' >>"$H/.agents/AGENTS.md"
    sed -i "s/alias ll='ls -l'/alias ll='ls -l' # 192.168.1.1/" "$H/.bashrc"
    run_sut
    assert_rc "gemischt" 1
    assert_match "gemischt: Fund genannt" 'Sicherheit: +~/\.bashrc \(Block shdft\) Zeile 1: private IP'
    assert_match "gemischt: Vorschlag trotzdem" 'Vorschlag: +shdftupdate/'
    local b
    b=$(branches)
    assert_eq "gemischt: nur die saubere Datei im Vorschlag" "home/.agents/AGENTS.md" "$(git -C "$CLONE" show --name-only --format= "$b")"
}

t_hosts() {
    echo "-- 7 Hosts-Liste mit ssh-Attrappe"
    # zweiter Rechner mit Repo und lokaler Abweichung
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    R2H=$H R2C=$CLONE R2S=$SB
    new_sandbox
    install_state
    mkdir -p "$SB/config" "$SB/remote-home"
    cat >"$SB/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_SSH_LOG"
alias=${*: -2:1}
cmd=${*: -1}
case "$alias" in
down)
    echo "ssh: connect to host down port 22: Connection refused" >&2
    exit 255
    ;;
down2) exit 255 ;;
remote2) exec env HOME="$FAKE_R2_HOME" SHDFT_REPO="$FAKE_R2_REPO" SHDFT_STATE_DIR="$FAKE_R2_STATE" bash -c "$cmd" ;;
*) exec env -u SHDFT_REPO HOME="$FAKE_REMOTE_HOME" bash -c "$cmd" ;;
esac
EOF
    chmod +x "$SB/bin/ssh"
    export FAKE_SSH_LOG="$SB/ssh.log" FAKE_REMOTE_HOME="$SB/remote-home"
    export FAKE_R2_HOME="$R2H" FAKE_R2_REPO="$R2C" FAKE_R2_STATE="$R2S/state"
    printf '# Rechner\nremote1   # ohne Repo\n\n' >"$SB/config/hosts"
    run_sut
    assert_rc "Hosts: Gegenstelle ohne Repo" 0
    assert_eq "Hosts: lokaler Lauf und Gegenstelle haben je einen Kopf" 2 "$(printf '%s\n' "$OUT" | grep -c '^== ')"
    assert_match "Hosts: Gegenstelle ohne Repo gemeldet" 'Repo: +kein shdft-Repo auf diesem Rechner'
    assert_match "Hosts: lokal zuerst" '^== .+ \(linux\) ==$'
    assert_match "Hosts: Aufruf mit --local" 'BatchMode=yes -o ConnectTimeout=10 remote1 bash -s -- --local' "$(cat "$SB/ssh.log")"

    printf 'remote1\ndown\n' >"$SB/config/hosts"
    : >"$SB/ssh.log"
    run_sut
    assert_rc "Hosts: nicht erreichbar" 1
    assert_match "Hosts: nicht erreichbar gemeldet" 'Ergebnis: +nicht erreichbar \(ssh: connect to host down'
    assert_eq "Hosts: je Alias ein Lauf" 2 "$(grep -c . "$SB/ssh.log")"

    printf 'remote2\n' >"$SB/config/hosts"
    run_sut
    assert_rc "Hosts: Gegenstelle mit Abweichung" 1
    assert_match "Hosts: Abweichung der Gegenstelle" 'abweichend: +~/\.agents/AGENTS\.md \[Kopie\]'

    printf 'down2\n-oProxyCommand=touch\\ %s/gehackt\n' "$SB" >"$SB/config/hosts"
    : >"$SB/ssh.log"
    run_sut
    assert_rc "Hosts: unerreichbar ohne Ausgabe, ungültiger Alias" 1
    assert_match "Hosts: nicht erreichbar ohne leere Klammer" '^Ergebnis: +nicht erreichbar$'
    assert_match "Hosts: ungültiger Alias übersprungen" 'Ergebnis: +übersprungen, kein gültiger ssh-Alias'
    assert_eq "Hosts: ungültiger Alias nie an ssh gereicht" 1 "$(grep -c . "$SB/ssh.log")"
    assert_no "Hosts: nichts ausgeführt" test -e "$SB/gehackt"

    : >"$SB/ssh.log"
    run_sut --local
    assert_rc "Hosts: --local" 0
    assert_eq "Hosts: --local fragt keinen Rechner" 0 "$(grep -c . "$SB/ssh.log")"

    : >"$SB/ssh.log"
    run_sut --dry-run --no-propose -v
    assert_match "Hosts: Optionen werden weitergereicht" 'bash -s -- --local --dry-run --no-propose -v' "$(cat "$SB/ssh.log")"
    unset FAKE_SSH_LOG FAKE_REMOTE_HOME FAKE_R2_HOME FAKE_R2_REPO FAKE_R2_STATE
}

t_identitaet() {
    echo "-- 8 / 6 Identität"
    local b wt
    # Firmenadresse in der Repo-Konfiguration wird nicht genommen; der Commit des Repo-Besitzers auf origin/main schon
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    git -C "$CLONE" config --local user.name "Firma Person"
    git -C "$CLONE" config --local user.email "person@$CORP_EMAIL"
    run_sut
    assert_rc "Identität Firma" 1
    b=$(branches)
    assert_eq "Identität Firma: Autor kommt vom Repo-Besitzer" "$NOREPLY" "$(git -C "$CLONE" log -1 --format='%an <%ae>' "$b")"
    assert_lacks "Identität Firma: keine Firmenadresse" "$CORP_EMAIL" "$(git -C "$CLONE" log -1 --format='%an %ae %cn %ce' "$b")"

    # kein Login des Besitzers: kein Commit
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    set_origin_owner jemand-anderes
    run_sut
    assert_rc "Identität fremder Besitzer" 1
    b=$(branches)
    assert_match "Identität fremder Besitzer: nicht committet" 'nicht committet: keine Noreply-Identität'
    assert_match "Identität fremder Besitzer: Befehl zum Committen" 'commit -m '
    assert_eq "Identität fremder Besitzer: Zweig steht auf origin/main" "$(git -C "$CLONE" rev-parse origin/main)" "$(git -C "$CLONE" rev-parse "$b")"
    wt=$(git -C "$CLONE" worktree list --porcelain | awk -v b="refs/heads/$b" '$1=="worktree"{p=substr($0,10)} $1=="branch"&&$2==b{print p}')
    assert_eq "Identität fremder Besitzer: Datei vorbereitet und vorgemerkt" "home/.agents/AGENTS.md" "$(git -C "$wt" diff --cached --name-only)"

    # origin ohne GitHub-Besitzer (lokaler Pfad): kein Commit
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    git -C "$CLONE" config remote.origin.url "$ORIGIN"
    run_sut
    assert_match "Identität ohne Besitzer: nicht committet" 'nicht committet: keine Noreply-Identität'

    # fremder Autor ganz oben: nie der jüngste Commit, sondern der des Besitzers
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    printf 'x\n' >"$SEED/x.txt"
    git -C "$SEED" add x.txt
    git -C "$SEED" -c user.name=Fremder -c user.email="7+fremder@users.noreply.github.com" commit -q -m "Fremder Commit"
    printf 'y\n' >"$SEED/y.txt"
    git -C "$SEED" add y.txt
    git -C "$SEED" -c user.name=Firma -c user.email="$CORP_EMAIL" commit -q -m "Firmen-Commit"
    git -C "$SEED" push -q origin main
    run_sut
    b=$(branches)
    assert_eq "Identität fremder Autor: Besitzer, nicht Fremder oder Firma" "$NOREPLY" "$(git -C "$CLONE" log -1 --format='%an <%ae>' "$b")"

    # nur ein fremder Autor mit Noreply-Adresse, der Besitzer fehlt in der Historie
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    set_origin_owner fremder
    printf 'x\n' >"$SEED/x.txt"
    git -C "$SEED" add x.txt
    git -C "$SEED" -c user.name=Fremder -c user.email="fremder@users.noreply.github.com" commit -q -m "Fremder Commit"
    git -C "$SEED" push -q origin main
    run_sut
    b=$(branches)
    assert_eq "Identität Besitzer ohne eigene Commits" "Fremder <fremder@users.noreply.github.com>" "$(git -C "$CLONE" log -1 --format='%an <%ae>' "$b")"
    # ... ohne Treffer in der Historie gar kein Commit
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    set_origin_owner nirgends
    printf 'x\n' >"$SEED/x.txt"
    git -C "$SEED" add x.txt
    git -C "$SEED" -c user.name=Fremder -c user.email="7+fremder@users.noreply.github.com" commit -q -m "Fremder Commit"
    git -C "$SEED" push -q origin main
    run_sut
    assert_match "Identität nur fremde Autoren: nicht committet" 'nicht committet: keine Noreply-Identität'

    # Noreply in der Repo-Konfiguration
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    git -C "$CLONE" config --local user.name "Repo Person"
    git -C "$CLONE" config --local user.email "9+person@users.noreply.github.com"
    run_sut
    b=$(branches)
    assert_eq "Identität Repo-Konfiguration: Autor" "Repo Person <9+person@users.noreply.github.com>" "$(git -C "$CLONE" log -1 --format='%an <%ae>' "$b")"
    assert_eq "Identität Repo-Konfiguration: Committer" "Repo Person <9+person@users.noreply.github.com>" "$(git -C "$CLONE" log -1 --format='%cn <%ce>' "$b")"
    assert_lacks "Identität Repo-Konfiguration: kein Co-Autor" "Co-authored-by" "$(git -C "$CLONE" log -1 --format=%B "$b")"

    # SHDFT_AUTHOR (nur mit Noreply), vor dem Commit des Besitzers
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    SUT_ENV=("SHDFT_AUTHOR=Env Person <5+envperson@users.noreply.github.com>")
    run_sut
    b=$(branches)
    assert_eq "Identität SHDFT_AUTHOR" "Env Person <5+envperson@users.noreply.github.com>" "$(git -C "$CLONE" log -1 --format='%an <%ae>' "$b")"
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    set_origin_owner jemand-anderes
    SUT_ENV=("SHDFT_AUTHOR=Firma <$CORP_EMAIL>")
    run_sut
    assert_match "Identität SHDFT_AUTHOR mit Firmenadresse: nicht committet" 'nicht committet: keine Noreply-Identität'
}

t_kein_push() {
    echo "-- 9 kein Push"
    new_sandbox
    install_state
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    mkdir -p "$ORIGIN/hooks"
    printf '#!/bin/sh\ntouch "%s/push-versucht"\ncat >/dev/null\n' "$SB" >"$ORIGIN/hooks/pre-receive"
    chmod +x "$ORIGIN/hooks/pre-receive"
    local before
    before=$(git -C "$ORIGIN" for-each-ref)
    run_sut
    run_sut
    assert_match "kein Push: Vorschlag vorhanden" 'Vorschlag: +shdftupdate/'
    assert_eq "kein Push: Origin unverändert" "$before" "$(git -C "$ORIGIN" for-each-ref)"
    assert_eq "kein Push: kein Remote-Zweig shdftupdate/*" "" "$(git -C "$ORIGIN" for-each-ref 'refs/heads/shdftupdate/')"
    assert_eq "kein Push: auch lokal kein Remote-Tracking-Zweig" "" "$(git -C "$CLONE" for-each-ref 'refs/remotes/origin/shdftupdate/')"
    assert_no "kein Push: Origin wurde nie angesprochen" test -e "$SB/push-versucht"
    assert_no "kein Push: gh nie aufgerufen" test -e "$SB/gh.log"
    # Statisch: nirgends stash, reset, checkout, force oder ein ausgeführter Push.
    local code
    code=$(grep -v '^[[:space:]]*#' "$SCRIPT")
    assert_no "kein Push: kein stash/reset/checkout im Skript" grep -Eq '(stash|reset|checkout)' <<<"$code"
    assert_no "kein Push: kein force im Skript" grep -Eq -- '(--force|push[^"]* -f)' <<<"$code"
    assert_no "kein Push: git push nur als Text" grep -En '^[[:space:]]*(g|git)[^"]* push' <<<"$code"
    assert_no "kein Push: gh nur als Text" grep -En '^[[:space:]]*gh ' <<<"$code"
}

array_of() { # Datei Name: Elemente einer mehrzeiligen Array-Definition
    (
        eval "$(sed -n "/^$2=(/,/^)/p" "$1")"
        local -n arr="$2"
        printf '%s\n' "${arr[@]}"
    )
}

t_drift() {
    echo "-- 10 Drift: Installer und Skript"
    local merges_script merges_linux merges_wsl p links expected block_lines script_blocks src
    merges_script=$(array_of "$SCRIPT" MERGES | sort)
    merges_linux=$(array_of "$ROOT/profiles/linux/install.sh" MERGES | sort)
    merges_wsl=$(array_of "$ROOT/profiles/windows-wsl/install.sh" MERGES | sort)
    assert_eq "Drift: MERGES Linux" "$merges_script" "$merges_linux"
    assert_eq "Drift: MERGES WSL" "$merges_script" "$merges_wsl"
    local homefiles
    homefiles=$(git -C "$ROOT" ls-files --cached --others --exclude-standard home/ | sed 's#^home/##' | grep -vxF -f <(printf '%s\n' "$merges_script") | sort)
    for p in linux windows-wsl; do
        links=$(array_of "$ROOT/profiles/$p/install.sh" LINKS | sort)
        expected=$homefiles
        if [ "$p" = windows-wsl ]; then
            expected=$(printf '%s\n%s\n' "$homefiles" ".local/bin/win-browser" | sort)
            src=$(array_of "$SCRIPT" LINKS_windows_wsl | head -n 1)
            assert_eq "Drift: Profildatei WSL im Skript" "profiles/windows-wsl/home/.local/bin/win-browser|.local/bin/win-browser" "$src"
            assert_ok "Drift: Quelle der Profildatei WSL existiert" git -C "$ROOT" cat-file -e "HEAD:profiles/windows-wsl/home/.local/bin/win-browser"
            assert_ok "Drift: Vorlage WSL im Installer" grep -qF 'BROWSER_DESKTOP=win-browser.desktop' "$ROOT/profiles/windows-wsl/install.sh"
            assert_ok "Drift: Vorlagenpfad WSL im Installer" grep -qF 'home/.local/share/applications/$BROWSER_DESKTOP.in' "$ROOT/profiles/windows-wsl/install.sh"
            assert_eq "Drift: Vorlage WSL im Skript" "profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in|.local/share/applications/win-browser.desktop" \
                "$(array_of "$SCRIPT" TEMPLATES_windows_wsl | head -n 1)"
        else
            assert_ok "Drift: WezTerm-Link Linux im Installer" grep -qF 'link "$PROFILE/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"' "$ROOT/profiles/linux/install.sh"
            assert_eq "Drift: WezTerm-Link Linux im Skript" "profiles/linux/wezterm.lua|.config/wezterm/wezterm.lua" "$(array_of "$SCRIPT" LINKS_linux | head -n 1)"
        fi
        assert_eq "Drift: LINKS $p gleich git ls-files home/ (ohne MERGES) und Profildateien" "$expected" "$links"
        # Blöcke: Zeilen "block <Datei> <Name> <Quelle>" der Installer gegen BLOCKS im Skript
        block_lines=$(sed -n 's/^[[:space:]]*block "\$HOME\/\([^"]*\)" \([^ ]*\) "\(.*\)"$/\1|\2|\3/p' "$ROOT/profiles/$p/install.sh" |
            sed -e 's#\$SHELL_SRC/#shell/#' -e "s#\\\$PROFILE/#profiles/$p/#" | sort)
        script_blocks=$(array_of "$SCRIPT" BLOCKS | sed "s#@PROFILE@#$p#" | sort)
        assert_eq "Drift: Shell-Blöcke $p" "$script_blocks" "$block_lines"
    done
    assert_ok "Drift: Skill in LINKS Linux" grep -qx '    .claude/skills/shdftupdate/SKILL.md' "$ROOT/profiles/linux/install.sh"
    assert_ok "Drift: Skill im Repo" test -f "$ROOT/home/.claude/skills/shdftupdate/SKILL.md"
}

t_trockenlauf() {
    echo "-- Trockenlauf, Aufruffehler, WSL-Vorlage"
    new_sandbox
    install_state
    push_v2
    printf 'lokal\n' >>"$H/.agents/AGENTS.md"
    rm "$H/.config/herdr/config.toml"
    local before
    before=$(clone_state; snapshot "$H")
    run_sut --dry-run
    assert_rc "Trockenlauf" 1
    assert_match "Trockenlauf: würde aktualisieren" 'würde aktualisieren'
    assert_match "Trockenlauf: würde anlegen" 'würde anlegen: +~/\.config/herdr/config\.toml'
    assert_match "Trockenlauf: kein Vorschlag" 'nicht vorgeschlagen: Trockenlauf'
    assert_eq "Trockenlauf: HOME und Klon unverändert" "$before" "$(clone_state; snapshot "$H")"
    assert_eq "Trockenlauf: kein Zweig" "" "$(branches)"
    run_sut --no-propose
    assert_match "--no-propose" 'nicht vorgeschlagen: --no-propose'
    assert_eq "--no-propose: kein Zweig" "" "$(branches)"

    OUT=$(env HOME="$H" SHDFT_REPO="$CLONE" bash "$SCRIPT" --gibt-es-nicht 2>&1) && RC=0 || RC=$?
    assert_rc "unbekannte Option" 2
    OUT=$(env HOME="$H" SHDFT_REPO="$SB" bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
    assert_rc "SHDFT_REPO ohne Klon" 2
    OUT=$(env HOME="$H" SHDFT_REPO="$CLONE" SHDFT_PROFILE=mac bash "$SCRIPT" 2>&1) && RC=0 || RC=$?
    assert_rc "unbekanntes Profil" 2
    OUT=$(env HOME="$H" bash "$SCRIPT" --help 2>&1) && RC=0 || RC=$?
    assert_rc "--help" 0
    assert_match "--help: Aufruf" '^Aufruf: shdftupdate\.sh'

    echo "-- Klon finden ohne SHDFT_REPO"
    new_sandbox
    install_state
    mkdir -p "$SB/draussen" "$SB/clone/profiles/shared"
    cp "$SCRIPT" "$SB/draussen/shdftupdate.sh"
    cp "$SCRIPT" "$SB/clone/profiles/shared/shdftupdate.sh"
    OUT=$(env HOME="$SB/leer" bash "$SB/clone/profiles/shared/shdftupdate.sh" --dry-run 2>&1) && RC=0 || RC=$?
    assert_match "Klon finden: Ort des Skripts" "^Repo: +$CLONE, main"
    OUT=$(env HOME="$H" bash "$SB/draussen/shdftupdate.sh" --dry-run 2>&1) && RC=0 || RC=$?
    assert_match "Klon finden: Symlink ~/.claude/CLAUDE.md" "^Repo: +$CLONE, main"
    rm "$H/.claude/CLAUDE.md"
    mv "$CLONE" "$H/shdft"
    OUT=$(env HOME="$H" bash "$SB/draussen/shdftupdate.sh" --dry-run 2>&1) && RC=0 || RC=$?
    assert_match "Klon finden: ~/shdft" "^Repo: +$H/shdft, main"
    mkdir -p "$SB/leer"
    OUT=$(env HOME="$SB/leer" bash "$SB/draussen/shdftupdate.sh" 2>&1) && RC=0 || RC=$?
    assert_rc "Klon finden: ohne Klon" 0
    assert_match "Klon finden: ohne Klon gemeldet" 'Repo: +kein shdft-Repo auf diesem Rechner'

    new_sandbox
    PROFILE_T=windows-wsl
    install_state windows-wsl
    run_sut
    assert_rc "WSL gleich" 0
    assert_match "WSL: Windows-Seite genannt" 'Windows-Seite .* wird hier nicht geprüft'
    printf 'X-Lokal=1\n' >>"$H/.local/share/applications/win-browser.desktop"
    run_sut
    assert_rc "WSL Vorlage lokal anders" 1
    assert_match "WSL Vorlage: gemeldet" 'abweichend: +~/\.local/share/applications/win-browser\.desktop \[Vorlage\] - lokal anders'
    local b
    b=$(branches)
    assert_match "WSL Vorlage: Vorschlag trägt @HOME@ statt des Pfades" '^Exec=@HOME@/\.local/bin/win-browser' \
        "$(git -C "$CLONE" show "$b:profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in")"
    assert_lacks "WSL Vorlage: kein HOME-Pfad im Vorschlag" "$H" "$(git -C "$CLONE" show "$b:profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in")"
    assert_match "WSL Vorlage: lokale Zeile im Vorschlag" '^X-Lokal=1' "$(git -C "$CLONE" show "$b:profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in")"
}

t_gleich
t_repo_neuer
t_lokal_anders
t_beide_geaendert
t_nachziehbedingung
t_symlink
t_sicherung_fehlt
t_nonascii
t_ssh_befehl
t_aufraeumen
t_leeres_objekt
t_fehlt
t_divergenz
t_sicherheit
t_hosts
t_identitaet
t_kein_push
t_drift
t_trockenlauf

echo
echo "$((PASS + FAIL)) Prüfungen: $PASS grün, $FAIL fehlgeschlagen"
[ "$FAIL" = 0 ]
