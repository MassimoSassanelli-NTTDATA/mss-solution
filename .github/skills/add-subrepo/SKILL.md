---
name: add-subrepo
description: >
  Erweitert das Multi-Repo-Plattformprojekt um ein neues Sub-Repository.
  Use when: neues Sub-Repo hinzufügen, Repository in die Plattform integrieren,
  bestehendes GitHub-Repo einbinden, neues Code-Repository anlegen, Workspace
  um ein Repo erweitern, copilot-platform.json erweitern, neues Repo registrieren.
argument-hint: 'Optional: GitHub-Repo-URL oder Name des neuen Repositories'
user-invocable: true
---

# Skill: Neues Sub-Repository zur Plattform hinzufügen

Dieser Skill führt durch die vollständige Integration eines neuen (oder bestehenden) GitHub-Repositories
in das Multi-Repo-Plattformprojekt. Er fragt interaktiv alle notwendigen Informationen ab und
aktualisiert anschließend alle betroffenen Plattformdateien.

---

## Schritt 1 – Interaktive Abfrage

Verwende das `vscode_askQuestions`-Tool, um folgende Informationen zu sammeln.
Stelle alle Fragen **in einem einzigen Aufruf**:

### Fragen

1. **`repo_origin`** – Neues oder bestehendes Repository?
   - Optionen: `Neues Repository anlegen`, `Bestehendes Repository verwenden`

2. **`repo_name`** – GitHub-Repository-Name (ohne Org-Präfix, z.B. `my-new-service`)

3. **`github_org`** – GitHub-Organisation oder Account (z.B. `MyOrg`) – nur bei neuem Repo relevant

4. **`checkout_path`** – Lokaler Checkout-Pfad relativ zum Plattformwurzelverzeichnis
   (Standard: identisch mit `repo_name`)

5. **`repo_type`** – Typ des Repositories
   - Optionen: `mobile-application`, `shared-component`, `foundation`, `backend-service`, `infrastructure`, `other`

6. **`repo_role`** – Kurze Rolle des Repositories in einem Satz (z.B. "shared notification library")

7. **`repo_description`** – Beschreibung des Nutzens im Kontext der Gesamtlösung
   (2–4 Sätze: Was macht das Repo? Für wen? Welchen Mehrwert bringt es der Plattform?)

8. **`repo_dependencies`** – Abhängigkeiten zu anderen Repositories (kommagetrennt oder leer)
   Bekannte Repos: `mss-app`, `maui-toolkit`, `net-client-api`

9. **`agent_guidance`** – 1–3 Sätze, die dem Copilot-Agenten erklären, wie er dieses Repo nutzen soll

Fahre nach der Abfrage mit **Schritt 2** fort.

---

## Schritt 2 – Bestehendes Repository auschecken (bei `Bestehendes Repository verwenden`)

Wenn der Nutzer ein bestehendes Repository einbinden möchte:

1. Prüfe, ob der lokale Checkout-Pfad bereits existiert:
   ```powershell
   Test-Path ".\<checkout_path>"
   ```
2. Falls nicht vorhanden, clone das Repository:
   ```powershell
   git clone https://github.com/<github_org>/<repo_name>.git .\<checkout_path>
   ```
3. Bestätige, dass das Verzeichnis jetzt vorhanden ist.

Bei neuem Repository:
- Erstelle das lokale Verzeichnis und initialisiere es (oder lass den Nutzer selbst das Repo auf GitHub anlegen und dann clonen).
- Weise den Nutzer darauf hin, dass das Repo auf GitHub erstellt und dann lokal geclont werden muss, bevor die nächsten Schritte abgeschlossen werden können.

---

## Schritt 3 – Sub-Repository vorbereiten

Erstelle folgende Dateien im neuen Sub-Repository, sofern sie noch nicht existieren.
**Überschreibe niemals vorhandene Dateien ohne explizite Bestätigung.**

### `<checkout_path>/AGENTS.md`

```markdown
This repository owns its implementation rules. Keep local AGENTS.md, skills, ADRs and docs current.

## Task Status via Pull Requests

Every implementation PR must reference its task issue with a closing keyword in the
PR description, e.g. `Closes #123`. The `PR Task Status` workflow uses this to move
the task's `status:*` label: PR opened -> `status:in-review`, PR merged ->
`status:done`. Set the task to `status:in-progress` when you start work.

See the platform label model: `docs/process/label-model.md` in the platform repository.
```

### `<checkout_path>/.github/copilot-instructions.md`

```markdown
# Copilot Instructions

Repository-wide guidance for GitHub Copilot and other AI agents working in this
repository. These instructions are **generic and reusable**: they apply to every
issue and pull request and are not tied to any single task. Read them before
planning or implementing any change.

## Project Context

<repo_description>

## Change Scope Rules

- Keep the diff **minimal and deterministic**; change only what the task requires.
- Respect items that the issue marks as **out of scope**.
- Do not introduce new tools, dependencies, or repository structures unless the
  task explicitly requires them.

## Architecture Rules

- **Do not introduce speculative abstractions.** Avoid new layers, generic
  frameworks, or architectural expansion that the current task does not require.
  Prefer the simplest design that satisfies the spec.

## Quality and Validation

Before finishing work and opening or updating a pull request:

- Build the relevant solution or project after implementation.
- Run applicable tests when a test setup exists.
- Do not consider work complete with failing validation unless the failure is unrelated and explicitly reported.
- Report validation commands and results clearly in the final response or pull request notes.

## Agent Context

For implementation rules, repository roles, and cross-repository guidance,
see [AGENTS.md](../AGENTS.md).
```

### `<checkout_path>/.github/skills/.gitkeep`

Erstelle das Verzeichnis, damit der `sync-subrepo-skills`-Skript es erkennen kann.

### `<checkout_path>/docs/agent-context.md`

```markdown
# Agent Context: <repo_name>

## Role

<repo_role>

## Description

<repo_description>

## Dependencies

<repo_dependencies – oder "None" wenn leer>

## Agent Guidance

<agent_guidance>
```

---

## Schritt 4 – `copilot-platform.json` aktualisieren

Füge in `.github/copilot-platform.json` im `repositories`-Objekt einen neuen Eintrag hinzu.
Lies die Datei zunächst, um die exakte Struktur zu kennen, und füge den Eintrag
alphabetisch oder am Ende des `repositories`-Blocks ein:

```json
"<repo_name>": {
  "type": "<repo_type>",
  "role": "<repo_role>",
  "description": "<repo_description>",
  "branch": "auto",
  "checkoutPath": "<checkout_path>",
  "dependencies": [<repo_dependencies als JSON-Array>],
  "context": {
    "agentInstructions": [
      "AGENTS.md"
    ],
    "architectureDocs": [],
    "adrs": [
      "adrs/"
    ],
    "buildCommands": [
      "dotnet build"
    ],
    "testCommands": [
      "dotnet test"
    ]
  },
  "agentGuidance": [
    "<agent_guidance>"
  ]
}
```

**Wichtig:** Lies die Datei vorher mit `read_file` und editiere sie mit `replace_string_in_file`.
Füge den neuen Eintrag **innerhalb** des `"repositories": { ... }` Blocks ein, nicht danach.

---

## Schritt 5 – `*.code-workspace` aktualisieren

Lies `*.code-workspace` und füge einen neuen Ordner-Eintrag im `folders`-Array hinzu:

```json
{
  "path": "<checkout_path>",
  "name": "<Anzeigename – aus repo_name ableiten, z.B. 'My New Service'>"
}
```

Füge den Eintrag **vor** dem abschließenden `]` des `folders`-Arrays ein.

---

## Schritt 6 – Issue templates `./github/ISSUE_TEMPLATE` aktualisieren

Füge in den Issue-Templates des Plattform Projekts(z.B. `epic.yml`, `story.yml`) einen Hinweis auf das neue Sub-Repository hinzu, falls relevant.


## Schritt 6 – `scripts/sync-subrepo-skills.ps1` aktualisieren

Füge `"<checkout_path>"` zur `$subrepos`-Liste hinzu:

```powershell
# Vorher:
$subrepos = @(
    "maui-toolkit",
    "mss-app",
    "net-client-api"
)

# Nachher (Beispiel):
$subrepos = @(
    "maui-toolkit",
    "mss-app",
    "net-client-api",
    "<checkout_path>"
)
```

---

## Schritt 7 – Branch-Skripte aktualisieren

### `scripts/checkout-story-branches.ps1`

Füge `"<checkout_path>"` in das `$repos`-Array ein:

```powershell
# Vorher:
$repos=@("mss-solution","mss-app","maui-toolkit","net-client-api")

# Nachher (Beispiel):
$repos=@("mss-solution","mss-app","maui-toolkit","net-client-api","<checkout_path>")
```

### `scripts/create-story-branches.ps1`

Identische Änderung wie in `checkout-story-branches.ps1`.

---

## Schritt 8 – Abschluss und Zusammenfassung

Erstelle nach allen Änderungen eine kompakte Zusammenfassung:

### Geänderte Dateien

| Datei | Änderung |
|---|---|
| `.github/copilot-platform.json` | Neuer Repo-Eintrag `<repo_name>` |
| `MMS.code-workspace` | Neuer Ordner-Eintrag |
| `scripts/sync-subrepo-skills.ps1` | `<checkout_path>` zur `$subrepos`-Liste |
| `scripts/checkout-story-branches.ps1` | `<checkout_path>` zum `$repos`-Array |
| `scripts/create-story-branches.ps1` | `<checkout_path>` zum `$repos`-Array |

### Neue Dateien im Sub-Repository

| Datei | Inhalt |
|---|---|
| `<checkout_path>/AGENTS.md` | Standard-AGENTS.md |
| `<checkout_path>/.github/copilot-instructions.md` | Repo-spezifische Copilot-Instruktionen |
| `<checkout_path>/.github/skills/.gitkeep` | Skills-Verzeichnis für Skill-Sync |
| `<checkout_path>/docs/agent-context.md` | Agent-Kontextdokument |

### Nächste empfohlene Schritte

1. Öffne VS Code neu oder lade das Workspace-Fenster neu (`Developer: Reload Window`), damit der neue Workspace-Ordner erkannt wird.
2. Führe `scripts/sync-subrepo-skills.ps1` aus, um Skills aus dem neuen Repo zu synchronisieren.
3. Erstelle ggf. eine `docs/agent-context.md` im Sub-Repo mit spezifischeren Architekturdokumenten.
4. Passe `copilot-instructions.md` im Sub-Repo an den tatsächlichen Tech Stack an (Framework, Sprache, Build-Befehle).
5. Committe alle geänderten Plattformdateien.

---

## Hinweise zur Fehlerbehandlung

- **Repo existiert lokal bereits:** Überspringe den Clone-Schritt, bereite aber fehlende Dateien nach.
- **Datei existiert bereits im Sub-Repo:** Frage den Nutzer, ob sie überschrieben werden soll.
- **JSON-Syntaxfehler in `copilot-platform.json`:** Lies die gesamte Datei, bevor du bearbeitest. Füge kein abschließendes Komma nach dem letzten Eintrag ein.
- **Workspace-Datei:** Achte auf gültiges JSON (kein Komma vor dem abschließenden `]`).
