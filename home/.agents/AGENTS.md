# global agent instructions

- Never use the em dash "—" or the en dash "–". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions within the task, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, long term maintainability, and scalability where the task needs it.
  Choose the best solution for the task, not the cheapest; this never enlarges the task itself.
- For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  Apply the same high standard to engineering excellence: lint, test failures, and test flakiness.
- Never ignore such a problem, even if it is not caused by what you are working on: always report it.
  Fix it in a separate commit only if the fix takes less effort than the task itself; if it would double the effort or more, report it as its own task instead.
  Keep the task's own diff limited to the task, unless the problem blocks the task.
- Before using "dynamic workflows", "ultra code" or any harness feature that immediately spawns a large swarm of subagents, always explain the tradeoffs and ask the user for explicit approval.

## Handwerk vor dem Diff

Gilt für jeden Coding-Agenten in diesem Setup: Claude Code, Grok Build, Cursor CLI, Bob CLI, direkt oder als Firstmate-Crewmate in Herdr.
Firstmate schreibt keinen Projektcode. Es schreibt das Gate in den Brief und prüft, dass der Crewmate es befolgt hat.

Der Auftrag nennt Ziel, Grenzen und Nachweis. Er nennt nicht die Technik.
Steht im Auftrag eine konkrete Technik, ist sie ein Vorschlag, keine Vorgabe.
Eine bessere vorhandene Lösung im Repo oder eine einfachere Variante darf sie ersetzen. Dann kurz sagen, warum.

Ein Ein-Satz-Diff, eine Umbenennung oder ein offensichtlicher Tippfehler braucht das Gate nicht.
Alles andere schon: mehrere Dateien, neues Verhalten, unklare Ursache, fremdes Modul.

Vor dem ersten Edit, Commit oder PR steht dieser Block. Ohne ihn keine Änderung:

- Annahme: was ich voraussetze, obwohl es nicht im Auftrag stand
- Zwei Wege: einer davon stammt nicht aus dem Auftrag. Welchen ich nehme, welchen ich lasse, warum
- Ablehnung: was ein erfahrener Kollege am Ergebnis ablehnen würde
- Nachweis: welcher Befehl oder Test zeigt, dass es stimmt
- Grenze: welche Dateien und welches Verhalten ich nicht anfasse

Danach den Block als Docs/Markdown/plan-<kurze-aufgabe>.md speichern.
Umsetzen in einer neuen Session, nur mit dieser Datei und dem Ziel. Nicht im selben Verlauf weiterbauen.

Fertig heißt: der Nachweis ist gelaufen und grün, oder er konnte nicht laufen und das ist gesagt.
Ein Modell bewertet nicht, was ein Test, der Compiler oder der Linter prüfen kann.

Prüfung danach in einer frischen Session, nur mit Diff und Ziel: was fehlt, was ist falsch, was ist unnötig.
Der Lauf, der den Diff geschrieben hat, prüft ihn nicht.
Ausnahme für lokale Modelle (z. B. Strata unter Pi): Der Gate-Block bleibt Pflicht, Umsetzung und Prüfung dürfen aber in derselben Session laufen, wenn eine frische Session den Ablauf unverhältnismäßig verlangsamt.
Die Prüfung bleibt dann ein eigener, ausdrücklicher Schritt mit derselben Frage: was fehlt, was ist falsch, was ist unnötig.

Nichts ändern ist ein gültiges Ergebnis.
Wenn die Aufgabe schon erledigt ist oder der genannte Weg falsch ist: kein Diff, Grund nennen, stoppen.

Jede vom Captain angenommene Korrektur wird ein Satz in dieser Datei (`~/.agents/AGENTS.md`), bei rein werkzeugspezifischen Punkten in der Regeldatei des Werkzeugs.
Nicht in den Chat. Kurz, prüfbar, eine Pflicht. Keine Wiederholung eines Satzes, der schon dort steht.

Antworten an den Captain im Chat sind immer deutsch, auch nach einer Übergabe zwischen Werkzeugen.

## Vorlage von Entscheidungen

Entscheidungen und offene Punkte für den Captain, auch aus `/bearings` oder `/ahoy`, werden immer als Lavish-Board vorgelegt, nie nur im Chat.
Lavish wird über Tailscale erreichbar gebunden, nicht nur auf localhost und nie ins offene LAN.
Aufträge an Worker geben die Worte des Captains wieder und erfinden keine Rahmung dazu (kein Zielunternehmen, kein Empfänger, kein Umsetzungsziel, das er nicht genannt hat).

## Maintaining this file

This file is global: it applies to every agent and every project on this machine (Claude Code imports it from `~/.claude/CLAUDE.md`, Pi reads it via `~/.pi/agent/AGENTS.md`).
Keep it for rules useful to almost every agent session across all projects; project-specific knowledge belongs in that project's own AGENTS.md.
Do not repeat what a codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
