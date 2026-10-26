# shdft

Reproduzierbares Shell-, Terminal- und Agenten-Setup für **Linux** und **Windows/WSL** gleichwertig:
Shell-Standards, WezTerm, Herdr, Claude Code und Pi. Bedienkonzepte sind auf beiden Seiten dieselben; Installer und Pfade sind getrennt.

```
Linux (nativ)                          Windows 11 + WSL
└─ WezTerm                             └─ WezTerm (Acrylic, WSL-Domain)
   └─ Herdr                               └─ WSL Ubuntu
      ├─ Claude Code                         └─ Herdr
      └─ Pi                                     ├─ Claude Code
                                                └─ Pi
```

## Inhalt

- [Was drin ist](#was-drin-ist)
- [Schnellstart Linux](#schnellstart-linux)
- [Schnellstart Windows/WSL](#schnellstart-windowswsl)
- [Nur Shell-Standards](#nur-shell-standards)
- [Was sudo oder Administratorrechte braucht](#was-sudo-oder-administratorrechte-braucht)
- [Tastenbelegung](#tastenbelegung)
- [Ändern und aktualisieren](#ändern-und-aktualisieren)
- [Rückbau](#rückbau)
- [Was bewusst nicht drin ist](#was-bewusst-nicht-drin-ist)

## Was drin ist

| Was | Ort im Repo | Ziel | Wie |
|---|---|---|---|
| Shell-Standards (Aliase, Prompt, inputrc) | `setup-shell-defaults.sh`, `shell/bashrc-shdft.sh` | `~/.bashrc` / `~/.zshrc`, Block `# BEGIN shdft` | Skript oder Profil-Installer |
| Profil: PATH, nvm (, BROWSER unter WSL) | `profiles/*/shell/` | `~/.bashrc` / `~/.profile`, Block `# BEGIN shdft-profile` | Profil-Installer |
| Herdr, Claude, Pi, AGENTS.md | `home/` | `~/.config/herdr`, `~/.claude`, `~/.pi`, `~/.agents` | Symlink (Profil-Installer) |
| Claude/Pi Einstellungen (Whitelist) | `home/.claude/settings.json`, `home/.pi/agent/settings.json` | gleiche Pfade unter `$HOME` | Schlüssel hineinmischen |
| WezTerm Linux | `profiles/linux/wezterm.lua` | `~/.config/wezterm/wezterm.lua` | Symlink |
| WezTerm + `.wslconfig` Windows | `profiles/windows-wsl/windows/` | `%USERPROFILE%\.config\wezterm\`, `%USERPROFILE%\.wslconfig` | Kopie (`install.ps1`) |
| WSL Autostart / Font | `profiles/windows-wsl/install-admin.ps1`, `install-font.ps1` | Aufgabenplanung / Fonts | PowerShell |

Drei Arten, wie Dateien ins System kommen:

- **Symlink ins Repo:** echte Datei im Repo, `$HOME` zeigt darauf.
- **Schlüssel hineinmischen:** nur Whitelist-Keys per `jq`; Hooks, Permissions und Werkzeug-eigene Felder bleiben unberührt.
- **Markierter Block:** `# BEGIN <name>` … `# END <name>` in Shell-Dateien.

Sicherungen liegen unter `~/.shdft-backup/<Zeitstempel>/` bzw. `%USERPROFILE%\.shdft-backup\`. Alle Skripte sind mehrfach ausführbar und haben `--dry-run` bzw. `-WhatIf`.

## Schnellstart Linux

Voraussetzung: Linux-Desktop (z. B. EndeavourOS, Ubuntu). WezTerm und die Agenten-Werkzeuge kommen aus ihren eigenen Installern.

```bash
git clone https://github.com/thelad-dev/shdft.git
cd shdft/profiles/linux
./install-sudo.sh --dry-run
./install-sudo.sh
./install.sh --dry-run
./install.sh
exec bash -l
```

Werkzeuge (einzeln, nicht als Block einfügen):

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
exec bash -l
nvm install 24
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://herdr.dev/install.sh | sh
curl -fsSL https://pi.dev/install.sh | sh
npm install -g quota-axi
for b in node npm npx quota-axi; do ln -sfn "$NVM_BIN/$b" ~/.local/bin/$b; done
```

WezTerm und Hack Nerd Font über den Paketmanager oder die Upstream-Installer. WezTerm liest `~/.config/wezterm/wezterm.lua` (Symlink ins Repo).

## Schnellstart Windows/WSL

Reihenfolge: Windows vorbereiten, WSL-Systemteil, Konfiguration, Werkzeuge, Windows-Teil.

### 1. Windows vorbereiten

```powershell
wsl --install -d Ubuntu-24.04
```

WezTerm Nightly: [WezTerm-nightly-setup.exe](https://github.com/wezterm/wezterm/releases/tag/nightly).

### 2. Repo in WSL

```bash
sudo apt update && sudo apt install -y git gh
gh auth login
mkdir -p ~/workspaces
gh repo clone thelad-dev/shdft ~/workspaces/shdft
cd ~/workspaces/shdft/profiles/windows-wsl
```

### 3. Systemteil (sudo)

```bash
./install-sudo.sh --dry-run
./install-sudo.sh
sudo tailscale up   # einmalig, öffnet einen Link
```

### 4. Konfiguration

```bash
./install.sh --dry-run
./install.sh
exec bash -l
```

### 5. Werkzeuge

Wie unter Linux (nvm, Claude, Herdr, Pi, quota-axi und die Symlinks nach `~/.local/bin`).

### 6. Windows-Teil

```bash
ps1() { powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$1")" "${@:2}"; }
ps1 install.ps1 -WhatIf
ps1 install.ps1
ps1 install-font.ps1
```

Autostart-Aufgabe in einer Administrator-PowerShell:

```powershell
cd \\wsl.localhost\Ubuntu-24.04\home\<linux-benutzer>\workspaces\shdft\profiles\windows-wsl
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-admin.ps1
```

`windows/.wslconfig` ist ein Hardware-Beispiel (`memory=48GB`, `processors=8`). Vor `install.ps1` an die eigene Maschine anpassen (Faustregel: höchstens drei Viertel des Arbeitsspeichers).

## Nur Shell-Standards

Ohne WezTerm/Herdr/Claude/Pi:

```bash
curl -fsSL https://raw.githubusercontent.com/thelad-dev/shdft/main/setup-shell-defaults.sh | bash
```

Status / Rückbau: `--status` bzw. `--uninstall`. Details und oh-my-zsh-Abfragen wie bisher im Skript.

## Was sudo oder Administratorrechte braucht

| Schritt | Profil | Recht | Warum |
|---|---|---|---|
| Pakete `jq` (, `xdg-utils`, `curl`) | beide | sudo | Merge, Statuszeile, Browser-Helfer, Installer |
| `/usr/local/bin/claude` Symlink | beide | sudo | Herdr-Panes finden claude ohne `~/.local/bin` im PATH |
| `loginctl enable-linger` | beide | sudo | Benutzerdienste ohne offenes Terminal |
| Tailscale | beide | sudo | Lavish über das Tailnet |
| `/etc/wsl.conf` | windows-wsl | sudo | systemd und Standardbenutzer |
| `wsl --install` | windows-wsl | Administrator | WSL-Funktion |
| Autostart-Aufgabe | windows-wsl | Administrator | Start ohne Anmeldung |
| Hack Nerd Font | windows-wsl | keins (HKCU) | eigener Benutzer |

## Tastenbelegung

### WezTerm

| Taste | Wirkung |
|---|---|
| Mittelklick | Zwischenablage einfügen, auch in Herdr |
| Umschalt+Enter, Strg+Enter | dank Kitty-Keyboard unterscheidbar an Herdr und Claude Code |
| Rücktaste, Entf | klassisch löschen, auch bei aktivem Kitty-Keyboard |
| Strg+Umschalt+C / V | Kopieren / Einfügen |
| Strg+Umschalt+T / N / W | neuer Tab / neues Fenster / Tab schließen |
| Strg+Umschalt+R | Konfiguration neu laden |
| Alt+Enter | Vollbild |

Nur das erste Fenster nach dem Start hängt sich in Herdr; neue Tabs öffnen eine normale Shell.

### Herdr

Präfix **Strg+B**, dann Taste:

| Taste | Wirkung |
|---|---|
| A / S / W / D | Fokus links / unten / oben / rechts |
| - / + | Pane teilen horizontal / vertikal |
| T / Q | Tab neu / schließen |
| Leertaste | Workspace |
| G / Y / , / ? | Springen / Scrollback / Einstellungen / Hilfe |
| Rücktaste | abkoppeln |

### Claude Code

| Taste | Wirkung |
|---|---|
| Umschalt+Enter | Zeilenumbruch |
| Strg+Enter | Nachricht einreihen |
| Esc / Esc Esc | Abbruch / zurückspringen |
| Umschalt+Tab | Modus wechseln |

Statuszeile: Modell, Kontext und Limits rechtsbündig (`quota-axi` optional).

## Ändern und aktualisieren

| Ich will ... | So |
|---|---|
| Herdr/Claude/Pi/AGENTS ändern | Datei unter `~` bearbeiten (Symlink), im Repo committen |
| settings-Whitelist erweitern | Key in `home/.claude/settings.json` bzw. `home/.pi/...` eintragen, Profil-`install.sh` |
| WezTerm Linux | `profiles/linux/wezterm.lua`, `./install.sh` |
| WezTerm / `.wslconfig` Windows | Datei unter `profiles/windows-wsl/windows/`, dann `install.ps1` |
| Shell-Aliase | `shell/bashrc-shdft.sh` bzw. `setup-shell-defaults.sh`, dann Installer |

## Rückbau

```bash
# im jeweiligen Profilverzeichnis
./install.sh --uninstall --dry-run
./install.sh --uninstall
```

Shell allein: `./setup-shell-defaults.sh --uninstall`.

Windows zusätzlich (Administrator): `schtasks /delete /tn "WSL Ubuntu Autostart" /f`.
WezTerm/`.wslconfig` aus `%USERPROFILE%\.shdft-backup\` zurückkopieren oder löschen.

## Was bewusst nicht drin ist

- Keine Tokens, keine `auth.json`, nichts aus `~/.ssh` oder anderen Zugangsdaten.
  `apiKey: "strata-local"` in `models.json` ist ein Platzhalter für den lokalen Strata-Server auf `127.0.0.1`.
- Keine `permissions`- und `hooks`-Blöcke in Claude-Settings (Maschinen-/Firstmate-Sache).
- Keine Organisations-Interna und keine Hostnamen aus fremden Netzen.
- Keine Laufzeitdaten (Herdr-Sitzungen, Pi-Sessions, Claude-Projekte).
- Keine Binärdateien der Werkzeuge.

Vor jedem Push: `gitleaks git .` sollte "no leaks found" melden.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
