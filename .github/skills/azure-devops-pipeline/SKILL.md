---
name: azure-devops-pipeline
description: >
  Wissen und Gotchas rund um Azure DevOps Pipelines in dieser Solution.
  Use when: Azure DevOps Pipeline erstellen, Pipeline debuggen, GitVersion
  einbinden, NuGet-Paket publizieren, Azure Artifacts Feed, pipeline YAML
  schreiben, Pipeline-Variable setzen, ##vso[task.setvariable], .NET-MAUI-App
  im CI bauen (Android/iOS/Windows), Workloads, iOS-Codesign/Xcode.
user-invocable: true
---

# Azure DevOps Pipelines – Wissen & Gotchas

## 1. Variablen & Versionierung

### `##vso[task.setvariable]`: keine Punkte im Namen

Punkte im Namen (`GitVersion.AssemblySemVer`) werden als Property-Trenner
interpretiert → nachfolgende Steps erhalten einen **leeren** Wert.
Symptom: `error MSB4044: ... required parameter "AssemblyVersion"`.
**Fix:** Unterstriche verwenden (`GV_AssemblySemVer`).

### GitVersion, Build & Pack in EINEM Step

Inter-Step-Variablenübergabe ganz vermeiden: GitVersion auswerten, bauen und
packen im selben PowerShell-Step. Zuverlässigste Methode.

```yaml
- powershell: |
    dotnet tool install --global GitVersion.Tool --version 6.x
    Write-Host "##vso[task.prependpath]$env:USERPROFILE\.dotnet\tools"
  displayName: 'Install GitVersion'

- powershell: |
    $gv = dotnet-gitversion /output json | Out-String | ConvertFrom-Json
    if ($null -eq $gv) { throw "GitVersion produced no output." }
    Write-Host "##vso[build.updatebuildnumber]$($gv.FullSemVer)"

    dotnet build "$(solution)" -c "$(buildConfiguration)" --no-restore `
      "-p:Version=$($gv.NuGetVersionV2)" "-p:AssemblyVersion=$($gv.AssemblySemVer)" `
      "-p:FileVersion=$($gv.AssemblySemFileVer)" "-p:InformationalVersion=$($gv.InformationalVersion)"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    dotnet pack "$(solution)" -c "$(buildConfiguration)" --no-build `
      "-p:PackageVersion=$($gv.NuGetVersionV2)" --output "$(packagesOutput)"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  displayName: 'GitVersion, Build & Pack'
```

## 2. NuGet-Publish (Muster: net-client-api)

| Branch | Version | Ergebnis |
|---|---|---|
| `main` | Release (`1.4.0`) | Artefakt + Push in Feed |
| `develop` | Prerelease (`1.4.0-develop.5`) | Artefakt + Push in Feed |
| `feature/*`, `bugfix/*` | Prerelease | nur Pipeline-Artefakt (kein Push) |

Push nur auf main/develop beschränken und gegen den Feed authentifizieren:

```yaml
- task: NuGetAuthenticate@1
- task: NuGetCommand@2
  condition: and(succeeded(), in(variables['Build.SourceBranch'], 'refs/heads/main', 'refs/heads/develop'))
  inputs:
    command: push
    nuGetFeedType: internal
    publishVstsFeed: '<feed-name>'
```

Der Build-Service-Account (`<Project> Build Service`) braucht die Rolle
**Contributor** im Feed (Artifacts → Feed Settings → Permissions).

## 3. .NET-MAUI-App im CI bauen (Muster: mss-app / NDBS.MSS)

Die App wird pro Plattform in getrennten Stages gebaut (`--framework <tfm>`).
Die folgenden vier Gotchas gehören zusammen und betreffen v. a. die **iOS-Stage**
auf dem `macOS-latest`-Agent.

### 3a. Restore braucht Workloads ALLER TFMs – nicht nur der Ziel-Plattform

`--framework` schränkt nur den **Build** ein; der implizite **Restore** evaluiert
den gesamten Projektgraphen über **alle** TargetFrameworks. Multi-Target-Libs
(z. B. mit `net9.0-android`) lassen den Restore sonst scheitern.
Symptom: `NETSDK1147: ... workloads must be installed: android`.

**Fix:** Workloads über das App-Projekt auflösen (installiert alle nötigen TFM-
Workloads plattformgerecht), NICHT einzeln `maui-ios` o. Ä.:

```yaml
# PREFER  (Android/Windows-Stages: latest ist ok)
- powershell: dotnet workload restore "src/Apps/NDBS.MSS/NDBS.MSS.csproj"
```

### 3b. iOS-Workload-Set an das Agent-Xcode pinnen

`dotnet workload restore` installiert im *loose-manifest*-Modus die **neueste**
iOS-Workload, die oft ein **neueres Xcode** fordert, als der Agent hat.
Symptom: `This version of .NET for iOS (26.5.x) requires Xcode 26.5. The current
version of Xcode is 16.4.` – trifft **nur die iOS-Stage** (Xcode-Check läuft nur
beim Bauen des iOS-TFM; Android/Windows sind nicht betroffen).

**Fix (nur iOS-Stage):** Workload-Set + SDK-Band auf die zu Xcode passende
Version pinnen statt `restore`:

```yaml
variables:
  iosDotnetBand: '9.0.204'   # .NET 9, passt zu Xcode 16.4

- task: UseDotNet@2
  inputs: { packageType: 'sdk', version: '$(iosDotnetBand)' }
- bash: dotnet workload install maui --version $(iosDotnetBand)
```

Xcode → Workload-Set (.NET 9, Band `9.0.200`): 16.3 → `9.0.203`, 16.4 → `9.0.204`.
Weitere Versionen: <https://github.com/dotnet/macios/releases>
(Tag `dotnet-9.0.1xx-xcode<version>`). Bei neuerem Agent-Xcode `iosDotnetBand`
hochziehen.

> **Nicht** `--from-previous-sdk` als Xcode-Fix nutzen: Die häufige Meldung *"No
> workloads installed for this feature band ... --from-previous-sdk"* betrifft nur
> das leere SDK-Band nach `UseDotNet@2`. Das Flag gibt es nur bei `workload update`
> (nicht `restore`), und `update` geht auf die **neueste** Workload → derselbe
> Xcode-Fehler. Lösung bleibt Pinnen.

### 3c. iOS-Simulator ohne Codesign/Provisioning bauen

Setzt die App-`.csproj` manuelle Signatur global pro TFM
(`ProvisioningType=manual` + `CodesignKey`/`CodesignProvision` für `net9.0-ios`),
gilt das für **jede** Konfiguration. Der CI-Build scheitert an fehlendem
Zertifikat/Profil: `The specified iOS provisioning profile '...' could not be found`.

**Fix:** Signatur **nur in der Pipeline** neutralisieren (Produkt-`.csproj` nicht
anfassen – echte Device-/Release-Builds signieren weiter). **Nicht**
`ProvisioningType=automatic` setzen (löst automatische Profilsuche aus →
`Could not find any available provisioning profiles`):

```yaml
- bash: >
    dotnet build "src/Apps/NDBS.MSS/NDBS.MSS.csproj"
    --framework net9.0-ios
    -p:RuntimeIdentifier=iossimulator-arm64
    -p:EnableCodeSigning=false
    -p:CodesignRequireProvisioningProfile=false
    -p:CodesignKey= -p:CodesignProvision=
```

- `RuntimeIdentifier=iossimulator-arm64` → Simulator statt Device.
- `EnableCodeSigning=false` → Signierung aus.
- `CodesignRequireProvisioningProfile=false` → überschreibt „Profil nötig bei
  Device-Build/Entitlements".
