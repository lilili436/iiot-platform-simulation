[CmdletBinding()]
param(
    [string]$ProjectRoot = "",
    [int[]]$ChainCounts = @(3,6),
    [ValidateRange(1,4096)][int]$BeamWidth = 64,
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
$settings = @()
foreach ($profile in @("uniform","mixed")) {
    foreach ($mode in @("base","full")) {
        foreach ($algorithmName in @("first_fit","round_robin","best_fit","beam_search")) {
            $settings += [pscustomobject]@{ profile=$profile; mode=$mode; algorithm=$algorithmName }
        }
    }
}
$sourceProjectRoot = $ProjectRoot
$maven = (Get-Command mvn -ErrorAction Stop).Source
$windowsPs = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (!(Test-Path -LiteralPath $windowsPs)) { throw "Windows PowerShell is required for charts." }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = "$stamp-$([guid]::NewGuid().ToString('N').Substring(0,8))"
$batchDir = Join-Path $ProjectRoot "results\platform-study-$runId"
$logsDir = Join-Path $batchDir "logs"
$rawDir = Join-Path $batchDir "raw"
$auditDir = Join-Path $batchDir "audits"
$snapshotDir = Join-Path $batchDir "snapshot"
New-Item -ItemType Directory -Path $logsDir,$rawDir,$snapshotDir,$auditDir | Out-Null
$experimentProjectRoot = Join-Path $batchDir "project"
& (Join-Path $PSScriptRoot "prepare-platform-project.ps1") -SourceProjectRoot $sourceProjectRoot -DestinationRoot $experimentProjectRoot
$ProjectRoot = $experimentProjectRoot
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "results") -Force | Out-Null
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

$expected = $ChainCounts.Count * $settings.Count * $Repetitions
$manifest = [ordered]@{
    run_id = $runId
    started_at = (Get-Date).ToString("o")
    source_project_root = $sourceProjectRoot
    project_root = $ProjectRoot
    status = "RUNNING"
    scenario = "pressure"
    chain_counts = $ChainCounts
    settings = $settings
    repetitions = $Repetitions
    beam_width = $BeamWidth
    metrics_discovery = "filesystem delta, no decoded console paths"
    log_decode = "strict UTF-8, falling back to Windows culture ANSI code page"
    expected_runs = $expected
    timeout_seconds_per_process = $TimeoutSeconds
    timing_protocol = "one fresh Maven/JVM process per case; planner-only timer; no warm-up exclusion"
    declaration_version = "synthetic-platform-v1"
    note = "Declared capabilities only; no host probing, ABI tests or cryptographic verification. Chain input, fixed nodes/resources and original planner scoring."
}
$manifestPath = Join-Path $batchDir "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding utf8
try {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "src\main\java") -Destination $snapshotDir -Recurse
    Copy-Item -LiteralPath (Join-Path $ProjectRoot "pom.xml") -Destination $snapshotDir
    Copy-Item -LiteralPath $PSCommandPath -Destination $snapshotDir
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "build-platform-report.ps1") -Destination $snapshotDir
    foreach ($supportName in @("prepare-platform-project.ps1","verify-platform-output.ps1","run-policy-checks.ps1","PlatformPolicyCheck.java.txt","patch-metadata.json")) {
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
    $checkOutput = & (Join-Path $PSScriptRoot "run-policy-checks.ps1") -ExperimentProjectRoot $ProjectRoot | Out-String
    [IO.File]::WriteAllText((Join-Path $logsDir "policy-checks.log"),$checkOutput,$utf8)
    Write-Host $checkOutput.Trim()
    $allRows = @()
    $index = 0
    foreach ($chains in $ChainCounts) {
        foreach ($repeat in 1..$Repetitions) {
            # Rotate execution order across conditions to avoid always placing one algorithm first.
            $offset = ($chains + $repeat - 2) % $settings.Count
            foreach ($position in 0..($settings.Count - 1)) {
                $setting = $settings[($position + $offset) % $settings.Count]
                $profile = $setting.profile
                $mode = $setting.mode
                $algorithm = $setting.algorithm
                $widthArgument = if ($algorithm -eq "beam_search") { [string]$BeamWidth } else { "-" }
                $index++
                $caseId = "c{0:D2}-{1}-r{2:D2}" -f $chains,("$profile-$mode-$algorithm"),$repeat
                Write-Host ("[{0}/{1}] {2}" -f $index,$expected,$caseId)
                $logPath = Join-Path $logsDir "$caseId.log"
                # Never reconstruct a filesystem path from decoded console text.
                $resultsRoot = Join-Path $ProjectRoot "results"
                $filePattern = "pressure-$algorithm-*.csv"
                $beforeNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                Get-ChildItem -LiteralPath $resultsRoot -Filter $filePattern -File |
                    ForEach-Object { [void]$beforeNames.Add($_.Name) }
                $auditPattern = "platform-audit-$algorithm-*.csv"
                $beforeAudits = @(Get-ChildItem -LiteralPath $resultsRoot -Filter $auditPattern -File | Select-Object -ExpandProperty Name)
                $output = Invoke-LoggedMaven -MavenArguments @(
                    "--batch-mode","-Dstyle.color=never","exec:java",
                    "-Dexec.mainClass=org.example.iiot.SimulationMain",
                    "-Dexec.args=$algorithm pressure $chains $widthArgument $mode $profile"
                ) -LogPath $logPath
                foreach ($confirmation in @("Capability profile: $profile","Compatibility mode: $mode")) {
                    if ([regex]::Matches($output,("(?m)^"+[regex]::Escape($confirmation)+"\r?$")).Count -ne 1) {
                        throw "Configuration not confirmed in $logPath"
                    }
                }
                $newAudits = @(Get-ChildItem -LiteralPath $resultsRoot -Filter $auditPattern -File |
                    Where-Object { $_.Name -notin $beforeAudits -and $_.Name -notmatch '\.(assignments|candidates)\.csv$' })
                if ($newAudits.Count -ne 1) { throw "Expected exactly one new audit summary." }
                $auditRows = @(Import-Csv -LiteralPath $newAudits[0].FullName -Encoding utf8)
                if ($auditRows.Count -ne 1) { throw "Expected one audit summary row." }
                $audit = $auditRows[0]
                $created = @(Get-ChildItem -LiteralPath $resultsRoot -Filter $filePattern -File |
                    Where-Object { !$beforeNames.Contains($_.Name) })
                if ($created.Count -ne 1) {
                    throw "Expected exactly one new metrics CSV for $caseId; found $($created.Count). Avoid concurrent runs in the same project. See: $logPath"
                }
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
                if ($record.scenario -ne "pressure" -or $record.algorithm -ne $algorithm -or
                    [int]$record.requested -ne 4*$chains -or [int]$record.workflow_requested -ne $chains) {
                    throw "Run identity/load mismatch: $csvPath"
                }
                if ([int]$record.ready -ne [int]$record.accepted -or
                    [int]$record.ready -lt 0 -or [int]$record.ready -gt [int]$record.requested -or
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
                foreach ($field in @("audited_assignments","violating_assignments","locally_compliant_ready","compliant_ready",
                    "dependency_blocked_ready","compliant_workflows","total_workflows","compliant_ready_ratio","compliant_workflow_ratio",
                    "arch_mismatch_count","runtime_missing_count","api_missing_count","driver_missing_count","security_mismatch_count")) {
                    if ($null -eq $audit.$field) { throw "Missing audit field: $field" }
                    $number = Read-Number $audit.$field
                    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) { throw "Invalid audit value." }
                }
                if ($audit.capability_profile -ne $profile -or $audit.compatibility_mode -ne $mode -or
                    [int]$audit.audited_assignments -ne [int]$record.accepted -or [int]$audit.total_workflows -ne $chains -or
                    [int]$audit.compliant_ready -gt [int]$record.ready -or
                    [int]$audit.compliant_workflows -gt [int]$record.workflow_ready -or
                    [int]$audit.violating_assignments -gt [int]$record.accepted -or
                    [int]$audit.locally_compliant_ready -ne ([int]$record.ready-[int]$audit.violating_assignments) -or
                    [int]$audit.dependency_blocked_ready -ne ([int]$audit.locally_compliant_ready-[int]$audit.compliant_ready)) {
                    throw "Audit identity or counts mismatch."
                }
                if ([Math]::Abs((Read-Number $audit.compliant_ready_ratio)-[double]$audit.compliant_ready/(4*$chains)) -gt 0.0000001 -or
                    [Math]::Abs((Read-Number $audit.compliant_workflow_ratio)-[double]$audit.compliant_workflows/$chains) -gt 0.0000001) {
                    throw "Audit ratio mismatch."
                }
                if (($mode -eq "full" -or $profile -eq "uniform") -and
                    ([int]$audit.violating_assignments -ne 0 -or [int]$audit.compliant_ready -ne [int]$record.ready)) {
                    throw "Capability gate/control invariant failed."
                }
                Copy-Item -LiteralPath $newAudits[0].FullName -Destination (Join-Path $auditDir "$caseId.csv")
                foreach ($kind in @("assignments","candidates")) {
                    $sidecar = [IO.Path]::ChangeExtension($newAudits[0].FullName,"$kind.csv")
                    if (!(Test-Path -LiteralPath $sidecar)) { throw "Missing audit sidecar: $sidecar" }
                    Copy-Item -LiteralPath $sidecar -Destination (Join-Path $auditDir "$caseId.$kind.csv")
                }
                $row = [ordered]@{
                    run_id=$runId; chain_count=$chains; beam_width=$BeamWidth; repeat_index=$repeat
                }
                foreach ($property in $audit.PSObject.Properties) { $row[$property.Name] = $property.Value }
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
    & (Join-Path $PSScriptRoot "verify-platform-output.ps1") -BatchDir $batchDir
    Write-Host "Generating charts and report..."
    & $windowsPs -NoProfile -File (Join-Path $PSScriptRoot "build-platform-report.ps1") -BatchDir $batchDir
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

