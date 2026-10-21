[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectRoot)
$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$target = Join-Path $ProjectRoot "src\main\java\org\example\iiot\SimulationMain.java"
$payload = Join-Path $PSScriptRoot "SimulationMain.java.txt"
$metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot "patch-metadata.json") -Raw -Encoding utf8 | ConvertFrom-Json
$payloadHash = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash
if ($payloadHash -ne $metadata.patched_sha256) { throw "Patch payload hash mismatch." }
$currentHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
if ($currentHash -eq $metadata.patched_sha256) {
    Write-Host "Beam-width argument support is already installed."
    return
}
if ($currentHash -ne $metadata.original_sha256) {
    throw "SimulationMain.java differs from the reviewed base version. No source was changed. Please send the current file for a fresh patch."
}
$backupDir = Join-Path $ProjectRoot ("backups\step23-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $backupDir | Out-Null
Copy-Item -LiteralPath $target -Destination (Join-Path $backupDir "SimulationMain.java")
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "patch-metadata.json") -Destination $backupDir
Copy-Item -LiteralPath $payload -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $metadata.patched_sha256) {
    throw "Installed source hash mismatch. Original source backup: $backupDir"
}
Write-Host "Installed beam-width argument support."
Write-Host "Original source backup: $backupDir"
