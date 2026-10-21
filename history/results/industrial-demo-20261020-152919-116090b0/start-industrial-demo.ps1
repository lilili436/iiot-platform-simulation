[CmdletBinding()]
param([string]$ProjectRoot="",[ValidateRange(1024,65535)][int]$Port=8765,[switch]$VerifyOnly)
$ErrorActionPreference="Stop"
if(!$ProjectRoot){$ProjectRoot=Join-Path (Split-Path $PSScriptRoot -Parent) "simulation"}
$ProjectRoot=(Resolve-Path -LiteralPath $ProjectRoot).Path
$stamp=(Get-Date -Format "yyyyMMdd-HHmmss")+"-"+[guid]::NewGuid().ToString("N").Substring(0,8)
$kind=if($VerifyOnly){"configuration-check"}else{"industrial-demo"}
$batch=Join-Path $ProjectRoot "results\$kind-$stamp"
$logs=Join-Path $batch "logs"
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$experiment=Join-Path $batch "project"
& (Join-Path $PSScriptRoot "prepare-workbench.ps1") -SourceProjectRoot $ProjectRoot -DestinationRoot $experiment
$maven=(Get-Command mvn -ErrorAction Stop).Source
$manifest=[ordered]@{run_id=$stamp;kind=$kind;status="PREPARING";source_project=$ProjectRoot;experiment_project=$experiment;port=$Port;started_at=(Get-Date).ToString("o");scope="Synthetic declarations and process data; fixed-order exact verification; localhost demo"}
$manifestPath=Join-Path $batch "manifest.json"
$manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding utf8
$utf8=New-Object Text.UTF8Encoding($true)
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
    $hashes=@(Get-ChildItem -LiteralPath $experiment -Recurse -File|ForEach-Object{
        [pscustomobject]@{path=$_.FullName.Substring($experiment.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $hashes|Export-Csv -LiteralPath (Join-Path $batch "source-hashes.csv") -NoTypeInformation -Encoding utf8
    Copy-Item -LiteralPath $PSCommandPath -Destination $batch
    foreach($name in @("prepare-workbench.ps1","patch-metadata.json","build-workbench-report.ps1")){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $batch
    }
    Write-Host "Compiling isolated workbench: $experiment"
    Invoke-MavenLog @("--batch-mode","-Dstyle.color=never","compile") (Join-Path $logs "compile.log")
    if($VerifyOnly){
        $manifest.status="VERIFYING"
        Invoke-MavenLog @("--batch-mode","-Dstyle.color=never","exec:java","-Dexec.mainClass=org.example.iiot.VerificationMain") (Join-Path $logs "verification.log")
        & (Join-Path $PSScriptRoot "build-workbench-report.ps1") -BatchDir $batch
        $manifest.status="COMPLETE"
        Write-Host "COMPLETE: configuration, exact checks and 24 simulation runs"
    }else{
        $manifest.status="RUNNING"
        $manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-Host "Open http://127.0.0.1:$Port after the INDUSTRIAL DEMO line appears."
        Write-Host "Keep this terminal open. Ctrl+C stops the demo. SESSION: $batch"
        Push-Location -LiteralPath $experiment
        $oldMavenOpts=$env:MAVEN_OPTS
        try{
            $env:MAVEN_OPTS=($oldMavenOpts+" -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8").Trim()
            & $maven "--batch-mode" "-Dstyle.color=never" "exec:java" "-Dexec.mainClass=org.example.iiot.demo.DemoServer" "-Dexec.args=$Port"
            if($LASTEXITCODE -ne 0){throw "Demo process failed; if the port is occupied, use -Port 8766"}
            $manifest.status="STOPPED"
        }finally{$env:MAVEN_OPTS=$oldMavenOpts;Pop-Location}
    }
}catch{
    $manifest.status="FAILED";$manifest.failure=$_.Exception.Message;throw
}finally{
    $manifest.finished_at=(Get-Date).ToString("o")
    $manifest|ConvertTo-Json|Set-Content -LiteralPath $manifestPath -Encoding utf8
}
