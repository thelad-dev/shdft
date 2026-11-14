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
- [/shdftupdate](#shdftupdate)
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
| Hack Nerd Font Linux | `profiles/linux/install-font.sh` | `~/.local/share/fonts` | Skript (`install.sh` ruft es auf) |
| `/shdftupdate` (Skill und Skript) | `home/.claude/skills/shdftupdate/`, `profiles/shared/shdftupdate.sh` | `~/.claude/skills/shdftupdate/` | Symlink (Skill), Skript läuft aus dem Klon |
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

WezTerm über den Paketmanager oder den Upstream-Installer. `./install.sh` legt Hack Nerd Font nach `~/.local/share/fonts` (auch einzeln: `./install-font.sh`), außer Fontconfig kennt die Schrift schon systemweit, etwa aus dem Paket `ttf-hack-nerd`. WezTerm liest `~/.config/wezterm/wezterm.lua` (Symlink ins Repo).

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
| Hack Nerd Font | linux | keins | eigener Benutzer, `~/.local/share/fonts` |
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
| Hack Nerd Font Linux | `profiles/linux/install-font.sh`, auch über `./install.sh` |
| WezTerm / `.wslconfig` Windows | Datei unter `profiles/windows-wsl/windows/`, dann `install.ps1` |
| Shell-Aliase | `shell/bashrc-shdft.sh` bzw. `setup-shell-defaults.sh`, dann Installer |
| Änderungen aus dem Repo auf einem Rechner nachziehen | `/shdftupdate` (siehe unten), statt den Installer noch einmal zu starten |
| Lokale Änderungen eines Rechners ins Repo bringen | `/shdftupdate` bereitet einen Zweig vor, Push und PR macht der Nutzer |

## /shdftupdate

Zieht die shdft-Einstellungen auf jedem Rechner nach, ohne je Lokales zu überschreiben, und bereitet für lokale Abweichungen einen PR vor.
Der Installer bleibt der Weg für die Ersteinrichtung; `/shdftupdate` ist der Weg für alles danach.

```bash
profiles/shared/shdftupdate.sh [--dry-run] [--no-propose] [--local] [-v] [--repo PFAD]
```

In Claude Code genügt `/shdftupdate` (der Skill liegt über `install.sh` als Symlink in `~/.claude/skills/shdftupdate/`). Nachgezogene Skills und `CLAUDE.md` wirken erst in einer neuen Claude-Sitzung.

Das Skript findet den Klon über `--repo`, `SHDFT_REPO`, den eigenen Ort, den Symlink `~/.claude/CLAUDE.md`, dann `~/shdft` und `~/workspaces/shdft`. Weitere Umgebung: `SHDFT_PROFILE` (`linux` oder `windows-wsl`, sonst WSL-Erkennung), `SHDFT_CONFIG_DIR` (Standard `~/.config/shdft`), `SHDFT_STATE_DIR` (Standard `~/.local/state/shdft`).
Exit 0: aktuell oder sicher nachgezogen. Exit 1: etwas zu melden (Abweichung, Divergenz, offline, Rechner nicht erreichbar, Sicherheitsfund). Exit 2: Aufruf- oder Umgebungsfehler.

**Ablauf**

1. **Klon:** `git fetch`, dann Fast-Forward auf `origin/main`, nur auf `main` und nur, wenn `HEAD` ein Vorfahre ist. Voraus, divergiert, anderer Zweig, offline, umgeschriebenes `origin/main` und lokale Änderungen im Weg werden gemeldet, nichts wird erzwungen. Nie `stash`, `reset` oder `checkout --`. Dateien werden nur nachgezogen oder angelegt, wenn der Klon auf `main` steht und `HEAD` gleich `origin/main` ist (nach dem Fast-Forward oder schon aktuell) oder der Abruf offline scheiterte und der Klon auf `main` steht; sonst wird nur verglichen und gemeldet.
2. **Dateien:** Jede verwaltete Datei (alles unter `home/`, die Profil-Dateien, die Shell-Blöcke, unter WSL die Browser-Vorlage) wird mit `HEAD` verglichen, und zwar mit dem Inhalt, den `$HOME` tatsächlich liefert (bei einem Symlink also der Arbeitsbaum des Klons).
3. **Vorschlag:** Für lokal Abweichendes entsteht ein Zweig `shdftupdate/<Zeitstempel>` in einem eigenen Arbeitsbaum unter `$SHDFT_STATE_DIR/proposals/`. Der Inhalt ist ein Dreiwege-Merge aus der lokalen Fassung, dem früheren Repo-Stand mit dem kleinsten Diff zu ihr und dem heutigen `HEAD`: Der Vorschlag enthält die lokale Änderung und den aktuellen Repo-Stand, dreht also nie Änderungen aus dem Repo zurück. Bei einem Merge-Konflikt wird die Datei nicht vorgeschlagen und der Grund gemeldet. Ein gleicher, schon vorbereiteter Vorschlag wird wiederverwendet statt neu angelegt. Ausgegeben werden Zweig, Dateien und die Befehle `git push -u origin <zweig>` und `gh pr create ...` als Text. Das Skript pusht nie und öffnet nie einen PR.
4. **Weitere Rechner:** siehe Hosts-Liste.

**Zustände je Datei**

| Zustand | Bedeutung | Aktion |
|---|---|---|
| gleich | Inhalt stimmt mit `HEAD` überein | keine |
| Repo neuer | weicht ab, stimmt aber mit einem früheren Stand dieser Datei im Repo überein | nachziehen, vorher Sicherung nach `~/.shdft-backup/<Zeitstempel>/` |
| lokal anders | stimmt mit keinem Repo-Stand überein | nie überschreiben; melden mit Diff-Zusammenfassung (`-v` zeigt den gekürzten Diff), Vorschlag |
| fehlt | Ziel fehlt, ein kaputter Symlink zählt dazu | neu anlegen, aber nur, wenn überhaupt eine verwaltete Datei auf dem Rechner liegt; sonst der Hinweis, `profiles/<profil>/install.sh` auszuführen |

Einstellungen (`settings.json` von Claude und Pi) werden schlüsselweise verglichen: Ein lokal anderer Wert macht die Datei "lokal anders" und wird nie überschrieben, Schlüssel nur auf dem Rechner (Hooks, Permissions, Plugins) sind nie eine Abweichung und kommen nie in einen Vorschlag. Ein Symlink, der auf einen anderen Klon zeigt, wird nur gemeldet, nie umgelegt. Durch einen Symlink wird nie geschrieben: Ein Link in den eigenen Klon liest dessen Arbeitsbaum, der gehört git. Weicht er von `HEAD` ab, auch weil jemand die Datei auf einen älteren Repo-Stand zurückgesetzt hat, ist das "lokal anders (Arbeitsbaum)" und wird nur gemeldet. Ist `~/.bashrc` oder `settings.json` ein Symlink, wird nichts hineingeschrieben, sondern ein Problem gemeldet. Schlägt die Sicherung nach `~/.shdft-backup/` fehl, wird die Datei nicht überschrieben.
Es gibt keine Basis-Hashes vom letzten Ausrollen. Ob "Repo neuer" oder "lokal anders" gilt, entscheidet die Git-Historie der Datei.
Kein Vorschlag entsteht, solange `HEAD` nicht gleich `origin/main` ist: Er wäre sonst auf einer anderen Basis gebaut, als die Abweichung gemessen wurde.

**Hosts-Liste**

`$SHDFT_CONFIG_DIR/hosts` (Standard `~/.config/shdft/hosts`) enthält je Zeile einen ssh-Alias, Leerzeilen und `#`-Kommentare sind erlaubt. Dann läuft derselbe Lauf per `ssh -o BatchMode=yes -o ConnectTimeout=10 <alias> 'bash -s -- --local ...' < shdftupdate.sh` auf den Gegenstellen, mit der Meldung je Rechner. Hat eine Gegenstelle den Klon nicht, steht dort "kein shdft-Repo auf diesem Rechner". Ist sie nicht erreichbar, zählt das als Meldung (Exit 1). Ohne Liste läuft nur der lokale Rechner; `--local` unterdrückt die Liste.

**Sicherheitsprüfung (das Repo ist öffentlich)**

Vor jedem Vorschlag werden nur die gegenüber `HEAD` neu hinzugekommenen Zeilen jeder Datei geprüft auf Tokens (GitHub, GitLab, npm, Hugging Face, Stripe, DigitalOcean, `sk-`, Slack, AWS, Google, JWT, `Authorization: Basic|Bearer`), private Schlüssel, Kennwörter (`password`, `pass`, `pwd`, `passphrase`, `secret`, `token`, `api_key`, `access_key` und Ähnliches, auch als Teil von Namen wie `DB_PASS`, mit Wert; auch `curl -u nutzer:kennwort`), private IP-Adressen (IPv4 und `fc00::/7`; `127.0.0.1` ist erlaubt), Mailadressen (außer `@users.noreply.github.com`, `noreply@` und der scp-Form `git@host:pfad`), feste Benutzerpfade (`/home/<name>`, `/Users/<name>`, `/mnt/<laufwerk>/Users/<name>`, `C:\Users\<name>`, UNC-Pfade) und Verbindungszeichenfolgen. Als Platzhalter für Kennwörter gelten nur `$NAME`, `${NAME}`, `<...>`, `@NAME@` und `strata-local`. Eine Datei mit Fund fällt allein aus dem Vorschlag; die Meldung nennt Datei, Zeile und Art mit einem maskierten Auszug (nie den Klartext, auch nicht mit `-v`; bei Mailadressen nur die Domain).
Commits tragen nur eine Noreply-Identität (`@users.noreply.github.com`), nie die globale Git-Identität und nie einen Co-Autor. Reihenfolge: `git config --local user.name`/`user.email` des Klons, dann die Umgebungsvariable `SHDFT_AUTHOR` (`Name <adresse>`), dann der jüngste Commit auf `origin/main`, dessen Noreply-Adresse den Besitzer der `origin`-URL (`github.com/<besitzer>/...`) als Login trägt. Die beiden ersten zählen nur mit Noreply-Adresse; ein fremder Autor wird nie genommen. Ohne passende Identität bleibt es bei vorbereiteten Dateien und den Commit-Befehlen im Text.

**Grenzen**

- Die Windows-Seite (`profiles/windows-wsl/windows/`, `.wslconfig`, `install.ps1`) liegt auf Windows-Pfaden und wird nicht geprüft; die Ausgabe nennt das unter WSL.
- Vorschläge für Einstellungen (`settings.json`) werden mit `jq` neu formatiert, der Diff im PR kann deshalb mehr Zeilen zeigen als geändert wurden.
- Ohne `jq` bricht das Skript mit Exit 2 ab (installiert `install-sudo.sh`).
- Der Trockenlauf (`--dry-run`) schreibt nichts, ruft aber `origin` ab und vergleicht die Dateien gegen den noch alten `HEAD`.
- Für den Abruf setzt das Skript `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` nur, wenn weder diese Umgebungsvariable noch `core.sshCommand` gesetzt ist.
- Tests: `tests/run.sh` (reine bash-Tests mit temporären Repos, danach `shellcheck`, sofern installiert; `SHELLCHECK=<pfad>` nimmt eines abseits des `PATH`).

## Rückbau

```bash
# im jeweiligen Profilverzeichnis
./install.sh --uninstall --dry-run
./install.sh --uninstall
```

Shell allein: `./setup-shell-defaults.sh --uninstall`.
Hack Nerd Font unter `~/.local/share/fonts` bleibt beim Rückbau liegen.

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
