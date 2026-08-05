---
description: Erweitert eine bestehende, auf net-client-api basierende Client API um neue Endpunkte und DTOs anhand ihrer OpenAPI-Definition. Use when: Client API erweitern, neue Endpunkte ergänzen, Refit-Methode hinzufügen, DTO ergänzen, OpenAPI-Operation integrieren, Service um Endpunkt erweitern."
argument-hint: Nenne das Client-API-Projekt und optional Endpunkte, z.B. NDBS.SAPCloud.OData / WarehouseOrder
agent: agent
---

# Client API um Endpunkte und DTOs erweite
Erweitere eine **bestehende** Client API um neue Endpunkte und DTOs **anhand ihrer
OpenAPI-Definition**. Jede Client API in diesem Workspace basiert auf
`net-client-api` (`NDBS.Api`, `NDBS.Api.OData`, `NDBS.Api.Refit`).

## Grundregeln

- Der bestehende konzeptionelle Aufbau der Client API **bleibt erhalten**. Nimm nur
  die Änderungen vor, die für die gewählten Endpunkte nötig sind – keine unnötigen
  Struktur- oder Umbenennungsänderungen.
- Der Aufbau folgt in der Regel dem Muster aus dem Skill
  [create-odata-api-client](../skills/create-odata-api-client/SKILL.md)
  (zentrales Refit-Interface, `Apis/<Area>/` mit DTOs, `I<Area>Service` + `<Area>Service`,
  DI-Registrierung). Prüfe den tatsächlichen Aufbau im Zielprojekt und folge diesem –
  der Skill ist nur die Referenz, der Code ist die Quelle der Wahrheit.
- Änderungen minimal und deterministisch halten.

## Ablauf

### 1. Ziel-Projekt klären

- Der Workspace enthält mehrere Repositories. Nimm das Ziel-Client-API-Projekt **nicht
  implizit an**.
- Wenn aus dem Aufruf nicht eindeutig hervorgeht, welche Client API erweitert werden
  soll, frage nach und biete die gefundenen Client-API-Projekte als Auswahl an
  (z.B. `NDBS.SAPCloud.OData`).

### 2. OpenAPI-Definition finden

- Suche im Ziel-Projekt nach der OpenAPI-Definitionsdatei (`*.json` / `*.yaml`, typisch
  unter `Apis/**`).
- **Falls keine OpenAPI-Definition im Projekt vorhanden ist:** verlange sie ausdrücklich
  vom Benutzer (Pfad oder Inhalt) und fahre erst danach fort. Erfinde keine Endpunkte
  ohne OpenAPI-Grundlage.
- Bei mehreren OpenAPI-Dateien: kläre, welche die relevante ist.

### 3. Endpunkte auswählen

- Liste **alle** in der OpenAPI-Definition enthaltenen Operationen auf, je Zeile mit:
  HTTP-Methode, Pfad, `operationId`/Aktionsname und Kurzbeschreibung.
- Markiere Operationen, die im Refit-Interface bereits implementiert sind (damit sie nicht
  doppelt angelegt werden).
- Frage den Benutzer, **welche Endpunkte** realisiert werden sollen. Biete dabei **immer
  auch die Option „Alle Endpunkte"** an.
- Setze die Umsetzung erst nach der Auswahl fort.

### 4. Bestehenden Aufbau ermitteln

Bestimme im Zielprojekt die vorhandenen Integrationspunkte:

- das zentrale Refit-Interface (z.B. `ISapCloudRefitApi.cs` bzw. `I<Name>RefitApi.cs`),
- die betroffene Area unter `Apis/<Area>/` (DTOs, `I<Area>Service`, `<Area>Service`),
- ob der Endpunkt in eine bestehende Area gehört oder eine neue Area analog vorhandener
  Areas anzulegen ist.

### 5. Pro gewähltem Endpunkt erweitern

Pro Operation aus der OpenAPI-Definition:

- **Refit-Methode** im zentralen Refit-Interface ergänzen:
  - korrektes Attribut (`[Get]`, `[Post]`, `[Patch]`, `[Delete]`),
  - Pfad exakt aus der OpenAPI-`paths`-Angabe, Path-Parameter per `[AliasAs("…")]`,
  - `[Body]` nur bei vorhandenem RequestBody,
  - Rückgabetyp: `Task<IApiResponse>` bei `204 No Content`, sonst `Task<ApiResponse<T>>`,
  - bei OData-Kollektionen `[Query] Dictionary<string, string>?` für `$filter`/`$select`/… .
- **DTOs** in derselben Area anlegen/erweitern (Request- und Response-DTOs aus den
  OpenAPI-Schemas; bestehende Typen wiederverwenden, wenn sie passen). Reine
  Datentransfer-Typen, kein Mapping-/Domänencode.
- **Service-Interface** `I<Area>Service` um die neue Async-Signatur erweitern.
- **Service-Implementierung** `<Area>Service` erweitern und direkt an `ApiClient`
  delegieren (bei OData `BuildQuery(...)` nutzen).
- Neue Area nur anlegen, wenn keine passende existiert – dann exakt dem Muster der
  bestehenden Areas folgen. Wird dabei ein neuer Service angelegt, ihn in der
  DI-Registrierung (`ServiceCollectionExtensions`) analog zu den bestehenden Services
  registrieren. Bestehende Services brauchen keine neue Registrierung.

**Konventionen:** Methoden enden auf `Async`; URL-Platzhalter stimmen exakt mit
`[AliasAs]` überein; Parameterreihenfolge in Interface und Implementierung konsistent;
Namen und Code auf Englisch.

### 6. Validieren

- Baue das betroffene Projekt (mindestens das erweiterte Client-API-Projekt) und behebe
  Fehler.
- Prüfe: Refit-Methode, DTOs, Service-Interface und Service-Implementierung sind für jeden
  gewählten Endpunkt konsistent vorhanden.

## Abschluss

Fasse am Ende zusammen:

- welche Endpunkte hinzugefügt wurden (Methode + Pfad),
- welche Dateien geändert/angelegt wurden,
- ob der Build erfolgreich war.
