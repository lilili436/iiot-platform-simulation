[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExperimentProjectRoot)
$ErrorActionPreference="Stop"
$project=(Resolve-Path -LiteralPath $ExperimentProjectRoot).Path
$classes=Join-Path $project "target\classes"
if(!(Test-Path -LiteralPath $classes)){throw "Compile the isolated experiment project first."}
$qa=Join-Path $project "target\platform-checks"
New-Item -ItemType Directory -Path $qa -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "PlatformPolicyCheck.java.txt") -Destination (Join-Path $qa "PlatformPolicyCheck.java") -Force
$javac=(Get-Command javac -ErrorAction Stop).Source
$java=(Get-Command java -ErrorAction Stop).Source
& $javac -encoding UTF-8 -cp $classes -d $qa (Join-Path $qa "PlatformPolicyCheck.java")
if($LASTEXITCODE -ne 0){throw "Policy test compilation failed"}
& $java -cp "$qa;$classes" PlatformPolicyCheck
if($LASTEXITCODE -ne 0){throw "Policy and dependency checks failed"}
