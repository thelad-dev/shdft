# Plan: font-systemschrift

Ziel: `profiles/linux/install-font.sh` legt keine eigene Kopie von Hack Nerd Font nach `~/.local/share/fonts`, wenn Fontconfig die Familie schon aus einer anderen Quelle kennt (etwa Paket `ttf-hack-nerd` unter `/usr/share/fonts`). Ohne vorhandene Schrift installiert es wie bisher. Nebenbei: `profiles/linux/install.sh` rückt mit Leerzeichen statt Tabs ein.

## Annahme

- "Systemweit vorhanden" heißt: `fc-list` findet für die Familie `Hack Nerd Font` alle vier Schnitte Regular, Bold, Italic und Bold Italic in Dateien außerhalb von `~/.local/share/fonts`. Version und Prüfsumme der fremden Dateien sind egal; das Paket ist dann die Quelle.
- Fehlt mindestens ein Schnitt außerhalb, gilt die Schrift als nicht vorhanden und das Skript verhält sich wie bisher (alle fehlenden Schnitte ins Benutzerverzeichnis). Gemischte Quellen je Schnitt werden nicht gebaut.
- Fehlt `fc-list`, gilt die Schrift als nicht vorhanden; der bisherige Ablauf prüft danach `fc-cache` wie gehabt.
- Die Varianten `Hack Nerd Font Mono` und `Hack Nerd Font Propo` zählen nicht, weil WezTerm `Hack Nerd Font` anfordert.

## Zwei Wege

**(a) Abfrage je Schnitt über Fontconfig-Muster:** `fc-list "Hack Nerd Font:style=<Stil>" file`, Treffer unter `~/.local/share/fonts/` verwerfen. Erkennt die Schrift unabhängig vom Dateinamen und Paketformat.

**(b) Dateinamen suchen** (`HackNerdFont-*.ttf` unter `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts`). Hängt am Dateinamen und an einer festen Verzeichnisliste, die je Distribution abweicht.

**Wahl: (a).** Fontconfig ist genau die Instanz, die WezTerm nutzt; was sie listet, sieht auch WezTerm. Gelassen wird (b).

Zusätzlich: Liegt bei vorhandener Systemschrift trotzdem eine eigene Kopie unter `~/.local/share/fonts`, nennt das Skript sie und den Befehl zum Entfernen, löscht aber nichts.

## Ablehnung

Ein erfahrener Kollege würde ablehnen:

- `fc-match` statt `fc-list`, weil `fc-match` immer eine Ersatzschrift liefert und so Vorhandensein vortäuscht;
- stilles Löschen einer vorhandenen Benutzerkopie;
- Neuformatierung von `install.sh` über die Einrückung hinaus oder Tabs in anderen Dateien im selben Diff;
- Änderungen am Download-, Prüfsummen- oder Installationspfad, die nicht nötig sind.

## Nachweis

- `shellcheck profiles/linux/install-font.sh profiles/linux/install.sh` ohne Befund.
- `grep -c $'\t' profiles/linux/install.sh` ergibt 0; `git diff -w` zeigt für `install.sh` keine inhaltliche Änderung.
- Mit Wegwerf-`HOME` und eigener `FONTCONFIG_FILE`, die ein "System"-Verzeichnis mit den vier Schnitten einbindet: `install-font.sh` und `--dry-run` melden "vorhanden" mit Pfad, Exit 0, `~/.local/share/fonts` bleibt leer.
- Mit Wegwerf-`HOME` und Fontconfig ohne Hack Nerd Font: `--dry-run` meldet viermal "würde", echter Lauf meldet viermal "installiert"; zweiter Lauf "unverändert".
- Variante mit Systemschrift plus eigener Kopie zeigt den Hinweis auf die Benutzerkopie.

## Grenze

- Nur `profiles/linux/install-font.sh`, Einrückung in `profiles/linux/install.sh`, der passende Satz im README.
- Kein Ausrollen auf elitedesk, ws88 oder andere Rechner; nichts im echten `~/.local/share/fonts` dieses Rechners.
- Windows-Skripte (`install-font.ps1`) und Tabs in anderen Dateien bleiben unberührt.
