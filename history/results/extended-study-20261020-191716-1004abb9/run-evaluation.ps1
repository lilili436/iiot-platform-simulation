[CmdletBinding()]
param([string]$ProjectRoot="",[ValidateSet("All","Verify","Study")][string]$Mode="All",[string]$PythonExe="",[string]$NodeExe="",[string]$CloudSimJar="")
$ErrorActionPreference="Stop"
if(!$ProjectRoot){$ProjectRoot=Join-Path (Split-Path $PSScriptRoot -Parent) "simulation"}
$ProjectRoot=(Resolve-Path -LiteralPath $ProjectRoot).Path
if(!$PythonExe){
 $bundled=Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
 if(Test-Path -LiteralPath $bundled){$PythonExe=$bundled}else{$PythonExe=(Get-Command python -ErrorAction Stop).Source}
}
if(!$NodeExe){$NodeExe=(Get-Command node -ErrorAction Stop).Source}
$java=(Get-Command java -ErrorAction Stop).Source
$javac=(Get-Command javac -ErrorAction Stop).Source
$maven=(Get-Command mvn -ErrorAction Stop).Source
$cloudsim=if($CloudSimJar){$CloudSimJar}else{Join-Path (Split-Path $ProjectRoot -Parent) "cloudsim-7.0.1\modules\cloudsim\target\cloudsim-7.0.1.jar"}
if(!(Test-Path -LiteralPath $cloudsim)){throw "CloudSim 7.0.1 jar not found beside simulation"}
$stamp=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)
$batch=Join-Path $ProjectRoot ("results\extended-study-"+$stamp)
$experiment=Join-Path $batch "project"
$logs=Join-Path $batch "logs";$report=Join-Path $batch "report"
New-Item -ItemType Directory -Path $logs,$report -Force|Out-Null
& (Join-Path $PSScriptRoot "prepare-workbench.ps1") -SourceProjectRoot $ProjectRoot -DestinationRoot $experiment
$utf8=New-Object Text.UTF8Encoding($true)
$manifest=[ordered]@{run_id=$stamp;mode=$Mode;status="PREPARING";project=$experiment;report=$report;scope="Windows takeover simulation and seeded multi-topology algorithm evaluation";started_at=(Get-Date).ToString("o")}
$manifestPath=Join-Path $batch "manifest.json"
function Invoke-Logged([string]$Exe,[string[]]$Arguments,[string]$Log){
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$Exe;$info.Arguments=($Arguments|ForEach-Object{'"'+$_+'"'}) -join " "
 $info.WorkingDirectory=$experiment;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$info
 $output=New-Object IO.MemoryStream;$errors=New-Object IO.MemoryStream
 try{
  [void]$p.Start();$a=$p.StandardOutput.BaseStream.CopyToAsync($output);$b=$p.StandardError.BaseStream.CopyToAsync($errors)
  if(!$p.WaitForExit(600000)){$p.Kill();$p.WaitForExit();throw "Child process timeout; only this child was stopped"}
  $null=$a.GetAwaiter().GetResult();$null=$b.GetAwaiter().GetResult()
  $text=[Text.Encoding]::UTF8.GetString($output.ToArray())+[Environment]::NewLine+[Text.Encoding]::UTF8.GetString($errors.ToArray())
  [IO.File]::WriteAllText($Log,$text,$utf8)
  if($p.ExitCode -ne 0){Get-Content -LiteralPath $Log -Tail 12|Out-Host;throw "Command failed; see $Log"}
 }finally{$p.Dispose();$output.Dispose();$errors.Dispose()}
}
function Invoke-MavenLog([string[]]$Arguments,[string]$Log){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$env:ComSpec
    $quoted=@($Arguments|ForEach-Object{'"'+$_+'"'})
    $info.Arguments='/d /s /c ""'+$maven+'" '+($quoted -join " ")+'"'
    $info.WorkingDirectory=$experiment;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables["MAVEN_OPTS"]=($env:MAVEN_OPTS+" -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8").Trim()
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    $out=New-Object IO.MemoryStream;$err=New-Object IO.MemoryStream
    try{
        [void]$p.Start();$o=$p.StandardOutput.BaseStream.CopyToAsync($out);$e=$p.StandardError.BaseStream.CopyToAsync($err)
        $timeout=!$p.WaitForExit(180000)
        if($timeout){& "$env:WINDIR\System32\taskkill.exe" /PID $p.Id /T /F | Out-Null;$p.WaitForExit()}
        $null=$o.GetAwaiter().GetResult();$null=$e.GetAwaiter().GetResult()
        $text=[Text.Encoding]::UTF8.GetString($out.ToArray())+[Environment]::NewLine+[Text.Encoding]::UTF8.GetString($err.ToArray())
        [IO.File]::WriteAllText($Log,$text,$utf8)
        if($timeout -or $p.ExitCode -ne 0){Get-Content -LiteralPath $Log -Tail 20|Out-Host;throw "Maven failed or timed out. See $Log"}
    }finally{$p.Dispose();$out.Dispose();$err.Dispose()}
}
try{
 $manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8
 $hashRows=@(Get-ChildItem -LiteralPath $experiment -Recurse -File|ForEach-Object{[pscustomobject]@{path=$_.FullName.Substring($experiment.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}})
 $hashRows|Export-Csv -LiteralPath (Join-Path $batch "input-source-hashes.csv") -NoTypeInformation -Encoding utf8
 Copy-Item -LiteralPath $PSCommandPath -Destination $batch
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot "patch-metadata.json") -Destination $batch
 Write-Host "Compiling: $experiment"
 Invoke-MavenLog @("--batch-mode","-Dstyle.color=never","compile") (Join-Path $logs "compile.log")
 $cp=(Join-Path $experiment "target\classes")+";"+$cloudsim
 $manifest.status="VERIFYING"
 Write-Host "Checking configuration, exact cases and cross-platform takeover..."
 Invoke-Logged $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.VerificationMain") (Join-Path $logs "verification.log")
 Invoke-Logged $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.FinalCheckMain") (Join-Path $logs "final-checks.log")
 $qa=Join-Path $experiment "qa-classes";New-Item -ItemType Directory -Path $qa|Out-Null
 $continuous=Join-Path $experiment "ContinuousCheck.java"
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot "验证证据\连续演示检查.java.txt") -Destination $continuous
 Invoke-Logged $javac @("-encoding","UTF-8","-cp",$cp,"-d",$qa,$continuous) (Join-Path $logs "test-compile.log")
 Invoke-Logged $java @("-Dfile.encoding=UTF-8","-cp",($cp+";"+$qa),"ContinuousCheck") (Join-Path $logs "continuous.log")
 Copy-Item -LiteralPath (Join-Path $experiment "restored-online-check-results.json") -Destination (Join-Path $report "continuous-check-results.json")
 Write-Host "Checking actual Java HTTP API and UI rendering..."
 Invoke-Logged $PythonExe @((Join-Path $PSScriptRoot "check-ui-api.py"),"--java",$java,"--classpath",$cp,"--project",$experiment,"--toolkit",$PSScriptRoot,"--node",$NodeExe,"--out",$report) (Join-Path $logs "ui-api.log")
 if($Mode -ne "Verify"){
  $manifest.status="STUDY_RUNNING";$manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8
  Write-Host "Running 180 paired scenarios, 7560 measurements, plus warmups..."
  Invoke-Logged $java @("-Dfile.encoding=UTF-8","-cp",$cp,"org.example.iiot.StudyMain","3") (Join-Path $logs "study.log")
 }
 [IO.File]::WriteAllText((Join-Path $report "environment.json"),'{"scope":"SIMULATION_ONLY","real_swarm_validation":"NOT_RUN","real_vxworks_validation":"NOT_RUN","reason":"User confirmed no real platform environment; current acceptance is local code and simulation."}',[Text.UTF8Encoding]::new($false))
 Invoke-Logged $PythonExe @((Join-Path $PSScriptRoot "summarize_report.py"),"--project",$experiment,"--out",$report) (Join-Path $logs "report.log")
 if(Test-Path -LiteralPath (Join-Path $report "aggregate.csv")){
  & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File (Join-Path $PSScriptRoot "build-final-figures.ps1") -ReportDir $report
  if($LASTEXITCODE -ne 0){throw "Figure generation failed; all raw results preserved"}
 }
 $manifest.status="COMPLETE"
 Write-Host "COMPLETE"
 Write-Host "REPORT: $(Join-Path $report 'report.html')"
 Write-Host "RAW STUDY: $(Join-Path $experiment 'study')"
}catch{$manifest.status="FAILED";$manifest.failure=$_.Exception.Message;throw}
finally{$manifest.finished_at=(Get-Date).ToString("o");$manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8}
