#!/usr/bin/env bash
set -euo pipefail

SHDFT_BEGIN="# BEGIN shdft"
SHDFT_END="# END shdft"
REPO_URL="https://github.com/thelad-dev/shdft"

usage() {
    cat <<EOF
Verwendung: $(basename "$0") [OPTION]

Shell-Standards für Bash, Zsh und Git Bash einrichten.

Optionen:
  (ohne)        Einstellungen anwenden (idempotent)
  --status      Aktuellen Stand anzeigen
  --check       Wie --status
  --uninstall   Alle von shdft verwalteten Blöcke entfernen
  -h, --help    Diese Hilfe

Nach der Installation: source ~/.bashrc  bzw.  source ~/.zshrc

Komplettstack (WezTerm/Herdr/Claude/Pi): profiles/linux/ oder profiles/windows-wsl/
EOF
}

confirm() {
    local prompt="$1"
    local answer=""

    if [[ -t 0 ]]; then
        read -r -p "$prompt [j/N] " answer
    elif [[ -r /dev/tty ]]; then
        printf '%s [j/N] ' "$prompt" >/dev/tty
        read -r answer </dev/tty
    else
        echo "Kein Terminal für Eingabe verfügbar — übersprungen: $prompt" >&2
        return 1
    fi

    case "$answer" in
        j|J|ja|Ja|y|Y|yes|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

managed_shell_files() {
    local files=("$HOME/.bashrc")

    if [[ -f "$HOME/.zshrc" ]] || command -v zsh >/dev/null 2>&1; then
        files+=("$HOME/.zshrc")
    fi

    if [[ -n "${MSYSTEM:-}" ]]; then
        files+=("$HOME/.bash_profile")
    fi

    printf '%s\n' "${files[@]}" | awk '!seen[$0]++'
}

has_block() {
    local file="$1"
    [[ -f "$file" ]] && grep -qF "$SHDFT_BEGIN" "$file"
}

remove_block() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local tmp
    tmp="$(mktemp)"
    awk -v begin="$SHDFT_BEGIN" -v end="$SHDFT_END" '
        $0 == begin { skip = 1; next }
        $0 == end   { skip = 0; next }
        !skip       { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

remove_legacy_entries() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    local tmp
    tmp="$(mktemp)"
    awk '
        /FULL_PATH_PROMPT_ENABLED/ { skip = 1; next }
        skip && /^$/ { skip = 0; next }
        skip { next }
        /^[[:space:]]*alias[[:space:]]+cls=/ { next }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

remove_legacy_inputrc() {
    local file="$HOME/.inputrc"
    [[ -f "$file" ]] || return 0
    if has_block "$file"; then
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    grep -vxF "set completion-ignore-case on" "$file" > "$tmp" || true
    mv "$tmp" "$file"
}

write_block() {
    local file="$1"
    local shell_type="$2"

    touch "$file"
    remove_legacy_entries "$file"
    remove_block "$file"

    {
        echo ""
        echo "$SHDFT_BEGIN"
        echo "# Shell-Standards ($REPO_URL)"
        echo "alias cls='clear'"
        echo "alias ll='ls -lah'"
        echo "alias la='ls -A'"
        echo "alias l='ls -CF'"

        if [[ "$shell_type" == "bash" ]]; then
            echo "export PROMPT_DIRTRIM=0"
            echo "PS1='[\\u@\\h \${PWD/#\$HOME/\\~}]\$ '"
        else
            echo "setopt PROMPT_SUBST"
            echo 'PROMPT="[%n@%m ${PWD/#$HOME/\~}]%# "'
        fi

        echo "$SHDFT_END"
    } >> "$file"
}

write_inputrc_block() {
    local file="$HOME/.inputrc"
    touch "$file"
    remove_legacy_inputrc
    remove_block "$file"

    {
        echo ""
        echo "$SHDFT_BEGIN"
        echo "# Shell-Standards ($REPO_URL)"
        echo "set completion-ignore-case on"
        echo "$SHDFT_END"
    } >> "$file"
}

ensure_git_bash_sources_bashrc() {
    local profile="$HOME/.bash_profile"
    [[ -n "${MSYSTEM:-}" ]] || return 0
    [[ -f "$profile" ]] || touch "$profile"

    if grep -qE '(\.|source)[[:space:]]+~?/?\.bashrc' "$profile"; then
        return 0
    fi

    if has_block "$profile"; then
        return 0
    fi

    {
        echo ""
        echo "$SHDFT_BEGIN"
        echo "# Git Bash: ~/.bashrc laden"
        echo 'if [[ -f "$HOME/.bashrc" ]]; then'
        echo '    . "$HOME/.bashrc"'
        echo 'fi'
        echo "$SHDFT_END"
    } >> "$profile"
}

ohmyzsh_installed() {
    [[ -d "$HOME/.oh-my-zsh" ]]
}

zsh_available() {
    command -v zsh >/dev/null 2>&1
}

install_zsh_package() {
    echo "zsh wird installiert …"

    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm zsh
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y zsh
    elif command -v apt >/dev/null 2>&1; then
        sudo apt install -y zsh
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y zsh
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y zsh
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y zsh
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add zsh
    elif command -v brew >/dev/null 2>&1; then
        brew install zsh
    elif command -v winget >/dev/null 2>&1; then
        winget install --id zsh.zsh --accept-package-agreements --accept-source-agreements
    elif command -v choco >/dev/null 2>&1; then
        choco install zsh -y
    elif command -v scoop >/dev/null 2>&1; then
        scoop install zsh
    else
        echo "Kein bekannter Paketmanager gefunden." >&2
        echo "Bitte zsh manuell installieren und das Skript erneut ausführen." >&2
        return 1
    fi

    if zsh_available; then
        echo "zsh: Installation abgeschlossen."
        return 0
    fi

    echo "zsh: Installation fehlgeschlagen oder nicht im PATH." >&2
    return 1
}

install_ohmyzsh() {
    echo "oh-my-zsh wird installiert …"
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended
    echo "oh-my-zsh: Installation abgeschlossen."
}

zsh_in_etc_shells() {
    local zsh_path="$1"
    [[ -f /etc/shells ]] || return 1
    grep -qxF "$zsh_path" /etc/shells && return 0
    local real_path
    real_path="$(readlink -f "$zsh_path" 2>/dev/null || true)"
    [[ -n "$real_path" ]] && grep -qxF "$real_path" /etc/shells
}

run_chsh() {
    local zsh_path="$1"

    if ! zsh_in_etc_shells "$zsh_path"; then
        echo "zsh steht nicht in /etc/shells — chsh nicht möglich." >&2
        return 1
    fi

    if [[ ! -r /dev/tty ]]; then
        echo "Kein Terminal für chsh verfügbar." >&2
        echo "Bitte manuell ausführen: chsh -s $zsh_path" >&2
        return 1
    fi

    echo "Passwort für chsh eingeben (erscheint nicht beim Tippen):" >/dev/tty
    if chsh -s "$zsh_path" </dev/tty >/dev/tty 2>&1; then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        echo "chsh erneut mit sudo …" >/dev/tty
        sudo chsh -s "$zsh_path" "$USER" </dev/tty >/dev/tty 2>&1
        return $?
    fi

    return 1
}

maybe_set_default_shell_zsh() {
    local zsh_path
    zsh_path="$(command -v zsh)" || return 0

    if [[ "${SHELL:-}" == "$zsh_path" ]]; then
        echo "Standard-Shell: bereits zsh."
        return 0
    fi

    local login_shell=""
    if command -v getent >/dev/null 2>&1; then
        login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
    fi
    if [[ -n "$login_shell" && "$login_shell" == "$zsh_path" ]]; then
        echo "Standard-Shell: bereits zsh (Login-Eintrag)."
        return 0
    fi

    if confirm "zsh als Standard-Shell setzen (Login/SSH)?"; then
        if run_chsh "$zsh_path"; then
            echo "Standard-Shell auf zsh gesetzt. Beim nächsten Login aktiv."
        else
            echo "chsh fehlgeschlagen — bitte manuell in einem Terminal:" >&2
            echo "  chsh -s $zsh_path" >&2
        fi
    else
        echo "Standard-Shell: unverändert (${SHELL:-${login_shell:-unbekannt}})."
    fi
}

setup_zsh_and_ohmyzsh() {
    echo "Zsh / oh-my-zsh"
    echo

    if zsh_available; then
        echo "zsh: bereits vorhanden ($(command -v zsh))."
    else
        if confirm "zsh installieren?"; then
            install_zsh_package || true
        else
            echo "zsh: übersprungen."
        fi
    fi

    echo

    if ! zsh_available; then
        echo "oh-my-zsh: übersprungen (zsh fehlt)."
        return 0
    fi

    if ohmyzsh_installed; then
        echo "oh-my-zsh: bereits installiert."
    elif confirm "oh-my-zsh installieren?"; then
        install_ohmyzsh
    else
        echo "oh-my-zsh: übersprungen."
    fi

    echo
    maybe_set_default_shell_zsh
}

status_item() {
    local label="$1"
    local ok="$2"
    if [[ "$ok" == "yes" ]]; then
        printf "  [ok]   %s\n" "$label"
    else
        printf "  [ -- ] %s\n" "$label"
    fi
}

cmd_status() {
    echo "shdft — Status"
    echo

    local file shell_type
    while IFS= read -r file; do
        if has_block "$file"; then
            status_item "$file (shdft-Block)" "yes"
        else
            status_item "$file (shdft-Block)" "no"
        fi
    done < <(managed_shell_files)

    if has_block "$HOME/.inputrc"; then
        status_item "$HOME/.inputrc (TAB-Completion)" "yes"
    else
        status_item "$HOME/.inputrc (TAB-Completion)" "no"
    fi

    echo
    if zsh_available; then
        status_item "zsh verfügbar" "yes"
    else
        status_item "zsh verfügbar" "no"
    fi

    if ohmyzsh_installed; then
        status_item "oh-my-zsh installiert" "yes"
    else
        status_item "oh-my-zsh installiert" "no"
    fi

    local login_shell=""
    if command -v getent >/dev/null 2>&1; then
        login_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"
    fi
    if [[ -n "$login_shell" ]] && [[ "$login_shell" == *zsh* ]]; then
        status_item "Standard-Shell: $login_shell" "yes"
    elif [[ -n "$login_shell" ]]; then
        status_item "Standard-Shell: $login_shell (nicht zsh)" "no"
    fi

    if [[ -n "${MSYSTEM:-}" ]]; then
        status_item "Git Bash erkannt ($MSYSTEM)" "yes"
    fi

    echo
}

cmd_uninstall() {
    echo "shdft — Deinstallation"
    echo

    local file
    while IFS= read -r file; do
        if has_block "$file"; then
            remove_block "$file"
            echo "  entfernt: $file"
        fi
    done < <(managed_shell_files)

    if has_block "$HOME/.inputrc"; then
        remove_block "$HOME/.inputrc"
        echo "  entfernt: ~/.inputrc"
    fi

    echo
    echo "shdft-Blöcke entfernt. Shell neu laden oder neu anmelden."
    echo
}

cmd_install() {
    echo "shdft — Einrichtung"
    echo

    setup_zsh_and_ohmyzsh
    echo

    local file
    while IFS= read -r file; do
        case "$file" in
            *".zshrc")
                write_block "$file" "zsh"
                ;;
            *".bash_profile")
                ensure_git_bash_sources_bashrc
                ;;
            *)
                write_block "$file" "bash"
                ;;
        esac
        echo "  eingerichtet: $file"
    done < <(managed_shell_files)

    write_inputrc_block
    echo "  eingerichtet: ~/.inputrc"

    echo
    echo "Konfiguration erfolgreich eingerichtet."
    echo
    echo "Änderungen aktivieren mit:"
    echo
    echo "    source ~/.bashrc"
    echo "oder"
    echo "    source ~/.zshrc"
    echo
    echo "oder einfach neu anmelden."
    echo
}

main() {
    case "${1:-}" in
        --status|--check)
            cmd_status
            ;;
        --uninstall)
            cmd_uninstall
            ;;
        -h|--help)
            usage
            ;;
        "")
            cmd_install
            ;;
        *)
            echo "Unbekannte Option: $1" >&2
            echo
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
