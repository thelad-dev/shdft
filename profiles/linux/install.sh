#!/usr/bin/env bash
# Richtet das Linux-Profil von shdft ein, ohne sudo:
# Symlinks ins Repo, bewusst gesetzte JSON-Schlüssel mischen,
# markierte Blöcke in ~/.bashrc und ~/.profile pflegen, WezTerm-Konfiguration verlinken,
# Hack Nerd Font ins Benutzerverzeichnis legen.
# Abweichende vorhandene Dateien werden vorher nach ~/.shdft-backup/<Zeitstempel>/ gesichert.
# Mehrfach ausführbar: ein zweiter Lauf meldet jeden Schritt als unverändert.
set -euo pipefail

usage() {
	cat <<'EOF'
Aufruf: ./install.sh [--dry-run] [--uninstall]

  --dry-run    nur anzeigen, was geschehen würde; schreibt nichts
  --uninstall  Symlinks ins Repo und die markierten Shell-Blöcke wieder entfernen
  -h, --help   diese Hilfe
EOF
}

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
	case "$arg" in
	-n | --dry-run) DRY_RUN=1 ;;
	--uninstall) UNINSTALL=1 ;;
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

PROFILE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd "$PROFILE/../.." && pwd -P)
HOME_SRC="$ROOT/home"
SHELL_SRC="$ROOT/shell"
BACKUP="$HOME/.shdft-backup/$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

LINKS=(
	.config/herdr/config.toml
	.claude/statusline.sh
	.claude/keybindings.json
	.claude/CLAUDE.md
	.agents/AGENTS.md
	.pi/agent/models.json
)
MERGES=(
	.claude/settings.json
	.pi/agent/settings.json
)

if [ "$DRY_RUN" = 1 ]; then
	echo "Trockenlauf: es wird nichts geschrieben."
fi

report() { printf '  %-12s %s\n' "$1" "$2"; }
would() { [ "$DRY_RUN" = 1 ] && report "würde" "$1"; }

backup() {
	local path=$1 rel dest
	rel=${path#"$HOME"/}
	dest="$BACKUP/$rel"
	if [ -e "$dest" ] || [ -L "$dest" ]; then return; fi
	mkdir -p "$(dirname "$dest")"
	cp -P -p "$path" "$dest"
	BACKED_UP=1
	report "gesichert" "$rel -> ${dest#"$HOME"/}"
}

write_file() {
	local tmp=$1 dest=$2 label=${3:-${2#"$HOME"/}}
	if [ -e "$dest" ] && cmp -s "$tmp" "$dest"; then
		report "unverändert" "$label"
		return
	fi
	if [ -e "$dest" ] || [ -L "$dest" ]; then
		if would "$label schreiben (vorher sichern)"; then return; fi
		backup "$dest"
	elif would "$label anlegen"; then
		return
	fi
	mkdir -p "$(dirname "$dest")"
	cat "$tmp" >"$dest"
	report "geschrieben" "$label"
}

own_link() {
	local rel=${1#"$HOME"/} target
	[ -L "$1" ] || return 1
	target=$(readlink "$1")
	case "$target" in
	*/home/"$rel" | */profiles/linux/wezterm.lua) true ;;
	*) false ;;
	esac
}

link() {
	local target=$1 dest=$2 rel=${2#"$HOME"/}
	if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$target" ]; then
		report "unverändert" "$rel"
		return
	fi
	if [ -d "$dest" ] && [ ! -L "$dest" ]; then
		echo "Fehler: $dest ist ein Verzeichnis, erwartet war eine Datei." >&2
		exit 1
	fi
	local save=0
	if [ -e "$dest" ] || [ -L "$dest" ]; then
		save=1
		if { [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$dest" "$target"; } || own_link "$dest"; then save=0; fi
	fi
	if [ "$save" = 1 ]; then
		if would "$rel -> $target verlinken (vorher sichern)"; then return; fi
		backup "$dest"
	elif would "$rel -> $target verlinken"; then
		return
	fi
	mkdir -p "$(dirname "$dest")"
	ln -sfn "$target" "$dest"
	report "verlinkt" "$rel -> $target"
}

merge_json() {
	local src=$1 dest=$2 tmp
	tmp=$(mktemp)
	if [ -e "$dest" ]; then
		if ! jq -e . "$dest" >/dev/null 2>&1; then
			echo "Fehler: ${dest} ist kein gültiges JSON, bitte von Hand prüfen." >&2
			rm -f "$tmp"
			exit 1
		fi
		jq -s '.[0] * .[1]' "$dest" "$src" >"$tmp"
		if [ "$(jq -S . "$tmp")" = "$(jq -S . "$dest")" ]; then
			report "unverändert" "${dest#"$HOME"/}"
			rm -f "$tmp"
			return
		fi
	else
		jq . "$src" >"$tmp"
	fi
	write_file "$tmp" "$dest"
	rm -f "$tmp"
}

block() {
	local file=$1 name=$2 content=$3 tmp
	tmp=$(mktemp)
	if [ -e "$file" ] && grep -qxF "# BEGIN $name" "$file"; then
		awk -v name="$name" -v content="$content" '
			$0 == "# BEGIN " name { print; while ((getline line < content) > 0) print line; skip = 1; next }
			$0 == "# END " name { skip = 0 }
			!skip { print }
		' "$file" >"$tmp"
	else
		{
			[ -e "$file" ] && cat "$file"
			printf '\n# BEGIN %s\n' "$name"
			cat "$content"
			printf '# END %s\n' "$name"
		} >"$tmp"
	fi
	write_file "$tmp" "$file" "${file#"$HOME"/} (Block $name)"
	rm -f "$tmp"
}

unblock() {
	local file=$1 name=$2 tmp
	if [ ! -e "$file" ] || ! grep -qxF "# BEGIN $name" "$file"; then
		report "fehlt" "${file#"$HOME"/}: Block $name"
		return
	fi
	tmp=$(mktemp)
	awk -v name="$name" '
		$0 == "# BEGIN " name { held = 0; skip = 1; next }
		$0 == "# END " name { skip = 0; next }
		skip { next }
		held { print ""; held = 0 }
		$0 == "" { held = 1; next }
		{ print }
		END { if (held) print "" }
	' "$file" >"$tmp"
	write_file "$tmp" "$file" "${file#"$HOME"/} (Block $name entfernen)"
	rm -f "$tmp"
}

oldest_backup() {
	local dir
	for dir in "$HOME"/.shdft-backup/*/; do
		if [ -L "$dir$1" ] && own_link "$dir$1"; then continue; fi
		if [ -e "$dir$1" ] || [ -L "$dir$1" ]; then
			printf '%s\n' "$dir$1"
			return
		fi
	done
}

unlink_one() {
	local dest=$1 target=$2 rel=${1#"$HOME"/} saved
	if [ ! -L "$dest" ] || [ "$(readlink "$dest")" != "$target" ]; then
		report "übrig" "$rel (kein Symlink von install.sh, bleibt)"
		return
	fi
	saved=$(oldest_backup "$rel")
	if [ -n "$saved" ]; then
		would "$rel aus ${saved#"$HOME"/} zurückholen" || { rm "$dest" && cp -P -p "$saved" "$dest" && report "zurückgeholt" "$rel aus ${saved#"$HOME"/}"; }
	else
		would "$rel entfernen" || { rm "$dest" && report "entfernt" "$rel"; }
	fi
}

uninstall() {
	local rel
	echo "Symlinks entfernen (eigene frühere Fassung zurückholen, falls gesichert):"
	for rel in "${LINKS[@]}"; do unlink_one "$HOME/$rel" "$HOME_SRC/$rel"; done
	unlink_one "$HOME/.pi/agent/AGENTS.md" "$HOME/.agents/AGENTS.md"
	unlink_one "$HOME/.config/wezterm/wezterm.lua" "$PROFILE/wezterm.lua"

	echo "Shell-Blöcke entfernen:"
	unblock "$HOME/.bashrc" shdft
	unblock "$HOME/.bashrc" shdft-profile
	unblock "$HOME/.profile" shdft-profile
	cat <<'EOF'

Nicht zurückgebaut: die gemischten Schlüssel in ~/.claude/settings.json und ~/.pi/agent/settings.json,
weil sie vor der Installation schon dort gestanden haben können.
statusLine zeigt danach auf das entfernte ~/.claude/statusline.sh; Claude Code zeigt dann einfach keine Statuszeile.
Wer den Schlüssel loswerden will: jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
Hack Nerd Font unter ~/.local/share/fonts wird nicht entfernt.
Alle früheren Fassungen liegen weiter unter ~/.shdft-backup/<Zeitstempel>/.
EOF
}

install() {
	local rel
	command -v jq >/dev/null 2>&1 || {
		echo "Fehler: jq fehlt. Erst ./install-sudo.sh ausführen (installiert jq) oder: sudo apt install jq / sudo pacman -S jq" >&2
		exit 1
	}

	echo "Konfigurationsdateien (Symlinks ins Repo):"
	for rel in "${LINKS[@]}"; do link "$HOME_SRC/$rel" "$HOME/$rel"; done
	link "$HOME/.agents/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
	link "$PROFILE/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"

	echo "Einstellungen (Schlüssel aus dem Repo mischen):"
	for rel in "${MERGES[@]}"; do merge_json "$HOME_SRC/$rel" "$HOME/$rel"; done

	echo "Shell-Blöcke:"
	block "$HOME/.bashrc" shdft "$SHELL_SRC/bashrc-shdft.sh"
	block "$HOME/.bashrc" shdft-profile "$PROFILE/shell/bashrc-profile.sh"
	block "$HOME/.profile" shdft-profile "$PROFILE/shell/profile-profile.sh"

	echo "Schrift (Hack Nerd Font):"
	if [ "$DRY_RUN" = 1 ]; then
		"$PROFILE/install-font.sh" --dry-run
	else
		"$PROFILE/install-font.sh"
	fi

	if [ "$BACKED_UP" = 1 ]; then
		echo
		echo "Sicherungen: $BACKUP"
	fi
	cat <<'EOF'

Fertig. Neue Shell-Blöcke gelten in neuen Shells (oder sofort: exec bash -l).
Nächste Schritte siehe README: Werkzeuge installieren (nvm, Claude, Herdr, Pi).
Shell allein ohne Profil: ../../setup-shell-defaults.sh
EOF
}

if [ "$UNINSTALL" = 1 ]; then uninstall; else install; fi
