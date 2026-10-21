[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [int[]]$ChainCounts = @(1,2,3,4,5,6,7,8),
    [int[]]$BeamWidths = @(1,4,16,64,256),
    [ValidateRange(1,30)][int]$Repetitions = 1,
    [ValidateRange(10,3600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = "Stop"
if (!$ProjectRoot) {
    $ProjectRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "simulation"
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot "pom.xml"))) {
    throw "pom.xml not found: $ProjectRoot"
}
if (!$ChainCounts.Count -or @($ChainCounts | Where-Object { $_ -lt 1 -or $_ -gt 100 }).Count) {
    throw "ChainCounts must contain integers from 1 to 100."
}
$ChainCounts = @($ChainCounts | Sort-Object -Unique)
if (!$BeamWidths.Count -or @($BeamWidths | Where-Object { $_ -lt 1 -or $_ -gt 4096 }).Count) {
    throw "BeamWidths must contain integers from 1 to 4096."
}
$BeamWidths = @($BeamWidths | Sort-Object -Unique)
& (Join-Path $PSScriptRoot "prepare-beam-width.ps1") -ProjectRoot $ProjectRoot
$maven = (Get-Command mvn -ErrorAction Stop).Source
$windowsPs = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (!(Test-Path -LiteralPath $windowsPs)) { throw "Windows PowerShell is required for charts." }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = "$stamp-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$batchDir = Join-Path $ProjectRoot "results\beam-study-$runId"
$logsDir = Join-Path $batchDir "logs"
$rawDir = Join-Path $batchDir "raw"
$snapshotDir = Join-Path $batchDir "snapshot"
New-Item -ItemType Directory -Path $logsDir,$rawDir,$snapshotDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($true)

function Decode-NativeOutput {
    param([byte[]]$Bytes)
    try {
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        return $strictUtf8.GetString($Bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        # Maven/Jansi may use the Windows ANSI code page even when Java file.encoding is UTF-8.
        $codePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
        return [System.Text.Encoding]::GetEncoding($codePage).GetString($Bytes)
    }
}

function Invoke-LoggedMaven {
    param([string[]]$MavenArguments, [string]$LogPath)
    $quoted = @($MavenArguments | ForEach-Object { '"' + $_ + '"' })
    $command = '"' + $maven + '" ' + ($quoted -join " ")
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /s /c "' + $command + '"'
    $info.WorkingDirectory = $ProjectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables["MAVEN_OPTS"] = (
        $env:MAVEN_OPTS + " -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8"
    ).Trim()
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $stdoutBytes = New-Object System.IO.MemoryStream
    $stderrBytes = New-Object System.IO.MemoryStream
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($stdoutBytes)
        $stderr = $process.StandardError.BaseStream.CopyToAsync($stderrBytes)
        $timedOut = !$process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            Write-Warning "Timeout: stopping this run's process tree, PID $($process.Id)."
            & "$env:WINDIR\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
            $process.WaitForExit()
        }
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        $text = (Decode-NativeOutput $stdoutBytes.ToArray()) + [Environment]::NewLine + (Decode-NativeOutput $stderrBytes.ToArray())
        [System.IO.File]::WriteAllText($LogPath, $text, $utf8)
        if ($timedOut) { throw "Run exceeded $TimeoutSeconds seconds. See: $LogPath" }
        if ($process.ExitCode -ne 0) {
            Get-Content -LiteralPath $LogPath -Tail 25 | Out-Host
            throw "Maven failed with exit code $($process.ExitCode). See: $LogPath"
        }
        return $text
    }
    finally { $process.Dispose(); $stdoutBytes.Dispose(); $stderrBytes.Dispose() }
}
function Read-Number([object]$Value) {
    return [double]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
}

$expected = $ChainCounts.Count * $BeamWidths.Count * $Repetitions
$manifest = [ordered]@{
    run_id = $runId
    started_at = (Get-Date).ToString("o")
    project_root = $ProjectRoot
    status = "RUNNING"
    scenario = "pressure"
    chain_counts = $ChainCounts
    algorithm = "beam_search"
    repetitions = $Repetitions
    beam_widths = $BeamWidths
    metrics_discovery = "filesystem delta, no decoded console paths"
    log_decode = "strict UTF-8, falling back to Windows culture ANSI code page"
    expected_runs = $expected
    timeout_seconds_per_process = $TimeoutSeconds
    timing_protocol = "one fresh Maven/JVM process per case; planner-only timer; no warm-up exclusion"
    note = "Beam-width study on the fixed pressure nodes; same scarcity ordering and state ranking."
}
$manifestPath = Join-Path $batchDir "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
try {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "src\main\java") -Destination $snapshotDir -Recurse
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "pom.xml") -Destination $snapshotDir
    Copy-Item -LiteralPath $PSCommandPath -Destination $snapshotDir
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "build-beam-report.ps1") -Destination $snapshotDir
    foreach ($supportName in @("prepare-beam-width.ps1","patch-metadata.json")) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $supportName) -Destination $snapshotDir
    }
    Get-ChildItem -LiteralPath $snapshotDir -Recurse -File |
        ForEach-Object {
            [pscustomobject]@{
                relative_path = $_.FullName.Substring($snapshotDir.Length + 1)
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } | Export-Csv -LiteralPath (Join-Path $batchDir "source-hashes.csv") -NoTypeInformation -Encoding utf8
    $versionText = Invoke-LoggedMaven -MavenArguments @("--version") -LogPath (Join-Path $logsDir "environment.log")
    $manifest.maven_version_output = $versionText.Trim()
    Write-Host "Compiling once. Output: $batchDir"
    $null = Invoke-LoggedMaven -MavenArguments @("--batch-mode","-Dstyle.color=never","compile") -LogPath (Join-Path $logsDir "compile.log")
    $allRows = @()
    $index = 0
    foreach ($chains in $ChainCounts) {
        foreach ($repeat in 1..$Repetitions) {
            $offset = ($chains + $repeat - 2) % $BeamWidths.Count
            foreach ($position in 0..($BeamWidths.Count - 1)) {
                $width = $BeamWidths[($position + $offset) % $BeamWidths.Count]
                $index++
                $caseId = "c{0:D2}-w{1:D4}-r{2:D2}" -f $chains,$width,$repeat
                Write-Host ("[{0}/{1}] {2}" -f $index,$expected,$caseId)
                $logPath = Join-Path $logsDir "$caseId.log"
                $resultsRoot = Join-Path $ProjectRoot "results"
                $beforeNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                Get-ChildItem -LiteralPath $resultsRoot -Filter "pressure-beam_search-*.csv" -File |
                    ForEach-Object { [void]$beforeNames.Add($_.Name) }
                $output = Invoke-LoggedMaven -MavenArguments @(
                    "--batch-mode","-Dstyle.color=never","exec:java",
                    "-Dexec.mainClass=org.example.iiot.SimulationMain",
                    "-Dexec.args=beam_search pressure $chains $width"
                ) -LogPath $logPath
                $widthLines = @([regex]::Matches($output, '(?m)^Beam width: ([0-9]+)\r?$'))
                if ($widthLines.Count -ne 1 -or [int]$widthLines[0].Groups[1].Value -ne $width) {
                    throw "The Java program did not confirm requested beam width $width. See: $logPath"
                }
                $created = @(Get-ChildItem -LiteralPath $resultsRoot -Filter "pressure-beam_search-*.csv" -File |
                    Where-Object { !$beforeNames.Contains($_.Name) })
                if ($created.Count -ne 1) { throw "Expected one new metrics CSV: $caseId" }
                $csvPath = $created[0].FullName
                $records = @(Import-Csv -LiteralPath $csvPath -Encoding utf8)
                if ($records.Count -ne 1) { throw "Expected one metrics row: $csvPath" }
                $record = $records[0]
                $required = @("scenario","algorithm","requested","accepted","ready","workflow_requested",
                    "workflow_ready","ready_ratio","workflow_ready_ratio","deployment_sim_seconds",
                    "planner_wall_ms","cpu_reserved_ratio_all","ram_reserved_ratio_all")
                foreach ($field in $required) {
                    if ($null -eq $record.$field) { throw "Missing metric '$field': $csvPath" }
                }
                if ($record.scenario -ne "pressure" -or $record.algorithm -ne "beam_search" -or
                    [int]$record.requested -ne 4*$chains -or [int]$record.workflow_requested -ne $chains) {
                    throw "Run identity/load mismatch: $csvPath"
                }
                if ([int]$record.ready -ne [int]$record.accepted -or
                    [int]$record.ready -lt 0 -or [int]$record.ready -gt 4*$chains -or
                    [int]$record.workflow_ready -lt 0 -or [int]$record.workflow_ready -gt $chains) {
                    throw "Invalid counts: $csvPath"
                }
                foreach ($pair in @(
                    @("ready_ratio", ([double]$record.ready/(4*$chains))),
                    @("workflow_ready_ratio", ([double]$record.workflow_ready/$chains))
                )) {
                    if ([Math]::Abs((Read-Number $record.($pair[0])) - $pair[1]) -gt 0.0000001) {
                        throw "Ratio/count mismatch: $csvPath"
                    }
                }
                Copy-Item -LiteralPath $csvPath -Destination (Join-Path $rawDir "$caseId.csv")
                $row = [ordered]@{ run_id=$runId; chain_count=$chains; beam_width=$width; repeat_index=$repeat }
                foreach ($property in $record.PSObject.Properties) { $row[$property.Name] = $property.Value }
                $allRows += [pscustomobject]$row
                $allRows | Export-Csv -LiteralPath (Join-Path $batchDir "runs.csv") -NoTypeInformation -Encoding utf8
            }
        }
    }
    if ($allRows.Count -ne $expected) { throw "Incomplete experiment matrix." }
    $manifest.status = "SIMULATIONS_COMPLETE"
    $manifest.completed_runs = $allRows.Count
    $manifest.finished_at = (Get-Date).ToString("o")
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Write-Host "Generating charts and report..."
    & $windowsPs -NoProfile -File (Join-Path $PSScriptRoot "build-beam-report.ps1") -BatchDir $batchDir
    if ($LASTEXITCODE -ne 0) { throw "Report failed. runs.csv and logs are preserved in $batchDir" }
    $manifest.status = "COMPLETE"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Write-Host ""
    Write-Host "COMPLETE: $index/$expected runs"
    Write-Host "REPORT: $(Join-Path $batchDir 'report.html')"
    Write-Host "SUMMARY: $(Join-Path $batchDir 'summary.csv')"
}
catch {
    $manifest.status = "FAILED"
    $manifest.failure = $_.Exception.Message
    $manifest.finished_at = (Get-Date).ToString("o")
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    throw
}

