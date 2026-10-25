# Plan: shdft-tui-merge

Ziel: Inhalt aus `tui-defaults` (Komplettstack Shell + WezTerm/Herdr + Claude/Pi) in privates `thelad-dev/shdft` mergen. Bedienkonzepte bleiben identisch; Linux (nativ) und Windows/WSL sind gleichwertig first-class. Alle erkennbaren Arbeitgeber- und Firmenbezüge raus. Neue Commits nur mit der noreply-Adresse des GitHub-Kontos; die History der Quelle nicht importieren.

## Annahme

- Quelle ist der Stand unter `/tmp/tui-defaults-work` (Klon von `tui-defaults` main), Inhalt wird kopiert und angepasst, nicht die Git-History übernommen.
- Bestehendes `setup-shell-defaults.sh` bleibt Einstieg für Shell-Standards allein; Profile-Installer ergänzen den Stack und nutzen dieselbe Block-Marker-Idee (`# BEGIN shdft` … `# END shdft`, plus `# BEGIN shdft-profile` … `# END shdft-profile`).
- Claude/Pi `settings.json` bleiben Whitelist-Keys wie im tui-defaults-Plan: Claude `theme`, `statusLine`, `language`, `editorMode`, `inputNeededNotifEnabled`, `skipDangerousModePermissionPrompt`; Pi `httpIdleTimeoutMs`, `modelThinkingLevels`. Keine `permissions`/`hooks`, keine Tokens/`auth.json`.
- `models.json` mit Platzhalter `apiKey: "strata-local"` (lokaler Strata auf 127.0.0.1) wird übernommen.
- Shared Agent-Configs (Herdr, Claude, Pi, AGENTS.md) sind plattformgleich; nur Installer-Pfade, WezTerm-Start und WSL/Windows-Helfer unterscheiden sich.
- Git-Author im Zielrepo bleibt `thelad-dev` mit der noreply-Adresse dieses Kontos, nie eine Firmen-Mailadresse.
- Nachweis läuft ohne Schreiben ins echte Home: Temp-HOME und `--dry-run`/`-WhatIf`.

## Zwei Wege

**(a) Auftragsweg: `profiles/linux/` + `profiles/windows-wsl/`, gemeinsames `shell/`, gemeinsames `home/` für Agent-Configs; bestehende Installer aus tui-defaults als Profile-Installer umbiegen; Root-README mit gleichwertigem Schnellstart.**

- Bedienung bleibt: ein Install-Befehl pro Umgebung, gleiche Symlink-/Merge-/Block-Semantik.
- Linux und Windows/WSL sind strukturell gleichwertig sichtbar.
- Umbenennung der Firmenbezüge und Pfadanpassung sind lokal und prüfbar.

**(b) Flat-Kopie von tui-defaults ins Repo-Root (install.sh/ps1 wie bisher), Linux nur als README-Abschnitt ohne eigenes Profil.**

- Weniger Dateien, aber Linux bleibt Second-Class (Widerspruch zum Grill-me).
- Root-Skripte kollidieren begrifflich mit dem bestehenden Shell-Only-Einstieg.

**Wahl: (a).** (b) verletzt die Gleichwertigkeit. Gelassen wird (b).

## Ablehnung

Ein erfahrener Kollege würde ablehnen:

- URLs, Notebook-Text, Mailadressen oder Hostnamen einer Firma, oder ein Klarname als Beispielname im Repo;
- Import der tui-defaults-Git-History (Author der Quelle);
- `permissions`/`hooks`/Tokens/`auth.json` in committed settings;
- Setup, das bestehende Dateien ohne Backup überschreibt oder Blöcke doppelt einfügt;
- sudo/Admin still im Hauptskript;
- Linux-Profil, das nur ein Alias der WSL-Skripte ist (win-browser, `.wslconfig` ohne Ersatzpfad);
- README nur auf Windows zugeschnitten.

## Nachweis

- Suche nach Arbeitgeber, Firma, Klarname, privaten Mailadressen und internen Hostnamen ohne Treffer. Der Suchausdruck steht nicht in diesem Plan, damit er die entfernten Werte nicht wieder abschreibt.
- `shellcheck setup-shell-defaults.sh profiles/linux/install.sh profiles/linux/install-sudo.sh profiles/windows-wsl/install.sh profiles/windows-wsl/install-sudo.sh home/.claude/statusline.sh profiles/windows-wsl/home/.local/bin/win-browser` ohne Befund.
- `HOME=$(mktemp -d) profiles/linux/install.sh --dry-run` und zweimal echter Lauf gegen Temp-HOME: zweiter Lauf meldet `unverändert`.
- `HOME=$(mktemp -d) profiles/windows-wsl/install.sh --dry-run` (ohne WSL: WezTerm-Link ggf. übersprungen).
- `jq` prüft, dass committed Claude/Pi settings keine Keys `permissions` oder `hooks` enthalten.
- Push Branch `fm/shdft-tui-merge-20261012`, PR auf `thelad-dev/shdft` (nicht draft, nicht mergen).

## Grenze

- Kein Anfassen von Firstmate-Home, dem echten Home, dem Remote der Quelle, sudo/Admin-Ausführung.
- Keine Herdr-Lifecycle-Steuerung.
- Kein Merge des PRs; kein Push auf `main`.
- Inhalt von AGENTS.md bleibt fachlich erhalten, nur Firmen-Formulierungen werden neutralisiert.
