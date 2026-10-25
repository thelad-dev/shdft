#!/usr/bin/env bash
# Die Linux-Schritte von shdft, die root brauchen. Jeder Schritt prüft erst, ob er schon erledigt ist,
# zeigt dann die Befehle und fragt einzeln nach. Läuft als normaler Benutzer und ruft sudo pro Befehl auf.
set -euo pipefail

usage() {
	cat <<'EOF'
Aufruf: ./install-sudo.sh [--dry-run] [--yes]

  --dry-run   nur anzeigen, welche Schritte offen sind und welche Befehle liefen
  --yes       offene Schritte ohne Einzelnachfrage ausführen
  -h, --help  diese Hilfe

Schritte:
  1. Pakete jq und curl (für install.sh, die Statuszeile und die Werkzeug-Installer)
  2. /usr/local/bin/claude -> ~/.local/bin/claude (Herdr-Panes finden claude auch ohne ~/.local/bin im PATH)
  3. loginctl enable-linger (Benutzerdienste laufen ohne offenes Terminal weiter)
  4. Tailscale installieren und tailscaled aktivieren (optional für Lavish über das Tailnet)
EOF
}

DRY_RUN=0
YES=0
for arg in "$@"; do
	case "$arg" in
	-n | --dry-run) DRY_RUN=1 ;;
	-y | --yes) YES=1 ;;
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
	echo "Bitte als normaler Benutzer starten, nicht mit sudo: das Skript braucht das HOME des Benutzers und ruft sudo selbst auf." >&2
	exit 1
fi

PACKAGES=(jq curl)
CLAUDE_LINK=/usr/local/bin/claude

if [ "$DRY_RUN" = 1 ]; then
	echo "Trockenlauf: es wird nichts ausgeführt."
fi

step() {
	local title=$1 done_note=$2
	shift 2
	echo
	echo "== $title"
	if [ -n "$done_note" ]; then
		echo "   erledigt: $done_note"
		return
	fi
	printf '   $ %s\n' "$@"
	if [ "$DRY_RUN" = 1 ]; then
		echo "   (Trockenlauf, nicht ausgeführt)"
		return
	fi
	if [ "$YES" != 1 ]; then
		local answer
		read -r -p "   Ausführen? [j/N] " answer
		case "$answer" in
		j | J | y | Y) ;;
		*)
			echo "   übersprungen"
			return
			;;
		esac
	fi
	local cmd
	for cmd in "$@"; do bash -c "$cmd"; done
	echo "   ausgeführt"
}

systemd_running() { [ "$(ps -p 1 -o comm= 2>/dev/null)" = systemd ]; }

pkg_missing() {
	local pkg=$1
	if command -v dpkg-query >/dev/null 2>&1; then
		dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' && return 1
		return 0
	fi
	if command -v pacman >/dev/null 2>&1; then
		pacman -Qi "$pkg" >/dev/null 2>&1 && return 1
		return 0
	fi
	if command -v rpm >/dev/null 2>&1; then
		rpm -q "$pkg" >/dev/null 2>&1 && return 1
		return 0
	fi
	command -v "$pkg" >/dev/null 2>&1 && return 1
	return 0
}

install_pkgs_cmd() {
	local pkgs=("$@")
	if command -v pacman >/dev/null 2>&1; then
		printf 'sudo pacman -Sy --needed --noconfirm %s' "${pkgs[*]}"
	elif command -v apt-get >/dev/null 2>&1; then
		printf 'sudo apt-get update && sudo apt-get install -y %s' "${pkgs[*]}"
	elif command -v dnf >/dev/null 2>&1; then
		printf 'sudo dnf install -y %s' "${pkgs[*]}"
	elif command -v zypper >/dev/null 2>&1; then
		printf 'sudo zypper install -y %s' "${pkgs[*]}"
	else
		echo "Kein bekannter Paketmanager gefunden; bitte jq und curl von Hand installieren." >&2
		exit 1
	fi
}

missing=()
for pkg in "${PACKAGES[@]}"; do
	pkg_missing "$pkg" && missing+=("$pkg")
done
note=""
[ ${#missing[@]} = 0 ] && note="${PACKAGES[*]} installiert"
if [ ${#missing[@]} = 0 ]; then
	step "Pakete ${PACKAGES[*]}" "$note"
else
	step "Pakete ${PACKAGES[*]}" "" "$(install_pkgs_cmd "${missing[@]}")"
fi

note=""
[ "$(readlink "$CLAUDE_LINK" 2>/dev/null)" = "$HOME/.local/bin/claude" ] && note="$CLAUDE_LINK -> $HOME/.local/bin/claude"
step "claude systemweit auffindbar" "$note" \
	"sudo ln -sfn $HOME/.local/bin/claude $CLAUDE_LINK"

later() {
	echo
	echo "== $1"
	echo "   später: systemd läuft noch nicht. Nach einem System mit systemd dieses Skript erneut starten."
}

if systemd_running; then
	note=""
	[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = yes ] && note="Linger=yes für $USER"
	step "Benutzerdienste ohne Login (linger)" "$note" \
		"sudo loginctl enable-linger $USER"
else
	later "Benutzerdienste ohne Login (linger)"
fi

if systemd_running; then
	note=""
	if command -v tailscale >/dev/null 2>&1 && systemctl is-enabled tailscaled >/dev/null 2>&1; then
		note="tailscale installiert, tailscaled aktiviert"
	fi
	step "Tailscale" "$note" \
		"curl -fsSL https://tailscale.com/install.sh | sh" \
		"sudo systemctl enable --now tailscaled"
	[ -n "$note" ] || echo "   Danach einmalig anmelden (öffnet einen Link): sudo tailscale up"
else
	later "Tailscale"
fi
