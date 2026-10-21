[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceProjectRoot,
    [Parameter(Mandatory=$true)][string]$DestinationRoot
)
$ErrorActionPreference = "Stop"
$source = (Resolve-Path -LiteralPath $SourceProjectRoot).Path
$metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot "patch-metadata.json") -Raw -Encoding utf8 | ConvertFrom-Json
foreach ($item in $metadata.sources) {
    $path = Join-Path $source $item.relative_path
    if (!(Test-Path -LiteralPath $path) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $item.sha256) {
        throw "Source differs from the reviewed version: $($item.relative_path). Original project is unchanged."
    }
}
$javaFiles = @(Get-ChildItem -LiteralPath (Join-Path $source "src\main\java") -Recurse -Filter "*.java" -File)
if ($javaFiles.Count -ne $metadata.java_source_count) { throw "Unexpected Java source set; original project is unchanged." }
foreach ($item in $metadata.payloads) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $item.file_name)).Hash -ne $item.sha256) {
        throw "Payload hash mismatch: $($item.file_name)"
    }
}
if (Test-Path -LiteralPath $DestinationRoot) { throw "Experiment project already exists: $DestinationRoot" }
$javaParent = Join-Path $DestinationRoot "src\main"
New-Item -ItemType Directory -Path $javaParent | Out-Null
Copy-Item -LiteralPath (Join-Path $source "src\main\java") -Destination $javaParent -Recurse
Copy-Item -LiteralPath (Join-Path $source "pom.xml") -Destination $DestinationRoot
foreach ($item in $metadata.payloads) {
    $target=Join-Path $DestinationRoot $item.relative_path
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $item.file_name) -Destination $target -Force
}
Write-Host "Created isolated experimental project: $DestinationRoot"

foreach($folder in @("configs","web")) {
    if(Test-Path -LiteralPath (Join-Path $PSScriptRoot $folder)) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $folder) -Destination $DestinationRoot -Recurse
    }
}
