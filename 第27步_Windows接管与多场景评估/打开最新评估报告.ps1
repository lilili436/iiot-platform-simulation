$ErrorActionPreference="Stop"
$resultRoot=Join-Path (Split-Path $PSScriptRoot -Parent) "simulation\results"
$candidates=@(Get-ChildItem -LiteralPath $resultRoot -Directory -Filter "extended-study-*"|Sort-Object Name -Descending)
foreach($candidate in $candidates){
 $manifest=Join-Path $candidate.FullName "manifest.json"
 if(!(Test-Path -LiteralPath $manifest)){continue}
 $state=Get-Content -LiteralPath $manifest -Raw -Encoding utf8|ConvertFrom-Json
 $report=Join-Path $candidate.FullName "report\report.html"
 if($state.status -eq "COMPLETE" -and $state.mode -ne "Verify" -and (Test-Path -LiteralPath $report)){
  Start-Process -FilePath $report
  return
 }
}
throw "No completed evaluation report. Run the evaluation script first."
