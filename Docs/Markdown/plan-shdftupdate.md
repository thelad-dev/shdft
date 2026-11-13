# Handwerk vor dem Diff: /shdftupdate

Ziel: Ein Claude-Code-Skill `/shdftupdate` plus ein bash-Skript ziehen die shdft-Einstellungen auf jedem Rechner nach, ohne je Lokales zu überschreiben, und schlagen für lokale Abweichungen einen PR vor (ohne ihn zu öffnen).

## Annahme

- Das Repo ist öffentlich. Alles, was in einen Vorschlag wandert, muss vorher durch die Sicherheitsprüfung.
- "Verwaltete Datei" heißt: alles, was die Installer ausrollen. Das sind die Dateien unter `home/` (Symlink oder Schlüssel-Mischung), die Shell-Blöcke und je Profil die Profil-Dateien.
  Die Windows-Seite (`profiles/windows-wsl/windows/`, `.wslconfig`, `install.ps1`) liegt auf Windows-Pfaden und ist bash-seitig nicht sauber prüfbar. Sie bleibt draußen, die Ausgabe nennt das in einer Zeile.
- Auf den Rechnern des Captains zeigen die Symlinks aus `$HOME` in den Arbeitsbaum des lokalen shdft-Klons. Eine lokale Änderung an einer verlinkten Datei sieht darum aus wie eine nicht committete Änderung im Klon (`git status`), nicht wie eine abweichende Kopie.
- Es gibt keine Basis-Hashes vom letzten Ausrollen, und die Installer schreiben keine. Ob eine abweichende Datei "Repo neuer" oder "lokal geändert" ist, entscheidet die Git-Historie: Stimmt der Inhalt mit irgendeinem früheren Stand dieser Datei im Repo überein, ist er nur veraltet.
  Sonst ist er lokal geändert.
- Es gibt weder `shellcheck` noch `bats` auf dem Rechner. Tests sind reine bash-Tests, `shellcheck` kommt für den Nachweis aus einer Wegwerf-venv (`shellcheck-py`).
- Die globale Git-Identität dieser Rechner ist die Firmenadresse. Sie darf nie in einen Commit. Die Identität kommt aus der Repo-Konfiguration (`git config --local`) oder, falls dort nichts steht, vom letzten Commit auf `origin/main`, sofern dessen Adresse auf `@users.noreply.github.com` endet. Sonst legt das Skript keinen Commit an und gibt die Befehle aus.

## Zwei Wege

1. Auftragsweg: Skript im Repo, das die Deploy-Logik der Installer für den Abgleich nachbaut.
2. Anderer Weg: Das Skript ruft `install.sh` des Profils auf, wenn nichts abweicht, und meldet sonst nur.

Ich nehme Weg 1. `install.sh` überschreibt abweichende Dateien nach einem Backup und ruft `install-font.sh` auf (Netzwerk, Schrift laden). Das ist genau das, was `/shdftupdate` nicht tun darf.
Weg 2 lasse ich. Zwei Quellen für "was ist verwaltet" gibt es trotzdem nicht: Ein Drift-Test liest `LINKS` und `MERGES` aus beiden `install.sh` und vergleicht sie mit `git ls-files home/` und der Liste im Skript. Läuft ein Installer anders als das Skript, wird der Test rot.

Weitere Entscheidungen:

- Diff-Basis ist `HEAD` des lokalen Klons nach dem Fast-Forward. Verglichen wird der Inhalt, den `$HOME` tatsächlich liefert (bei Symlink also der Arbeitsbaum), mit dem Blob in `HEAD`.
- Ein Vorschlag entsteht nur, wenn `HEAD == origin/main` gilt (Klon sauber aktuell). Divergenz, Vorsprung, anderer Zweig, Offline: kein Vorschlag, dafür der Grund. Das verhindert PRs, die auf einer anderen Basis gebaut sind, als die Abweichungen gemessen wurden.
- Eine Datei mit Sicherheitsfund fällt allein aus dem Vorschlag, die anderen laufen weiter. Die Meldung nennt Datei, Zeile, Art und einen maskierten Auszug.
- Skript-Übergabe an Gegenstellen per `ssh host 'bash -s -- ...' < skript`. So läuft auch beim ersten Mal die neue Fassung, bevor der Klon der Gegenstelle sie hat.

## Zu bauen

Dateien:

- `profiles/shared/shdftupdate.sh` (bash, ausführbar, `set -euo pipefail`, deutsche Meldungen, ganzer Ablauf in `main`, am Ende `main "$@"; exit $?`).
- `home/.claude/skills/shdftupdate/SKILL.md` (Skill, ruft das Skript).
- `home/.claude/skills/shdftupdate/SKILL.md` zusätzlich in `LINKS` beider `install.sh` (Linux und WSL) eintragen, damit er wie die übrigen `home`-Dateien verteilt wird.
- `tests/shdftupdate.test.sh` (reine bash-Tests, temporäre Repos) und `tests/run.sh` (führt Tests und, falls vorhanden, `shellcheck` aus).
- README: Abschnitt `/shdftupdate` (Inhaltsverzeichnis, Tabelle "Was drin ist", "Ändern und aktualisieren" nachziehen).

Aufruf: `shdftupdate.sh [--dry-run] [--no-propose] [--local] [-v] [--repo PFAD]`; `-h`.
Umgebung: `SHDFT_REPO`, `SHDFT_PROFILE` (`linux` oder `windows-wsl`, sonst WSL-Erkennung über `/proc/version` und `WSL_DISTRO_NAME`), `SHDFT_CONFIG_DIR` (Standard `~/.config/shdft`), `SHDFT_STATE_DIR` (Standard `~/.local/state/shdft`).
Exit 0: alles aktuell oder sicher nachgezogen. Exit 1: etwas zu melden (Abweichung, Divergenz, Offline, Rechner nicht erreichbar, Sicherheitsfund). Exit 2: Aufruf- oder Umgebungsfehler.

Repo finden (erste Treffer gewinnt, jeweils mit Prüfung "Git-Arbeitsbaum mit `home/`"): `--repo`, `SHDFT_REPO`, Ort des Skripts (zwei Ebenen höher, wenn es aus einer Datei läuft), Auflösung des Symlinks `~/.claude/CLAUDE.md` nach `<repo>/home/.claude/CLAUDE.md`, dann `~/shdft`, `~/workspaces/shdft`. Ohne Treffer: "kein shdft-Repo auf diesem Rechner", Exit 0 (wichtig für die Gegenstellen-Läufe).

Schritt 1, Repo:

- `GIT_TERMINAL_PROMPT=0 git fetch origin`. Offline oder Fehler: melden, weiter mit dem lokalen Stand.
- Stand vor und nach dem Fetch von `origin/main` merken. War der alte Stand kein Vorfahre des neuen, ist `origin/main` umgeschrieben: melden, nichts erzwingen.
- Auf `main` und `HEAD` Vorfahre von `origin/main`: `git merge --ff-only origin/main`. Lehnt Git ab (lokale Änderungen im Weg), die Meldung nennen, nichts anfassen.
- `HEAD` voraus: melden ("N Commits nicht gepusht"). Divergiert: melden mit den Zahlen beider Seiten. Anderer Zweig oder losgelöster `HEAD`: melden, kein Fast-Forward.
- Geänderte Dateien im Arbeitsbaum des Klons werden aufgelistet (`git status --porcelain` für getrackte Pfade), nie angefasst. Nie `stash`, nie `reset`, nie `checkout --`.

Schritt 2, Dateien. Verwaltete Pfade je Rechner:

| Klasse | Quelle im Repo | Ziel |
|---|---|---|
| link | jede getrackte Datei unter `home/` außer den merge-Dateien, dazu `profiles/linux/wezterm.lua` (Linux) bzw. `profiles/windows-wsl/home/.local/bin/win-browser` (WSL) | `$HOME/<Pfad>`, Linux-WezTerm nach `~/.config/wezterm/wezterm.lua` |
| merge | `home/.claude/settings.json`, `home/.pi/agent/settings.json` | gleiche Pfade unter `$HOME` |
| block | `shell/bashrc-shdft.sh`, Profil `shell/bashrc-profile.sh`, `profile-profile.sh` | `~/.bashrc` Block `shdft`, `~/.bashrc` Block `shdft-profile`, `~/.profile` Block `shdft-profile` |
| template (nur WSL) | `profiles/windows-wsl/home/.local/share/applications/win-browser.desktop.in` mit `@HOME@` durch `$HOME` ersetzt | `~/.local/share/applications/win-browser.desktop` |

Der Link `~/.pi/agent/AGENTS.md` auf `~/.agents/AGENTS.md` ist ein reiner Installer-Link ohne Repo-Quelle und gehört nicht dazu.

Zustand je Datei (Vergleich immer gegen `HEAD`, Inhalt "wie `$HOME` ihn liefert", Symlinks werden gelesen, nicht verglichen):

- gleich: Inhalt stimmt mit `HEAD` überein. Ob ein Link auf einen anderen Klon zeigt, nur als Hinweis.
- Repo neuer: Datei fehlt nicht, ist ungleich, stimmt aber mit einem früheren Repo-Stand überein (`git rev-list HEAD -- <pfad>`, jeder Blob, bei template und block nach demselben Rendern). Aktion: nachziehen.
- lokal anders: stimmt mit keinem Repo-Stand überein. Nie überschreiben. Meldung: Datei, Art, Diff-Zusammenfassung (Zeilen plus/minus, bei merge die betroffenen Schlüsselpfade; `-v` den gekürzten Unified-Diff). Liegt die Datei in den Änderungen, die dieser Lauf per Fast-Forward geholt hat, steht dabei "Repo hat sich ebenfalls geändert".
- fehlt: Ziel fehlt (kaputter Symlink zählt als fehlend, bei block fehlt der Block, bei merge fehlt die Datei). Aktion: neu anlegen, aber nur, wenn überhaupt irgendeine verwaltete Datei auf dem Rechner liegt. Sonst: ein Satz "shdft ist hier nicht eingerichtet, `profiles/<profil>/install.sh` ausführen", keine Einrichtung.

merge im Detail: Blätter sind die nicht-Objekt-Werte der Repo-Datei (Arrays zählen als ein Blatt, wie bei `jq '.[0] * .[1]'`). Je Blatt: Pfad fehlt lokal, Wert gleich, Wert stimmt mit einem früheren Repo-Wert desselben Pfades überein, oder lokal anders. Ein lokal anderes Blatt macht die Datei "lokal anders" und wird nie überschrieben. Schlüssel, die nur lokal existieren (Hooks, Permissions, Plugins), sind nie Abweichung und nie Teil eines Vorschlags. Nachziehen ist `jq -s '.[0] * .[1]' lokal repo`, nur wenn kein Blatt lokal anders ist. Ist die lokale Datei kein gültiges JSON: melden, nie anfassen.

Nachziehen schreibt mit Sicherung nach `~/.shdft-backup/<Zeitstempel>/<Pfad>`, wie die Installer es tun; Symlink-Ziel ist der Pfad im Klon. Ein Ziel, das ein Symlink auf einen anderen Klon ist, wird nur gemeldet, nie umgelegt. Block ersetzen wie `install.sh` (awk-Block mit den Markierungen `# BEGIN <name>` und `# END <name>`).

Schritt 3, Vorschlag (nicht bei `--no-propose`, nicht bei `--dry-run` über das Prüfen hinaus):

1. Je abweichender Datei den Inhalt in Repo-Form berechnen: link = lokaler Inhalt; merge = Repo-JSON, in dem jedes lokal andere Blatt durch den lokalen Wert ersetzt ist (neue lokale Schlüssel bleiben draußen); block = lokaler Blockinhalt; template = lokaler Inhalt mit `$HOME` zu `@HOME@` zurückgetauscht.
2. Sicherheitsprüfung nur auf die neu hinzugekommenen Zeilen gegenüber dem Blob in `HEAD` (`diff` mit `--new-line-format='%dn:%L'` o. Ä.). Muster, Groß-/Kleinschreibung egal wo sinnvoll:
   - Tokens: `gh[pousr]_`, `github_pat_`, `sk-` mit langer Folge, `xox[baprs]-`, `AKIA[0-9A-Z]{16}`, `AIza...`, JWT-Form `eyJ...\.eyJ`, `Bearer` mit langer Folge.
   - Schlüssel: `-----BEGIN ... PRIVATE KEY-----`, `ssh-rsa AAAA`, `ssh-ed25519 AAAA`.
   - Kennwörter: `password|passwd|secret|token|api[_-]?key` gefolgt von `:` oder `=` und einem nicht leeren Wert. Platzhalter sind erlaubt: Wert beginnt mit `$`, `<`, `@`, oder ist `strata-local`.
   - Private IPs: `10.x.x.x`, `192.168.x.x`, `172.16-31.x.x`, `100.64-127.x.x`. `127.0.0.1` ist erlaubt.
   - Mailadressen, außer `*@users.noreply.github.com` und `noreply@*`.
   - Feste Benutzerpfade: `/home/<name>`, `/Users/<name>`, `/mnt/c/Users/<name>`, `C:\Users\<name>`. Platzhalter in `<...>` zählen nicht.
   - Verbindungszeichenfolgen: `scheme://nutzer:kennwort@`, `postgres(ql)://`, `mysql://`, `mongodb(+srv)://`, `redis://`, `amqp://`, `jdbc:`, `Password=`.
3. Gibt es saubere Dateien: eigener Arbeitsbaum per `git worktree add -b shdftupdate/<host>-<Zeitstempel> <SHDFT_STATE_DIR>/proposals/<name> origin/main`. Dateien hineinkopieren, `git add`, committen mit der Identität aus der Voraussetzung (`-c user.name`, `-c user.email`, kein Co-Autor-Trailer). Meldungsform wie im Repo üblich, deutsch, kurz: `Lokale Änderungen von <host> übernehmen: <Dateien>.`
   Gibt es schon einen `shdftupdate/<host>-*`-Zweig mit gleichem Baum auf gleicher Basis, wird der neue verworfen (nur der eben angelegte) und der alte genannt.
   Ohne passende Identität: Arbeitsbaum und Dateien vorbereiten, aber nicht committen, und die Befehle zum Committen ausgeben.
4. Ausgabe: Zweig, Arbeitsbaum, Dateiliste, dazu die Befehle `git -C <klon> push -u origin <zweig>` und `gh pr create ...` als Text. Ausgeführt wird nichts davon.
5. Nach dem Merge eines solchen PRs kann der Klon (bei verlinkten Dateien) nicht per Fast-Forward nachziehen, solange die lokale Änderung noch im Arbeitsbaum liegt. Der Lauf meldet das als "Fast-Forward nicht möglich" mit der Datei, und der Hinweis nennt `git -C <klon> restore <datei>` als Handgriff des Nutzers, den das Skript nie selbst tut.

Schritt 4, mehrere Rechner: Liste `$SHDFT_CONFIG_DIR/hosts`, ein ssh-Alias je Zeile, Leerzeilen und `#`-Kommentare erlaubt. Ohne Liste nur lokal. Je Alias: `ssh -o BatchMode=yes -o ConnectTimeout=10 <alias> 'bash -s -- --local <weitergereichte Optionen>' < <skript>`. Die Gegenstelle hat das Repo nicht: Meldung "kein shdft-Repo auf diesem Rechner" (Exit 0). ssh scheitert: "nicht erreichbar", zählt als Meldung (Exit 1).
`--local` unterdrückt die Hosts-Liste (damit die Gegenstelle nicht rekursiv fragt).

Schritt 5, Ausgabe je Rechner (deutsch, kurz):

```
== <Rechner> (<Profil>) ==
Repo:       <Pfad>, main, aktuell | aktualisiert a1b2c3d..e4f5a6b (N Commits) | <Meldung>
Dateien:    N gleich, N nachgezogen, N neu angelegt, N abweichend
nachgezogen: <Datei> (Repo neuer)
abweichend:  <Datei> - lokal anders: <Zusammenfassung>
Vorschlag:   <Zweig> in <Arbeitsbaum> | nicht vorgeschlagen: <Grund>
Ergebnis:    aktuell | nachgezogen | Abweichungen gemeldet
```

Skill `SKILL.md` (deutsch, `user-invocable: true`, kurzer Frontmatter wie bei `updatefirstmate`): ruft das Skript, gibt die Ausgabe in Klartext wieder, weist darauf hin, dass der Skill nie pusht und nie einen PR öffnet. Er öffnet erst auf ausdrückliches Wort des Nutzers: Push, `gh pr create` aus den ausgegebenen Befehlen. Er fasst Abweichungen für den Menschen zusammen und erfindet keine Befehle. Er sagt, dass das Nachziehen von Skills und `CLAUDE.md` erst in einer neuen Claude-Sitzung wirkt.
Pfad des Skripts im Skill: über den Symlink aufgelöst (`readlink -f ~/.claude/skills/shdftupdate/SKILL.md`, vier Ebenen hoch, dann `profiles/shared/shdftupdate.sh`).

README: Abschnitt `## /shdftupdate` mit Aufruf, Zuständen, Hosts-Liste, Vorschlag und Sicherheitsprüfung, Grenzen (Windows-Seite, Basis ohne Hashes über die Historie). Die Tabelle "Ändern und aktualisieren" bekommt eine Zeile.

## Ablehnung

Was ein erfahrener Kollege ablehnen würde:

- Ein Nachziehen, das lokale Dateien ersetzt, auch mit Sicherung.
- `git stash`, `reset --hard`, `checkout --`, `push --force` oder `-f` an irgendeiner Stelle.
- Ein Skript, das pusht oder `gh pr create` ausführt.
- Die Firmenadresse (oder irgendeine Nicht-Noreply-Adresse) im Commit, ein Co-Autor-Trailer.
- Eine zweite, abweichende Liste verwalteter Dateien, die still von den Installern wegdriftet (Drift-Test deckt das ab).
- Eine Sicherheitsprüfung, die über das ganze Repo statt über die eigenen Zeilen scannt und deshalb ständig Alarm schlägt, oder umgekehrt Treffer ohne Meldung verschluckt.
- Banner, Farbausgabe, Konfigurationsframework: unnötige Maschinerie für einen seltenen Ablauf.
- Ausgabe, die ein geheimes Muster im Klartext zeigt.

## Nachweis

- `tests/run.sh` grün. Die Tests legen temporäre Repos an (ein bare Origin, ein Klon, ein Arbeits-`HOME`), ohne Netzwerk und ohne das echte `$HOME`:
  1. gleich: Link auf Klon und Block und Merge stimmen, Ergebnis "aktuell", Exit 0.
  2. Repo neuer (Kopie mit altem Stand, veralteter Block, veraltete Merge-Schlüssel): nachgezogen mit Sicherung.
  3. lokal anders (Kopie, Block, Merge-Wert, Link-Datei mit Arbeitsbaum-Änderung): nie überschrieben, Meldung, Exit 1, Vorschlag mit Commit.
  4. lokal fehlt: neu angelegt, aber nicht auf einem Rechner ohne jede verwaltete Datei.
  5. Divergenz und umgeschriebenes `origin/main`: gemeldet, nichts verändert (Hash von HEAD und Arbeitsbaum vorher/nachher gleich).
  6. Sicherheitsfund: je Muster ein Fall (Token, Schlüssel, Kennwort, private IP, Mailadresse, `/home/<name>`, Verbindungszeichenfolge); Datei fällt aus dem Vorschlag, Fund wird genannt, Klartext steht nicht in der Ausgabe.
  7. Hosts-Liste mit ssh-Attrappe im `PATH`: Lauf je Alias, Gegenstelle ohne Repo, Gegenstelle nicht erreichbar.
  8. Identität: kein Noreply, kein Commit; Noreply, Commit ohne Co-Autor.
  9. Kein Push: Der Origin steht danach unverändert, es gibt keinen Remote-Zweig `shdftupdate/*`.
  10. Drift: `LINKS` und `MERGES` beider `install.sh` gleich dem Skript und `git ls-files home/`.
- `shellcheck` über `profiles/shared/shdftupdate.sh`, `tests/*.sh` ohne Meldung (Wegwerf-venv mit `shellcheck-py`).
- Trockenlauf gegen Kopien von `~/shdft` und `~/.claude` (Skript mit `HOME`, `SHDFT_REPO` auf Kopien), Ausgabe im Bericht, danach unverändertes Original (Hash-Vergleich).
- Frische Prüfsitzung mit Diff und Ziel: was fehlt, was ist falsch, was ist unnötig.

## Grenze

- Nur im Worktree: `profiles/shared/shdftupdate.sh`, `home/.claude/skills/shdftupdate/SKILL.md`, die zwei `install.sh` (je eine Zeile in `LINKS`), `tests/`, `README.md`, dieser Plan.
- Keine Änderung an `~/shdft` (die drei dort geänderten Dateien des Captains und der ungetrackte Plan bleiben), `~/.claude` und anderen echten Pfaden. Der Trockenlauf läuft auf Kopien unter `/home/ladwein/sl-agent-workspace/data/shdftupdate-1313/`.
- Kein Push, kein PR, kein Merge. Kein CHANGELOG.
- Keine Installer-Logik umbauen, keine Änderung am Verhalten von `install.sh` über die eine Zeile in `LINKS` hinaus.
- Windows-Dateien und `install.ps1` bleiben unberührt.
