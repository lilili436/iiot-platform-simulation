$ErrorActionPreference = "Stop"

Push-Location $PSScriptRoot

try {
    $maven = (Get-Command mvn -ErrorAction Stop).Source

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)

    $batchDir = Join-Path $PSScriptRoot "results\comparison-$stamp-$suffix"
    $logsDir = Join-Path $batchDir "logs"
    $rawDir = Join-Path $batchDir "raw"

    New-Item -ItemType Directory -Path $logsDir, $rawDir | Out-Null

    Write-Host "Compiling project..."
    $compileLog = Join-Path $logsDir "compile.log"

    & $maven --batch-mode "-Dstyle.color=never" compile 2>&1 |
        Out-File -LiteralPath $compileLog -Encoding utf8

    if ($LASTEXITCODE -ne 0) {
        Get-Content -LiteralPath $compileLog -Tail 30
        throw "Compilation failed. See: $compileLog"
    }

    $rows = @()
    $scenarios = @("demo", "pressure")
    $algorithms = @(
        "first_fit",
        "round_robin",
        "best_fit",
        "beam_search"
    )

    foreach ($scenario in $scenarios) {
        foreach ($algorithm in $algorithms) {
            Write-Host "Running: $scenario / $algorithm"

            $logPath = Join-Path $logsDir "$scenario-$algorithm.log"

            & $maven --batch-mode "-Dstyle.color=never" exec:java `
                "-Dexec.mainClass=org.example.iiot.SimulationMain" `
                "-Dexec.args=$algorithm $scenario" 2>&1 |
                Out-File -LiteralPath $logPath -Encoding utf8

            if ($LASTEXITCODE -ne 0) {
                Get-Content -LiteralPath $logPath -Tail 30
                throw "Run failed. See: $logPath"
            }

            $saved = @(Get-Content -LiteralPath $logPath |
                Where-Object { $_.StartsWith("CSV saved: ") })

            if ($saved.Count -ne 1) {
                throw "Expected one CSV path. See: $logPath"
            }

            $csvPath = $saved[0].Substring("CSV saved: ".Length).Trim()
            $records = @(Import-Csv -LiteralPath $csvPath -Encoding utf8)

            if ($records.Count -ne 1) {
                throw "Expected one metrics row: $csvPath"
            }

            $record = $records[0]

            if ($record.scenario -ne $scenario -or
                $record.algorithm -ne $algorithm -or
                $null -eq $record.workflow_ready_ratio) {
                throw "Unexpected metrics schema or run identity: $csvPath"
            }

            Copy-Item -LiteralPath $csvPath -Destination (
                Join-Path $rawDir "$scenario-$algorithm.csv"
            )

            $rows += $record
        }
    }

    $summaryPath = Join-Path $batchDir "comparison.csv"

    $rows | Export-Csv -LiteralPath $summaryPath `
        -NoTypeInformation -Encoding utf8

    Write-Host ""

    $rows | ForEach-Object {
        [pscustomobject]@{
            Scenario  = $_.scenario
            Algorithm = $_.algorithm
            Services  = "$($_.ready)/$($_.requested)"
            Chains    = "$($_.workflow_ready)/$($_.workflow_requested)"
            Seconds   = $_.deployment_sim_seconds
            PlanMs    = $_.planner_wall_ms
        }
    } | Format-Table -AutoSize | Out-Host

    Write-Host "Summary saved: $summaryPath"
    Write-Host "Logs saved: $logsDir"
}
finally {
    Pop-Location
}