---
name: create-odata-api-client
description: >
  Erstellt ein neues OData/REST-Client-Projekt nach dem Architekturmuster von NDBS.SAPCloud.OData.
  Use when: neues API-Client-Projekt anlegen, HTTP-Client-Bibliothek nach Hausprinzip umsetzen,
  Refit-Interface erstellen, Domain-Service hinzufügen, OData-Client-Projekt scaffolden.
argument-hint: 'Nenne den API-Namen und die Base-URL, z.B. "XiaApi" mit https://api.example.com'
user-invocable: true
---

# Skill: Neues OData/REST-Client-Projekt erstellen

## Vorbedingung: Ziel-Repository klären

In einer Multi-Repo-Workspace darf das Ziel-Repository nicht implizit angenommen werden.

- Frage den Nutzer vor jeder Planung oder Dateierstellung, in welchem Repository die Client API angelegt werden soll.
- Wenn mehrere passende Repositories im Workspace vorhanden sind, nenne die konkreten Optionen.
- Fahre erst fort, wenn der Nutzer ein Ziel-Repository ausgewählt oder bestätigt hat.
- Lege keine Dateien im Plattform-Repository an, nur weil der Skill dort liegt.
- Wenn der Nutzer kein Repository nennt, aber der Workspace mehrere Repositories enthält, stelle zuerst die Rückfrage statt Annahmen zu treffen.

## Ziel

Dieser Skill beschreibt vollständig das Architekturmuster für HTTP-Client-Projekte in diesem
Repository (exemplarisch umgesetzt in `NDBS.SAPCloud.OData`) und leitet Schritt für Schritt
durch die Erstellung eines gleichartigen Projekts.

Wenn der Skill in einer Multi-Repo-Workspace verwendet wird, bezieht sich "dieses Repository"
immer auf das vom Nutzer bestätigte Ziel-Repository.

---

## Architekturübersicht

```
┌─────────────────────────────────────────────────────────────────┐
│  Consumer (MAUI-App / andere Projekte)                          │
│   → injiziert IXxxService, IYyyService                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │ DI
┌──────────────────────────▼──────────────────────────────────────┐
│  Domain-Services  (je Ressource eine Klasse + Interface)        │
│   XxxService : ApiServiceBase<IMyRefitApi>, IXxxService         │
│   YyyService : ApiServiceBase<IMyRefitApi>, IYyyService         │
│   → rufen ApiClient.XxxMethodAsync() auf                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │ protected ApiClient-Property
┌──────────────────────────▼──────────────────────────────────────┐
│  ApiServiceBase<TRefitApi>        (NDBS.SAPCloud.OData)         │
│   → kapselt IApiClientFactory<T>                                │
│   → stellt BuildQuery(Action<ODataQuery>) bereit                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│  IApiClientFactory<TApi> / RefitClientFactory<TApi>             │
│   (NDBS.Api / NDBS.Api.Refit)                                   │
│   → cached Refit-Instanzen nach BaseUrl                         │
│   → liest ApiOptions<TApi>.BaseUri + Timeout über IOptionsMonitor│
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│  IMyRefitApi  (Refit-Interface)                                 │
│   → alle HTTP-Endpunkte des Backends als Methoden               │
│   → [Get]/[Post]/[Put]/[Patch]/[Delete] Attribute              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ named HttpClient
┌──────────────────────────▼──────────────────────────────────────┐
│  IHttpClientFactory / named HttpClient  (.NET)                  │
│   → DelegatingHandler-Pipeline (Auth, Logging, …)              │
└─────────────────────────────────────────────────────────────────┘
```

### Querschnittsklassen

| Klasse / Interface | Projekt | Zweck |
|---|---|---|
| `ApiOptions<TApi>` | `NDBS.Api` | BaseUri + Timeout pro API-Typ |
| `ApiOptionsUpdater<TApi>` | `NDBS.Api` | Laufzeit-Update der BaseUri (z.B. nach Login) |
| `IApiClientFactory<TApi>` | `NDBS.Api` | Abstraktion der Client-Erzeugung |
| `RefitClientFactory<TApi>` | `NDBS.Api.Refit` | Refit-Implementierung mit URL-Cache |
| `RefitSettingsFactory` | `NDBS.Api.Refit` | vorkonfigurierte RefitSettings (inkl. OData-Konverter) |
| `ODataQuery` | `NDBS.Api.OData` | Fluent-Builder für `$filter`, `$select`, `$expand` etc. |
| `ODataHttpContentSerializer` | `NDBS.Api.Refit` | Entfernt OData v2/v4 Wrapper beim Deserialisieren |

---

## Schritt-für-Schritt: Neues Client-API-Projekt anlegen

### Schritt 0 - Repository und API-Typ klären

Vor allen fachlichen oder technischen Schritten müssen Repository und API-Typ feststehen.

**Repository:**
- Prüfe, ob der Workspace mehrere Repositories enthält.
- Wenn ja, frage den Nutzer explizit, in welchem Repository die neue Client API angelegt werden soll.
- Gib die gefundenen Repository-Namen als Auswahl an, statt allgemein von "dem Repository" zu sprechen.
- Setze die restlichen Schritte erst nach dieser Auswahl auf das bestätigte Repository auf.

Beispielfrage Repository:

> In welchem Repository soll die neue Client API angelegt werden? Ich sehe hier mehrere Repositories im Workspace, z.B. `net-client-api`, `mss-app` und `maui-toolkit`.

**API-Typ:**

Frage den Nutzer nach dem Typ der Ziel-API. Biete genau **zwei** Optionen an:

> Welchen Typ hat die API?
> 1. **Reines REST/JSON** – Standard-HTTP-Endpunkte ohne OData-Overhead
> 2. **OData v2/v4 (SAP)** – OData-Backend (SAP oder anderes), mit `$filter`, `$expand` etc.

Die Antwort bestimmt:
- `CreateWithODataSupport()` (OData) vs. `CreateDefault()` (REST)
- `NDBS.Api.OData`-Projektreferenz und `BuildQuery`/`ODataQuery` nur bei OData
- `[Query] Dictionary<string, string>?` Parameter im Refit-Interface nur bei OData

Falle der Nutzer bereits im Aufruf einen Hinweis auf den API-Typ gibt (z.B. "SAP", "OData", "REST"), diese Frage überspringen.

### Schritt 1 – Projektdatei erstellen

Lege eine neue `.csproj`-Datei an (Target `net9.0`):

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="10.0.1" />
    <PackageReference Include="Refit" Version="9.0.2" />
    <PackageReference Include="Refit.HttpClientFactory" Version="9.0.2" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\NDBS.Api\NDBS.Api.csproj" />
    <ProjectReference Include="..\NDBS.Api.OData\NDBS.Api.OData.csproj" />   <!-- nur wenn OData v2/v4 -->
    <ProjectReference Include="..\NDBS.Api.Refit\NDBS.Api.Refit.csproj" />
  </ItemGroup>
</Project>
```

> **REST/JSON:** `NDBS.Api.OData`-Referenz weglassen, `RefitSettingsFactory.CreateDefault()` verwenden, `BuildQuery` und `ODataQuery` nicht benötigt.
> **OData v2/v4:** `NDBS.Api.OData`-Referenz behalten, `RefitSettingsFactory.CreateWithODataSupport()` verwenden.

---

### Schritt 2 – Options-Klasse anlegen

Thin-Wrapper um `ApiOptions<TApi>` – zur DI-Trennung (damit verschiedene APIs eigene
`IOptions<T>`-Registrierungen bekommen).

```csharp
// DependencyInjection/MyApiOption.cs
using NDBS.Api;

namespace NDBS.MyApi;

public class MyApiOption : ApiOptions<IMyRefitApi>
{
}
```

---

### Schritt 3 – Refit-Interface definieren

**Eine** zentrale Schnittstelle pro Backend-Host mit allen Endpunkten.

```csharp
// IMyRefitApi.cs
using Refit;

namespace NDBS.MyApi;

[Headers("Accept: application/json")]
public interface IMyRefitApi
{
    #region Resource: Foo

    // Kollektion abrufen – OData-Abfrageparameter als Dictionary
    [Get("/api/v1/Foo")]
    Task<ApiResponse<IReadOnlyList<FooDto>>> GetFoosAsync(
        [Query] Dictionary<string, string>? queryParams = null,
        CancellationToken cancellationToken = default);

    // Einzelne Entität per Schlüssel
    [Get("/api/v1/Foo/{id}")]
    Task<ApiResponse<FooDto>> GetFooAsync(
        [AliasAs("id")] string id,
        CancellationToken cancellationToken = default);

    // POST – Body als DTO
    [Post("/api/v1/Foo")]
    [Headers("Content-Type: application/json")]
    Task<ApiResponse<FooDto>> CreateFooAsync(
        [Body] FooCreateDto body,
        CancellationToken cancellationToken = default);

    // Aktion (z.B. OData Bound Action)
    [Post("/api/v1/Foo('{key}')/Namespace.ActionName")]
    [Headers("Content-Type: application/json")]
    Task<IApiResponse> PostActionAsync(
        [AliasAs("key")] string key,
        [Body] ActionRequestDto body,
        CancellationToken cancellationToken = default);

    #endregion
}
```

**Konventionen für das Interface:**

- `[Query] Dictionary<string, string>?` für OData-Parameter (`$filter`, `$select` …) – erzeugt
  automatisch Query-String.
- `[AliasAs("name")]` wenn der Parameterbezeichner im C# sich vom URL-Platzhalter unterscheidet.
- `[Body]` für JSON-Bodies bei POST/PUT/PATCH.
- Rückgabetyp `ApiResponse<T>` gibt Zugriff auf HTTP-Statuscode + Body; `IApiResponse` wenn kein
  Body erwartet wird.
- Gruppierung per `#region` nach Ressource, analog zur OpenAPI-Struktur.

---

### Schritt 4 – DTOs anlegen

Einfache C# Record- oder Klassen-Typen, die der JSON-Struktur der API entsprechen.

```csharp
// Apis/Foo/FooDto.cs
using System.Text.Json.Serialization;

namespace NDBS.MyApi;

public class FooDto
{
    public string Id { get; set; } = default!;
    public string Name { get; set; } = default!;
    public decimal? Value { get; set; }
    public DateTime? CreatedAt { get; set; }

    // Navigation Property (OData $expand) → JsonPropertyName wenn Name abweicht
    [JsonPropertyName("_Items")]
    public IReadOnlyList<FooItemDto>? Items { get; set; }
}

public class FooCreateDto
{
    public string Name { get; set; } = default!;
    public decimal Value { get; set; }
}
```

**Regeln für DTOs:**

- `nullable` Properties mit `?` markieren wenn das Feld optional/null sein kann.
- Navigation Properties (`$expand`) als `IReadOnlyList<T>?` mit `[JsonPropertyName]` wenn der
  JSON-Key sich vom C#-Namen unterscheidet.
- Kein Mapping-Code, keine Domänenlogik – reine Datentransferklassen.
- Create-DTOs von Read-DTOs trennen wenn sich die Felder unterscheiden.

---

### Schritt 5 – Domain-Service-Interface definieren

```csharp
// Apis/Foo/IFooService.cs
using NDBS.Api.OData;
using Refit;

namespace NDBS.MyApi;

public interface IFooService
{
    Task<ApiResponse<IReadOnlyList<FooDto>>> SearchAsync(
        Action<ODataQuery>? query = null,
        CancellationToken cancellationToken = default);

    Task<ApiResponse<FooDto>> GetAsync(
        string id,
        CancellationToken cancellationToken = default);

    Task<ApiResponse<FooDto>> CreateAsync(
        FooCreateDto body,
        CancellationToken cancellationToken = default);
}
```

**Warum ein separates Interface?**

- Erlaubt Mock-Implementierungen in Tests ohne Refit-Abhängigkeit.
- Kapselt die Refit-Details (Dictionary-Parameter, URL-Muster) hinter einer lesbaren API.
- Consumer kennen weder `IMyRefitApi` noch `ApiResponse`-Details (bei Bedarf kann der Service
  auch aufgelöste `T` zurückgeben).

---

### Schritt 6 – Domain-Service implementieren

```csharp
// Apis/Foo/FooService.cs
using NDBS.Api;
using NDBS.Api.OData;
using Refit;

namespace NDBS.MyApi;

public class FooService : ApiServiceBase<IMyRefitApi>, IFooService
{
    public FooService(IApiClientFactory<IMyRefitApi> apiFactory)
        : base(apiFactory)
    {
    }

    public Task<ApiResponse<IReadOnlyList<FooDto>>> SearchAsync(
        Action<ODataQuery>? query = null,
        CancellationToken cancellationToken = default)
        => ApiClient.GetFoosAsync(BuildQuery(query), cancellationToken);

    public Task<ApiResponse<FooDto>> GetAsync(
        string id,
        CancellationToken cancellationToken = default)
        => ApiClient.GetFooAsync(id, cancellationToken);

    public Task<ApiResponse<FooDto>> CreateAsync(
        FooCreateDto body,
        CancellationToken cancellationToken = default)
        => ApiClient.CreateFooAsync(body, cancellationToken);
}
```

**`ApiServiceBase<T>` stellt bereit:**
- `ApiClient` – lazy Property, gibt den Refit-Client via Factory zurück.
- `BuildQuery(Action<ODataQuery>?)` – erzeugt ein `Dictionary<string, string>` aus dem
  Fluent-ODataQuery-Builder.

---

### Schritt 7 – OptionsUpdater anlegen (optional, für MAUI/dynamische BaseUrl)

Nur nötig, wenn die BaseUrl zur Laufzeit geändert werden muss (z.B. nach Login mit Server-URL).

```csharp
// DependencyInjection/MyApiOptionsUpdater.cs
using Microsoft.Extensions.Options;
using NDBS.Api;

namespace NDBS.MyApi;

public class MyApiOptionsUpdater : ApiOptionsUpdater<IMyRefitApi>
{
    public MyApiOptionsUpdater(
        IOptionsMonitorCache<ApiOptions<IMyRefitApi>> cache,
        IOptionsMonitor<ApiOptions<IMyRefitApi>> monitor)
        : base(cache, monitor)
    {
    }
}
```

Verwendung im App-Code:
```csharp
// Nach Login-Response:
_myApiOptionsUpdater.Update(new MyApiOption { BaseUri = new Uri(serverUrl) });
// Oder partial update:
_myApiOptionsUpdater.UpdatePartial(o => o.BaseUri = new Uri(serverUrl));
```

---

### Schritt 8 – DI-Registrierung (ServiceCollectionExtensions)

```csharp
// DependencyInjection/ServiceCollectionExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using NDBS.Api;
using NDBS.Api.Refit;

namespace NDBS.MyApi;

public static class ServiceCollectionExtensions
{
    public static IHttpClientBuilder AddMyApi(
        this IServiceCollection services,
        Action<MyApiOption>? configure = null)
    {
        string httpClientName = typeof(IMyRefitApi).FullName!;

        return services
            .AddOptions()
            .Configure<MyApiOption>(options => configure?.Invoke(options))
            .AddSingleton<IApiClientFactory<IMyRefitApi>, RefitClientFactory<IMyRefitApi>>(sp =>
            {
                var httpFactory = sp.GetRequiredService<IHttpClientFactory>();
                var optionsMonitor = sp.GetRequiredService<IOptionsMonitor<ApiOptions<IMyRefitApi>>>();
                var refitSettings = RefitSettingsFactory.CreateWithODataSupport();  // oder CreateDefault()
                return new RefitClientFactory<IMyRefitApi>(httpFactory, optionsMonitor, refitSettings, httpClientName);
            })
            .AddSingleton<MyApiOptionsUpdater>()
            // Domain Services
            .AddTransient<IFooService, FooService>()
            .AddTransient<IBarService, BarService>()
            // Named HttpClient – muss denselben Namen wie in RefitClientFactory haben
            .AddHttpClient(httpClientName);
    }
}
```

**Wichtig:** `IHttpClientBuilder` wird zurückgegeben, damit der Consumer DelegatingHandlers
anhängen kann (Auth, Logging, Retry):

```csharp
// In MauiProgram.cs / Program.cs
builder.Services
    .AddMyApi(opts => opts.BaseUri = new Uri("https://api.example.com"))
    .AddHttpMessageHandler<AuthHandler>();
```

---

### Schritt 9 – Fehlerbehandlung (optional, bei eigenem Fehlerformat)

Falls die API eigene Fehler-JSON-Strukturen liefert:

```csharp
// MyApiError.cs
public class MyApiError
{
    public string Code { get; init; } = default!;
    public string Message { get; init; } = default!;
}
```

Hilfsmethoden als `static class` Extension-Methoden auf `IApiResponse` (analog zu
`RefitExtensions` in `NDBS.SAPCloud.OData`):

```csharp
// MyApiExtensions.cs
using Refit;
using System.Text.Json;

namespace NDBS.MyApi;

public static class MyApiExtensions
{
    private static readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };

    public static MyApiError? GetApiError(this IApiResponse response)
    {
        if (response.IsSuccessStatusCode) return null;
        var raw = response.Error?.Content;
        if (string.IsNullOrWhiteSpace(raw)) return null;
        try { return JsonSerializer.Deserialize<MyApiError>(raw, _json); }
        catch { return null; }
    }

    public static bool HasErrorCode(this IApiResponse response, string code)
        => string.Equals(response.GetApiError()?.Code, code, StringComparison.OrdinalIgnoreCase);
}
```

---

## Ordnerstruktur (Referenz)

```
NDBS.MyApi/
├── NDBS.MyApi.csproj
├── IMyRefitApi.cs                          ← einziges Refit-Interface
├── MyApiExtensions.cs                      ← Fehlerbehandlungs-Extensions (optional)
├── DependencyInjection/
│   ├── MyApiOption.cs                      ← Options-Wrapper
│   ├── MyApiOptionsUpdater.cs              ← Laufzeit-Update (optional)
│   └── ServiceCollectionExtensions.cs      ← AddMyApi()
└── Apis/
    ├── ApiServiceBase.cs                   ← (nur wenn nicht aus NDBS.SAPCloud.OData geteilt)
    ├── Foo/
    │   ├── FooDto.cs
    │   ├── FooCreateDto.cs
    │   ├── IFooService.cs
    │   └── FooService.cs
    └── Bar/
        ├── BarDto.cs
        ├── IBarService.cs
        └── BarService.cs
```

> `ApiServiceBase<T>` ist aktuell Teil von `NDBS.SAPCloud.OData`. Für ein unabhängiges Projekt
> entweder kopieren oder in ein eigenes gemeinsames Projekt (z.B. `NDBS.Api.Services`) auslagern.

---

## Entscheidungsregeln

| Situation | Empfehlung |
|---|---|
| Backend ist OData v2/v4 (SAP oder anderes) | Neues Projekt nach diesem Muster mit `CreateWithODataSupport()`, `NDBS.Api.OData` einbinden |
| Backend ist ein reines REST/JSON-API | Neues Projekt, `CreateDefault()` verwenden, `NDBS.Api.OData` weglassen |
| BaseUrl ist zur Compilezeit bekannt | `configure`-Action in `AddMyApi()` verwenden, kein `OptionsUpdater` nötig |
| BaseUrl kommt zur Laufzeit (MAUI/Login) | `MyApiOptionsUpdater` anlegen und via DI injizieren |
| Mehrere Backends mit gleicher Auth | Separate Refit-Interfaces + separate `AddXxxApi()`-Methoden |

---

## ODataQuery – Kurzreferenz

```csharp
// Im Consumer-Code
var foos = await _fooService.SearchAsync(q => q
    .Filter("Name eq 'Test'")
    .Select("Id", "Name")
    .Expand("Items")
    .Top(50)
    .OrderBy("Name asc"));
```

Erzeugt den Query-String:
`?$filter=Name eq 'Test'&$select=Id,Name&$expand=Items&$top=50&$orderby=Name asc`

---

## Checkliste für ein neues Projekt

- [ ] `.csproj` mit korrekten Projekt-Referenzen angelegt
- [ ] `IMyRefitApi` mit allen benötigten Endpunkten
- [ ] `MyApiOption : ApiOptions<IMyRefitApi>` vorhanden
- [ ] Jede Ressource hat ein `IXxxService`-Interface und eine `XxxService`-Implementierung
- [ ] Alle Services in `AddMyApi()` als `Transient` registriert
- [ ] `RefitClientFactory` als `Singleton` registriert
- [ ] `AddHttpClient(httpClientName)` am Ende der DI-Kette aufgerufen
- [ ] `MyApiOptionsUpdater` registriert (falls Laufzeit-BaseUrl gebraucht wird)
- [ ] Fehler-Extensions angelegt falls das Backend eigene Fehlercodes hat
