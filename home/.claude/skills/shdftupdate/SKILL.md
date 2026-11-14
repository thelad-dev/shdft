---
name: shdftupdate
description: >-
  Zieht die shdft-Einstellungen (Shell-, Terminal- und Agent-Standards) auf diesem Rechner und den Rechnern der Hosts-Liste nach,
  meldet lokale Abweichungen und bereitet dafür einen PR-Vorschlag vor.
  Nutzen, wenn der Nutzer /shdftupdate aufruft (z. B. "/shdftupdate", "shdft aktualisieren", "shdft-Einstellungen nachziehen").
user-invocable: true
---

# shdftupdate

Zieht den lokalen shdft-Klon per Fast-Forward auf `origin/main` und gleicht jede verwaltete Datei mit dem Repo ab.
Das Skript `profiles/shared/shdftupdate.sh` macht die ganze Mechanik; dieser Skill ruft es auf und gibt das Ergebnis für den Menschen wieder.

Der Skill pusht nie und öffnet nie einen PR.
Das Skript überschreibt nie etwas Lokales, benutzt weder `stash` noch `reset` und erzwingt nichts.

## Ablauf

1. **Skript finden und ausführen.**
   Der Skill liegt als Symlink im Klon; darüber findet man das Skript:
   ```sh
   skill_dir=$(dirname "$(readlink -f ~/.claude/skills/shdftupdate/SKILL.md)")
   "$skill_dir/../../../../profiles/shared/shdftupdate.sh"
   ```
   Liegt das Skript dort nicht (`SKILL.md` ist dann kein Symlink in den Klon), den Klon unter `~/shdft` oder `~/workspaces/shdft` nehmen (`profiles/shared/shdftupdate.sh`).
   Gibt es keinen Klon, sagen, dass shdft hier nicht eingerichtet ist (Schnellstart im README), und nichts erfinden.

   Optionen reichen nur durch, was der Nutzer verlangt hat:
   - `--dry-run` nur prüfen, nichts schreiben
   - `--no-propose` keinen Vorschlag vorbereiten
   - `-v` bei Abweichungen den gekürzten Diff zeigen
   - `--local` nur diesen Rechner (sonst fragt das Skript die ssh-Aliase aus `~/.config/shdft/hosts` mit ab)

2. **Ausgabe lesen.** Je Rechner steht dort:
   `Repo:` (aktuell, aktualisiert, Offline, divergiert, nicht gepusht, umgeschrieben, Fast-Forward nicht möglich),
   `Dateien:` (gleich, nachgezogen, neu angelegt, abweichend),
   `abweichend:` je Datei mit Art und Zusammenfassung,
   `Sicherheit:` Funde, die eine Datei aus dem Vorschlag nehmen (nie den Klartext wiederholen),
   `Vorschlag:` Zweig, Arbeitsbaum, Dateien und die Befehle zum Veröffentlichen,
   `Ergebnis:` aktuell, nachgezogen oder Abweichungen gemeldet.
   Exit 0 heißt alles aktuell oder sicher nachgezogen, Exit 1 heißt, es gibt etwas zu melden, Exit 2 ist ein Aufruf- oder Umgebungsfehler.

3. **Auf Deutsch in Klartext berichten**, je Rechner kurz:
   was nachgezogen oder neu angelegt wurde (eine frühere Fassung liegt unter `~/.shdft-backup/<Zeitstempel>/`),
   was lokal abweicht und warum es nie überschrieben wurde,
   welche Dateien wegen eines Sicherheitsfunds nicht im Vorschlag stehen,
   ob ein Vorschlag bereitliegt (Zweig `shdftupdate/<Zeitstempel>` und Arbeitsbaum) und was nicht gelang,
   und wenn das Skript Nachziehen und Anlegen ausgesetzt hat (Klon nicht auf `main`, voraus, divergiert, umgeschrieben, Fast-Forward blockiert), dass nur verglichen wurde und warum.
   Nichts hinzuerfinden: Befehle, Zweige und Pfade stammen aus der Ausgabe des Skripts.

4. **Hinweise weitergeben.**
   - Nachgezogene Skills und `CLAUDE.md` wirken erst in einer neuen Claude-Sitzung.
   - Meldet das Skript "Fast-Forward nicht möglich" mit einer Datei, liegt eine lokale Änderung im Klon im Weg (typisch nach dem Merge eines Vorschlags).
     Der Nutzer entscheidet dann selbst, ob er `git -C <klon> restore <datei>` ausführt; der Skill tut das nie.
   - Windows-Dateien (`.wslconfig`, WezTerm unter Windows, `install.ps1`) prüft das Skript nicht.

## Veröffentlichen nur auf ausdrückliches Wort

Das Skript legt höchstens einen Zweig mit Commit in einem eigenen Arbeitsbaum an und gibt die Befehle als Text aus (`git -C <klon> push -u origin <zweig>` und `gh pr create ...`).
Der Skill führt sie nur aus, wenn der Nutzer das ausdrücklich sagt, und dann genau die ausgegebenen Befehle, ohne `--force`.
Ohne dieses Wort bleibt es beim Bericht.
Das Repo ist öffentlich: den Vorschlag vor dem Push nicht um Dateien oder Zeilen erweitern, die das Skript nicht selbst vorbereitet hat.

## Sicherheit

- Lokal Abweichendes wird nie überschrieben, auch nicht mit Sicherung.
- Der Vorschlag ist ein Dreiwege-Merge aus lokaler Fassung, früherem Repo-Stand und heutigem `HEAD`; er enthält die lokale Änderung und den aktuellen Repo-Stand. Bei einem Merge-Konflikt wird die Datei nicht vorgeschlagen.
- Durch einen Symlink schreibt das Skript nie; ein Link in den Klon liest dessen Arbeitsbaum, der git gehört.
- Der Vorschlag prüft nur die neu hinzugekommenen Zeilen auf Tokens, Schlüssel, Kennwörter, private IP-Adressen, Mailadressen, feste Benutzerpfade und Verbindungszeichenfolgen; ein Treffer nimmt die Datei allein aus dem Vorschlag.
- Commits tragen nur eine Noreply-Identität (`@users.noreply.github.com`) und keinen Co-Autor: Repo-Konfiguration, `SHDFT_AUTHOR` oder ein Commit des Repo-Besitzers auf `origin/main`, nie ein fremder Autor oder die globale Git-Identität. Fehlt sie, bleibt es bei vorbereiteten Dateien und den Commit-Befehlen im Text.
