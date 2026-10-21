[CmdletBinding()]
param(
 [ValidateSet("Build","Demo","Verify","Study")][string]$Action="Demo",
 [ValidateRange(1024,65535)][int]$Port=8765,
 [string]$PythonExe="",[string]$NodeExe="",[switch]$Online
)
$ErrorActionPreference="Stop"
$root=$PSScriptRoot
$project=Join-Path $root "current"
$maven=Join-Path $root "apache-maven-3.10.0\bin\mvn.cmd"
$settings=Join-Path $root "environment\maven-settings.xml"
$cache=Join-Path $root "environment\maven-repository"
$cloudsim=Join-Path $root "cloudsim-7.0.1\modules\cloudsim\target\cloudsim-7.0.1.jar"
if($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME "bin\javac.exe"))){
 $java=Join-Path $env:JAVA_HOME "bin\java.exe";$javac=Join-Path $env:JAVA_HOME "bin\javac.exe"
}else{
 $java=(Get-Command java -ErrorAction Stop).Source
 $javac=(Get-Command javac -ErrorAction Stop).Source
}
foreach($path in @($maven,$settings,$cloudsim)){if(!(Test-Path -LiteralPath $path)){throw "Missing bundled file: $path"}}
$mavenArgs=@("--batch-mode","-s",$settings,"-gs",$settings,"-Dmaven.repo.local=$cache","-Dstyle.color=never")
if(!$Online){$mavenArgs+="--offline"}
$oldOptions=$env:MAVEN_OPTS
$oldJava=$env:JAVA_HOME
try{
 $env:JAVA_HOME=Split-Path (Split-Path $javac -Parent) -Parent
 $env:MAVEN_OPTS=($oldOptions+" -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8").Trim()
 Push-Location -LiteralPath $project
 try{
  & $maven @mavenArgs compile
  if($LASTEXITCODE -ne 0){throw "Build failed. See environment/SETUP.md for JDK21 and offline dependency requirements."}
 }finally{Pop-Location}
 if($Action -eq "Build"){Write-Host "BUILD PASS";return}
 $classes=Join-Path $project "target\classes"
 $cp=$classes+";"+$cloudsim
 if($Action -eq "Demo"){
  Push-Location -LiteralPath $project
  try{
   Write-Host "Open http://127.0.0.1:$Port/ when INDUSTRIAL DEMO appears. Ctrl+C stops this terminal's service."
   & $java "-Dfile.encoding=UTF-8" -cp $cp org.example.iiot.demo.DemoServer $Port
   if($LASTEXITCODE -ne 0){throw "Demo failed. If port is busy, use -Port 8766."}
  }finally{Pop-Location}
  return
 }
 if(!$PythonExe){$PythonExe=(Get-Command python -ErrorAction Stop).Source}
 if(!$NodeExe){$NodeExe=(Get-Command node -ErrorAction Stop).Source}
 $stamp=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)
 $batch=Join-Path $root ("runs\"+$Action.ToLower()+"-"+$stamp)
 $work=Join-Path $batch "project";$report=Join-Path $batch "report";$logs=Join-Path $batch "logs"
 New-Item -ItemType Directory -Path $work,$report,$logs -Force|Out-Null
 foreach($folder in @("src","configs","web")){Copy-Item -LiteralPath (Join-Path $project $folder) -Destination $work -Recurse}
 Copy-Item -LiteralPath (Join-Path $project "pom.xml") -Destination $work
 $hashes=@(Get-ChildItem -LiteralPath $work -Recurse -File|ForEach-Object{[pscustomobject]@{path=$_.FullName.Substring($work.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
 $hashes|Export-Csv -LiteralPath (Join-Path $batch "source-hashes.csv") -NoTypeInformation -Encoding UTF8
 $manifest=[ordered]@{status="RUNNING";action=$Action;started_at=(Get-Date).ToString("o");scope="LOCAL_SIMULATION";project=$work;report=$report}
 $manifestPath=Join-Path $batch "manifest.json"
 $manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding UTF8
 function Invoke-Checked([string]$Exe,[string[]]$Arguments,[string]$Log){
  & $Exe @Arguments 2>&1 | Tee-Object -FilePath $Log | Out-Host
  if($LASTEXITCODE -ne 0){throw "Command failed; see $Log"}
 }
 Push-Location -LiteralPath $work
 try{
  Invoke-Checked $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.VerificationMain") (Join-Path $logs "verification.log")
  Invoke-Checked $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.FinalCheckMain") (Join-Path $logs "final-checks.log")
  $qa=Join-Path $work "qa-classes";New-Item -ItemType Directory -Path $qa|Out-Null
  Invoke-Checked $javac @("-encoding","UTF-8","-cp",$cp,"-d",$qa,(Join-Path $root "tests\ContinuousCheck.java")) (Join-Path $logs "test-compile.log")
  Invoke-Checked $java @("-Dfile.encoding=UTF-8","-cp",($cp+";"+$qa),"ContinuousCheck") (Join-Path $logs "continuous.log")
  Copy-Item -LiteralPath (Join-Path $work "restored-online-check-results.json") -Destination (Join-Path $report "continuous-check-results.json")
  Invoke-Checked $PythonExe @((Join-Path $root "tests\check-ui-api.py"),"--java",$java,"--classpath",$cp,"--project",$work,"--toolkit",(Join-Path $root "tests"),"--node",$NodeExe,"--out",$report) (Join-Path $logs "ui-api.log")
  if($Action -eq "Study"){
   Invoke-Checked $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.StudyMain","3") (Join-Path $logs "study.log")
  }
  '{"scope":"SIMULATION_ONLY","real_swarm_validation":"NOT_RUN","real_vxworks_validation":"NOT_RUN"}'|Set-Content -LiteralPath (Join-Path $report "environment.json") -Encoding UTF8
  Invoke-Checked $PythonExe @((Join-Path $root "scripts\summarize_report.py"),"--project",$work,"--out",$report) (Join-Path $logs "report.log")
  if(Test-Path -LiteralPath (Join-Path $report "aggregate.csv")){
   Invoke-Checked "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" @("-NoProfile","-ExecutionPolicy","Bypass","-File",(Join-Path $root "scripts\build-final-figures.ps1"),"-ReportDir",$report) (Join-Path $logs "figures.log")
  }
  $manifest.status="COMPLETE"
  Write-Host "COMPLETE. REPORT: $(Join-Path $report 'report.html')"
 }catch{$manifest.status="FAILED";$manifest.failure=$_.Exception.Message;throw}
 finally{
  $manifest.finished_at=(Get-Date).ToString("o")
  $manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding UTF8
  Pop-Location
 }
}finally{$env:MAVEN_OPTS=$oldOptions;$env:JAVA_HOME=$oldJava}
