# Handwerk vor dem Diff: Regeln nachziehen

## Annahme

- Die drei Regeln vom 2026-10-14 stehen derzeit nicht in `~/.agents/AGENTS.md` (die Datei ist wieder eine normale Kopie ohne diese Abschnitte), aber ihr Wortlaut ist in der Sitzung dokumentiert, die sie eingetragen hat, und parallel in der damaligen Notiz dazu.
- "Lokale Fassung" meint diesen eingetragenen AGENTS-Wortlaut, nicht die kürzeren Präferenz-Zeilen und nicht eine freie Umschreibung.
- Symlink auf den Primary-Checkout ist erst sinnvoll, wenn dort derselbe Stand liegt; dieser Worktree ist wegwerfbar.

## Zwei Wege

1. Auftragsweg: genau die drei lokalen AGENTS-Formulierungen in `home/.agents/AGENTS.md` nachtragen, sonst nichts.
2. Alternativ (nicht Auftrag): die kürzeren Präferenz-Bullets 1:1 als Stichpunkte anhängen.

Ich nehme Weg 1, weil der Auftrag "wortgleich zur lokalen Fassung" verlangt und die lokale AGENTS-Fassung Abschnitte/Sätze war, keine kurzen Präferenz-Bullets. Weg 2 lasse ich, weil er den AGENTS-Stil und den dokumentierten Wortlaut verwässern würde.

## Ablehnung

- Em-Dashes oder andere stilfremde Zeichen in neuem Text (verstößt gegen die erste globale Regel).
- Zusätzliche Aufräumarbeiten am GitHub-Kommentarstil oder an den bestehenden Lavish-/Tailscale-Zeilen.
- Symlink setzen, obwohl Primary und lokale Datei nicht denselben Inhalt haben.
- Auftraggeber-/Rollenworte in Commit-Text.

## Nachweis

```bash
rg -n 'Dasselbe gilt für jeden Bericht|## Identität nach außen|Werte aus Datenfeldern werden immer so ausgeschrieben' home/.agents/AGENTS.md
git diff --stat
git diff home/.agents/AGENTS.md
# nur Zuwachs der drei Regeln; keine anderen Dateien außer diesem Plan
```

Symlink nur, wenn `cmp` zwischen Ziel und `~/.agents/AGENTS.md` greift; sonst bewusst nicht setzen.

## Grenze

- Nur `home/.agents/AGENTS.md` (plus dieser Plan).
- Keine anderen Docs, keine Installer, kein Push, kein Merge.
- `~/.agents/AGENTS.md` nur anfassen, um den freigegebenen Symlink zu setzen, und nur bei Inhaltsgleichheit.
