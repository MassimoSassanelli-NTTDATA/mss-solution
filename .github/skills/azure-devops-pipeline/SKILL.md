---
name: azure-devops-pipeline
description: >
  Wissen und Gotchas rund um Azure DevOps Pipelines in dieser Solution.
  Use when: Azure DevOps Pipeline erstellen, Pipeline debuggen, GitVersion
  einbinden, NuGet-Paket publizieren, Azure Artifacts Feed, pipeline YAML
  schreiben, Pipeline-Variable setzen, ##vso[task.setvariable].
user-invocable: true
---

# Azure DevOps Pipelines – Wissen & Gotchas

## Gotcha: Kein Punkt im Variablennamen bei `##vso[task.setvariable]`

Variablennamen mit Punkten (z. B. `GitVersion.AssemblySemVer`) funktionieren in
`##vso[task.setvariable]` **unzuverlässig**: Azure DevOps interpretiert den Punkt als
Objekt-Property-Trenner und liefert in nachfolgenden Steps einen leeren Wert.

**Symptom:**
```
error MSB4044: The "GenerateDepsFile" task was not given a value for the required parameter "AssemblyVersion".
```

**Fix:** Unterstriche statt Punkte verwenden.

```yaml
# AVOID
Write-Host "##vso[task.setvariable variable=GitVersion.AssemblySemVer]$($gv.AssemblySemVer)"

# PREFER
Write-Host "##vso[task.setvariable variable=GV_AssemblySemVer]$($gv.AssemblySemVer)"
```

Gilt für alle Variablen, die per PowerShell-`##vso`-Logging-Command gesetzt und
anschließend als `$(VarName)` in YAML-Steps referenziert werden.

---

## Pipeline-Struktur: NuGet-Publish (net-client-api)

Die Pipeline in `net-client-api/azure-pipelines.yml` folgt diesem Muster:

| Branch | Versionstyp | Ergebnis |
|---|---|---|
| `main` | Release (z. B. `1.4.0`) | Artefakt + Push in Feed |
| `develop` | Prerelease `-develop` (z. B. `1.4.0-develop.5`) | Artefakt + Push in Feed |
| `feature/*` | Prerelease | nur Pipeline-Artefakt |
| `bugfix/*` | Prerelease | nur Pipeline-Artefakt |

### Versioning via GitVersion (dotnet global tool)

GitVersion, Build und Pack **in einem einzigen PowerShell-Step** kombinieren.
Das vermeidet jede Inter-Step-Variablenübergabe und ist die zuverlässigste Methode.

```yaml
- powershell: |
    dotnet tool install --global GitVersion.Tool --version 6.x
    Write-Host "##vso[task.prependpath]$env:USERPROFILE\.dotnet\tools"
  displayName: 'Install GitVersion'

- powershell: |
    $gv = dotnet-gitversion /output json | Out-String | ConvertFrom-Json
    if ($null -eq $gv) { throw "GitVersion produced no output." }

    $nugetVersion    = $gv.NuGetVersionV2
    $assemblyVersion = $gv.AssemblySemVer
    $fileVersion     = $gv.AssemblySemFileVer
    $infoVersion     = $gv.InformationalVersion

    Write-Host "##vso[build.updatebuildnumber]$($gv.FullSemVer)"

    dotnet build "$(solution)" --configuration "$(buildConfiguration)" --no-restore `
      "-p:Version=$nugetVersion" `
      "-p:AssemblyVersion=$assemblyVersion" `
      "-p:FileVersion=$fileVersion" `
      "-p:InformationalVersion=$infoVersion"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    dotnet pack "$(solution)" --configuration "$(buildConfiguration)" --no-build `
      "-p:PackageVersion=$nugetVersion" --output "$(packagesOutput)"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  displayName: 'GitVersion, Build & Pack'
```

### Push nur für main/develop

```yaml
condition: and(succeeded(), in(variables['Build.SourceBranch'], 'refs/heads/main', 'refs/heads/develop'))
```

### Feed-Authentifizierung (organization-scoped)

```yaml
- task: NuGetAuthenticate@1
- task: NuGetCommand@2
  inputs:
    command: push
    nuGetFeedType: internal
    publishVstsFeed: '<feed-name>'
```

Der Build-Service-Account (`<Project> Build Service`) benötigt die Rolle
**Contributor** im Feed (Azure DevOps → Artifacts → Feed Settings → Permissions).
