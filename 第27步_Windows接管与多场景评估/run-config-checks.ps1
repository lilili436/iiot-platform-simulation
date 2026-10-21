[CmdletBinding()]
param([string]$ProjectRoot="")
$ErrorActionPreference="Stop"
& (Join-Path $PSScriptRoot "start-industrial-demo.ps1") -ProjectRoot $ProjectRoot -VerifyOnly
