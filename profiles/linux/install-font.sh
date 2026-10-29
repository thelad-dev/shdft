#!/usr/bin/env bash
# Installiert Hack Nerd Font v3.4.0 für den aktuellen Benutzer (ohne root).
# Lädt Hack.zip aus dem Release v3.4.0 von github.com/ryanoasis/nerd-fonts, prüft die SHA-256-Summe,
# legt die vier Schnitte Regular, Bold, Italic und BoldItalic unter ~/.local/share/fonts ab
# und aktualisiert den Fontconfig-Cache. Bereits installierte Schnitte mit passender Prüfsumme
# bleiben unverändert; dann wird nichts heruntergeladen.
# WezTerm sieht die Schrift nach einem Neustart.
set -euo pipefail

usage() {
    cat <<'EOF'
Aufruf: ./install-font.sh [--dry-run]

  --dry-run   nur anzeigen, was geschehen würde; lädt nichts herunter
  -h, --help  diese Hilfe
EOF
}

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
    -n | --dry-run) DRY_RUN=1 ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Unbekannte Option: $arg" >&2
        usage >&2
        exit 2
        ;;
    esac
done

if [ "$(id -u)" = 0 ]; then
    echo "Bitte als normaler Benutzer starten, nicht mit sudo: die Schrift gehört ins eigene ~/.local/share/fonts." >&2
    exit 1
fi

# Dieselbe Quelle und dieselben Prüfsummen wie profiles/windows-wsl/install-font.ps1.
ZIP_URL='https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/Hack.zip'
ZIP_SHA256='8CA33A60C791392D872B80D26C42F2BFA914A480F9EB2D7516D9F84373C36897'
FONT_DIR="${HOME}/.local/share/fonts"
STYLES=(Regular Bold Italic BoldItalic)

sha_of() {
    case "$1" in
    Regular) printf '%s\n' '7E6B5D86BAEE613984B10CEF14C8D6AEE86C976A3D1CBD87ABFFD424D6EC4C64' ;;
    Bold) printf '%s\n' '7FB835CBD3273D509868DCD4E03EAB3DC98679AC0BDFFD52EF23411244396082' ;;
    Italic) printf '%s\n' 'B65EDFCBDCE25A6F359B6AD129F51FC0B7C59E4893676FC3B75A4F49E3A12B18' ;;
    BoldItalic) printf '%s\n' '1A6FDC79F82BEB3CA3A0BC2088568A24B094B55F0F93CBF9731BF8E1EDE85D6B' ;;
    *)
        echo "Unbekannter Schnitt: $1" >&2
        exit 1
        ;;
    esac
}

file_sha256() {
    sha256sum -- "$1" | awk '{print toupper($1)}'
}

font_file() {
    printf '%s\n' "${FONT_DIR}/HackNerdFont-$1.ttf"
}

installed() {
    local file
    file=$(font_file "$1")
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    [ "$(file_sha256 "$file")" = "$(sha_of "$1")" ]
}

report() { printf '  %-12s %s\n' "$1" "$2"; }

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Fehler: $1 fehlt." >&2
        exit 1
    }
}

missing=()
echo 'Hack Nerd Font v3.4.0:'
for style in "${STYLES[@]}"; do
    name="HackNerdFont-${style}.ttf"
    if installed "$style"; then
        report 'unverändert' "$name"
    else
        missing+=("$style")
        if [ "$DRY_RUN" = 1 ]; then
            report 'würde' "$name"
        fi
    fi
done

if [ "${#missing[@]}" -eq 0 ]; then
    exit 0
fi
if [ "$DRY_RUN" = 1 ]; then
    exit 0
fi

need curl
need unzip
need sha256sum
need fc-cache

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
zip="${work}/Hack.zip"
curl -fsSL --retry 3 --retry-delay 2 -o "$zip" "$ZIP_URL"
actual=$(file_sha256 "$zip")
if [ "$actual" != "$ZIP_SHA256" ]; then
    echo "Fehler: Prüfsumme von Hack.zip stimmt nicht: erwartet ${ZIP_SHA256}, erhalten ${actual}" >&2
    exit 1
fi

mkdir -p "$FONT_DIR"
for style in "${missing[@]}"; do
    name="HackNerdFont-${style}.ttf"
    unzip -q -j -o "$zip" "$name" -d "${work}/out"
    src="${work}/out/${name}"
    got=$(file_sha256 "$src")
    if [ "$got" != "$(sha_of "$style")" ]; then
        echo "Fehler: Prüfsumme von ${name} stimmt nicht: erwartet $(sha_of "$style"), erhalten ${got}" >&2
        exit 1
    fi
    target=$(font_file "$style")
    if [ -L "$target" ]; then
        echo "Fehler: ${target} ist ein Symlink, erwartet war eine Datei." >&2
        exit 1
    fi
    cp -f "$src" "$target"
    chmod 644 "$target"
    report 'installiert' "$name"
done

fc-cache -f "$FONT_DIR"
if ! fc-list 'Hack Nerd Font' file | grep -F 'HackNerdFont-Regular.ttf' >/dev/null; then
    echo 'Fehler: Fontconfig listet Hack Nerd Font nicht.' >&2
    exit 1
fi
echo 'WezTerm neu starten, damit die Schrift erscheint.'
