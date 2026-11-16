# Handwerk vor dem Diff: Board-Link findet sein Zuhause

Ziel: Die Statuszeile zeigt rechts das letzte offene bearings-Board, ohne dass `FM_HOME` gesetzt ist und ohne rechnerspezifischen Standardpfad. Eine verwaiste Sperre blockiert die Anzeige nicht mehr.

## Annahme

- Claude übergibt der Statuszeile JSON auf stdin; das Arbeitsverzeichnis steht in `workspace.project_dir`, `workspace.current_dir` oder `cwd`.
- Das bearings-Board liegt in `<Zuhause>/.lavish/bearings-board.html`, und `lavish-axi` listet seine offene Sitzung mit diesem Dateipfad.
- Der Hintergrundlauf kann abbrechen (Kill, Timeout), ohne seine Aufräumzeile zu erreichen.

## Zwei Wege

1. Auftragsweg: Zuhause aus einer Konfigdatei mit einer Verzeichnisliste lesen.
2. Anderer Weg: Zuhause aus dem Arbeitsverzeichnis aufwärts suchen, sonst aus der Liste der offenen Lavish-Sitzungen lesen.

Ich nehme Weg 2. Er braucht keine Konfiguration pro Rechner: `FM_HOME` hat Vorrang, dann das erste Verzeichnis ab dem Arbeitsverzeichnis aufwärts mit einem Board, dann das Board einer offenen Lavish-Sitzung. Die Sitzungsliste kennt den Pfad ohnehin, eine zweite Liste von Hand würde nur veralten.
Die Konfigdatei lasse ich: sie wäre pro Rechner zu pflegen und löst nichts, was Weg 2 nicht löst.

Sperre: Eine Sperre, die älter als eine Minute ist, wird ersetzt. Der Hintergrundlauf räumt die Sperre über `trap ... EXIT` auf, auch wenn `fm-board-link` fehlt. Ohne Board wird die Anzeige geleert statt alt stehen zu lassen.

## Ablehnung

- Mehrere Rechner mit mehreren offenen Boards: gewählt wird das Board der Sitzung, in der die Statuszeile läuft, sonst das erste offene. Das reicht für "letztes offenes Board" nicht streng, ist aber der heutige Stand.
- Pfade mit Leerzeichen oder Komma werden aus der Sitzungsliste nicht gefunden. Das Arbeitsverzeichnis deckt sie ab.

## Nachweis

`bash tests/run.sh` und `bash tests/board-link.test.sh`: Zuhause ohne `FM_HOME` gefunden (Arbeitsverzeichnis, Sitzungsliste), `FM_HOME` vorrangig, kein Board gibt leere Anzeige ohne Fehler, verwaiste Sperre ersetzt (auch bei fehlendem `fm-board-link`), frische Sperre bleibt.

## Grenze

Nur `home/.local/bin/fm-board-link`, die Sperre und die Pfadübergabe in `home/.claude/statusline.sh`, der neue Test und die Testliste in `tests/run.sh`. Nichts an der übrigen Statuszeile oder an shdftupdate.
