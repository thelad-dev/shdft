# Handwerk vor dem Diff: Regeln einkippen 2026-10-17

## Annahme

- Die Quelle unter dem Task-Datenpfad (`AGENTS.md.neu` und `aenderung.patch`) ist der freigegebene Stand und besser als der Repo-Inhalt: DeepAPI nur auf Ansage, Lavish-Links ueber LAN-Adresse ohne harte IP, zusaetzlicher Absatz zu Klarnamen und internen Angaben.
- Der Patch passt auf den aktuellen `home/.agents/AGENTS.md` im Worktree (Basisindex wie im Patch).
- Oeffentliches Repo: weder Plan noch Commit-/PR-Text enthalten interne Adressen, Rechnernamen oder Klarnamen.

## Zwei Wege

1. Auftragsweg: `aenderung.patch` bzw. den Inhalt von `AGENTS.md.neu` 1:1 auf `home/.agents/AGENTS.md` anwenden; sonst nichts am Regeltext.
2. Alternativ (nicht Auftrag): die drei Punkte frei umformulieren oder nur einen Teil uebernehmen.

Ich nehme Weg 1, weil der Auftrag den vorbereiteten Stand einkippen will und der Diff bereits geprueft ist. Weg 2 lasse ich, weil Umschreiben Drift und Review-Rauschen erzeugt.

## Ablehnung

- Harte LAN-IP oder Hostname im Regeltext oder in Commit/PR.
- Em-Dashes oder stilfremde Zeichen im neuen Text.
- Aenderungen an anderen Abschnitten (Handwerk, GitHub-Stil, Maintaining).
- Inhalt aus einer schmutzigen Hauptkopie statt aus dem Task-Datenpfad.

## Nachweis

```bash
diff -u home/.agents/AGENTS.md AGENTS.md.neu
rg -n 'DeepAPI wird nur|LAN-Adresse des Rechners|Klarname, Arbeitgeber' home/.agents/AGENTS.md
git diff --stat
# erwartet: nur home/.agents/AGENTS.md (+ dieser Plan); diff gegen AGENTS.md.neu leer
```

## Grenze

- Nur `home/.agents/AGENTS.md` und dieser Plan.
- Kein Symlink auf `~/.agents/AGENTS.md`, keine Installer, kein Merge, kein Default-Branch-Push.
