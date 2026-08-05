---
description: "Konventionen für die Implementierung von Client-API-Endpunkten, DTOs und Services auf Basis von net-client-api (NDBS.Api / NDBS.Api.OData / NDBS.Api.Refit)."
applyTo: "**/Apis/**,**/I*RefitApi.cs"
---

# Client-API-Implementierung – Konventionen

Diese Regeln gelten für Client APIs, die auf `net-client-api` (`NDBS.Api`,
`NDBS.Api.OData`, `NDBS.Api.Refit`) basieren. Den Scaffolding-Workflow für ein **neues** Projekt
(inkl. `.csproj`, Options, DI-Registrierung, Ordnerstruktur) beschreibt der Skill
[create-odata-api-client](../skills/create-odata-api-client/SKILL.md). Bestehenden Aufbau eines
Projekts beibehalten; nur die für die Aufgabe nötigen Änderungen vornehmen.

## Aufbau je API

- **Ein** zentrales Refit-Interface pro Backend-Host (`I<Name>RefitApi`) mit allen
  HTTP-Endpunkten; nach Ressource per `#region` gruppiert.
- Je Ressource eine Area unter `Apis/<Area>/` mit: DTOs, `I<Area>Service` und
  `<Area>Service : ApiServiceBase<I<Name>RefitApi>, I<Area>Service`.
- DI-Registrierung in `ServiceCollectionExtensions` (`Add<Name>Api`). Neue Services dort
  analog zu den bestehenden registrieren; bestehende Services brauchen keine neue
  Registrierung.

## Refit-Interface

- Korrektes Attribut je HTTP-Methode: `[Get]`, `[Post]`, `[Put]`, `[Patch]`, `[Delete]`.
- Pfad exakt wie im Backend/der OpenAPI-Definition; Path-Parameter per `[AliasAs("…")]`,
  wobei die URL-Platzhalter **exakt** mit den `[AliasAs]`-Namen übereinstimmen.
- `[Body]` nur bei vorhandenem RequestBody; bei mutierenden Endpunkten passende Header
  setzen (z.B. `Content-Type: application/json`).
- Rückgabetyp: `Task<IApiResponse>` bei `204 No Content`, sonst `Task<ApiResponse<T>>`.
- Bei OData-Kollektionen `[Query] Dictionary<string, string>?` für `$filter`/`$select`/… .
- `CancellationToken` als letzten Parameter.

## DTOs

- Reine Datentransfer-Typen (Records/Klassen), kein Mapping- oder Domänencode.
- Optionale/null-bare Felder mit `?` markieren.
- Bei abweichendem JSON-Key `[JsonPropertyName("…")]`; Navigation Properties (`$expand`)
  als `IReadOnlyList<T>?`.
- Create-/Request-DTOs von Read-/Response-DTOs trennen, wenn sich die Felder unterscheiden;
  bestehende Typen wiederverwenden, wenn sie passen.

## Service-Interface und -Implementierung

- `I<Area>Service` kapselt die Refit-Details hinter lesbaren, `Async`-benannten Methoden.
- `<Area>Service` erbt von `ApiServiceBase<…>` und delegiert direkt an `ApiClient`; bei
  OData `BuildQuery(Action<ODataQuery>?)` verwenden.
- Parameterreihenfolge zwischen Interface und Implementierung konsistent halten.

## Allgemein

- Code und Namen auf **Englisch**.
- Keine spekulativen Abstraktionen oder neuen Schichten einführen; der einfachste Weg, der
  dem bestehenden Muster folgt, hat Vorrang.
- Nach Änderungen mindestens das betroffene Client-API-Projekt bauen.
