[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BatchDir)
$ErrorActionPreference = "Stop"
$BatchDir = (Resolve-Path -LiteralPath $BatchDir).Path
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$inv = [Globalization.CultureInfo]::InvariantCulture
$nl = [Environment]::NewLine
function Number($Value) { return [double]::Parse([string]$Value, $inv) }
function Fmt($Value, [int]$Digits=2) { return ([double]$Value).ToString("F$Digits",$inv) }
function Escape($Value) { return [System.Net.WebUtility]::HtmlEncode([string]$Value) }
$manifest = Get-Content -LiteralPath (Join-Path $BatchDir "manifest.json") -Raw -Encoding utf8 | ConvertFrom-Json
$rows = @(Import-Csv -LiteralPath (Join-Path $BatchDir "runs.csv") -Encoding utf8)
if ($rows.Count -ne $manifest.expected_runs) { throw "Run count does not match manifest." }
$algorithms = @("first_fit","round_robin","best_fit","beam_search")
$metrics = @("ready","workflow_ready","ready_ratio","workflow_ready_ratio",
    "deployment_sim_seconds","cpu_reserved_ratio_all","ram_reserved_ratio_all","planner_wall_ms")
$summary = @()
$variations = @()
foreach ($chains in $manifest.chain_counts) {
    foreach ($algorithm in $algorithms) {
        $group = @($rows | Where-Object { [int]$_.chain_count -eq $chains -and $_.algorithm -eq $algorithm })
        if ($group.Count -ne $manifest.repetitions) { throw "Missing/duplicate case: $chains / $algorithm" }
        $item = [ordered]@{ chain_count=[int]$chains; algorithm=$algorithm; repetitions=$group.Count; requested=4*[int]$chains }
        foreach ($metric in $metrics) {
            $values = @($group | ForEach-Object { Number $_.$metric } | Sort-Object)
            $stat = $values | Measure-Object -Average -Minimum -Maximum
            $item[$metric] = $stat.Average
            if ($metric -eq "planner_wall_ms") {
                $middle = [int][Math]::Floor($values.Count / 2)
                $median = if ($values.Count % 2) { $values[$middle] } else { ($values[$middle-1]+$values[$middle])/2 }
                $item["planner_wall_ms_median"] = $median
                $item["planner_wall_ms_min"] = $stat.Minimum
                $item["planner_wall_ms_max"] = $stat.Maximum
            }
            elseif ($stat.Maximum - $stat.Minimum -gt 0.0000001) {
                $variations += "$chains / $algorithm / $metric"
            }
        }
        $summary += [pscustomobject]$item
    }
}
$summary | Export-Csv -LiteralPath (Join-Path $BatchDir "summary.csv") -NoTypeInformation -Encoding utf8
$comparisons = @()
foreach ($chains in $manifest.chain_counts) {
    $beam = $summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq "beam_search" }
    foreach ($algorithm in @("first_fit","round_robin","best_fit")) {
        $baseline = $summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq $algorithm }
        $comparable = ([Math]::Abs($beam.ready-$baseline.ready) -lt 0.0000001) -and
            ([Math]::Abs($beam.workflow_ready-$baseline.workflow_ready) -lt 0.0000001)
        $reduction = if ($comparable -and $baseline.deployment_sim_seconds -gt 0) {
            100*($baseline.deployment_sim_seconds-$beam.deployment_sim_seconds)/$baseline.deployment_sim_seconds
        } else { $null }
        $comparisons += [pscustomobject]@{
            chain_count=$chains; baseline=$algorithm
            baseline_ready=$baseline.ready; beam_ready=$beam.ready
            baseline_workflows=$baseline.workflow_ready; beam_workflows=$beam.workflow_ready
            time_comparable=$comparable; beam_time_reduction_pct=$reduction
            reason=$(if ($comparable) { "equal ready-service and complete-workflow counts" } else { "different ready counts; compare admission before time" })
        }
    }
}
$comparisons | Export-Csv -LiteralPath (Join-Path $BatchDir "time-comparisons.csv") -NoTypeInformation -Encoding utf8
$figuresDir = Join-Path $BatchDir "figures"
New-Item -ItemType Directory -Path $figuresDir -Force | Out-Null
$colors = @("#64748b","#d97706","#2563eb","#059669")
$labels = @("First Fit","Round Robin","Best Fit","Beam Search")
$markers = @("Circle","Square","Triangle","Diamond")
$chartSpecs = @(
    @("service-ready","ready_ratio","Service ready ratio","Ready services / requested services (%)",100),
    @("workflow-ready","workflow_ready_ratio","Complete workflow ready ratio","Fully ready workflows / requested workflows (%)",100),
    @("deployment-time","deployment_sim_seconds","Deployment completion time of accepted services","Simulation time (s)",1),
    @("cpu-reserved","cpu_reserved_ratio_all","CPU capacity reserved across all nodes","Reserved CPU / total CPU (%)",100),
    @("ram-reserved","ram_reserved_ratio_all","RAM capacity reserved across all nodes","Reserved RAM / total RAM (%)",100),
    @("planner-wall","planner_wall_ms_median","Planner wall time in a fresh JVM","Observed planner time, median (ms)",1)
)
foreach ($spec in $chartSpecs) {
    $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
    try {
        $chart.Width = 1440
        $chart.Height = 900
        $chart.BackColor = [System.Drawing.Color]::White
        $chart.AntiAliasing = "All"
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea("main")
        $area.AxisX.Title = "Requested workflows (4 services per workflow)"
        $area.AxisX.Interval = 1
        $area.AxisX.IntervalOffset = 0.5
        $area.AxisX.LabelStyle.Format = "0"
        $area.AxisX.Minimum = ([double]($manifest.chain_counts | Measure-Object -Minimum).Minimum) - 0.5
        $area.AxisX.Maximum = ([double]($manifest.chain_counts | Measure-Object -Maximum).Maximum) + 0.5
        $area.AxisY.Title = $spec[3]
        $area.AxisY.Minimum = 0
        if ($spec[4] -eq 100) { $area.AxisY.Maximum = 100 }
        foreach ($axis in @($area.AxisX,$area.AxisY)) {
            $axis.TitleFont = New-Object System.Drawing.Font("Arial",15)
            $axis.LabelStyle.Font = New-Object System.Drawing.Font("Arial",12)
            $axis.LineColor = [System.Drawing.ColorTranslator]::FromHtml("#94a3b8")
            $axis.MajorGrid.LineColor = [System.Drawing.ColorTranslator]::FromHtml("#e2e8f0")
        }
        $area.AxisX.MajorGrid.Enabled = $false
        $chart.ChartAreas.Add($area)
        $title = $chart.Titles.Add([string]$spec[2])
        $title.Font = New-Object System.Drawing.Font("Arial",19,[System.Drawing.FontStyle]::Bold)
        $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend("algorithms")
        $legend.Docking = "Bottom"
        $legend.Font = New-Object System.Drawing.Font("Arial",13)
        $chart.Legends.Add($legend)
        for ($a=0; $a -lt $algorithms.Count; $a++) {
            $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series($labels[$a])
            $series.ChartType = "Line"
            $series.BorderWidth = 3
            $series.Color = [System.Drawing.ColorTranslator]::FromHtml($colors[$a])
            $series.MarkerStyle = $markers[$a]
            $series.MarkerSize = 10
            foreach ($entry in @($summary | Where-Object algorithm -eq $algorithms[$a] | Sort-Object chain_count)) {
                [void]$series.Points.AddXY([double]$entry.chain_count, ([double]$entry.($spec[1]) * [double]$spec[4]))
            }
            $chart.Series.Add($series)
        }
        $chart.SaveImage((Join-Path $figuresDir ($spec[0]+".png")),
            [System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]::Png)
    }
    finally { $chart.Dispose() }
}
$maxLoad = ($manifest.chain_counts | Measure-Object -Maximum).Maximum
$largestText = @($summary | Where-Object chain_count -eq $maxLoad | ForEach-Object {
    "$($_.algorithm)：服务 $(Fmt $_.ready 0)/$($_.requested)，完整链 $(Fmt $_.workflow_ready 0)/$($_.chain_count)，部署 $(Fmt $_.deployment_sim_seconds 3) s"
})
$tableRows = @()
$mdRows = @()
foreach ($entry in $summary) {
    $cells = @($entry.chain_count,$entry.algorithm,
        ("$(Fmt $entry.ready 0)/$($entry.requested)"),("$(Fmt $entry.workflow_ready 0)/$($entry.chain_count)"),
        ("$(Fmt ($entry.ready_ratio*100))%"),("$(Fmt ($entry.workflow_ready_ratio*100))%"),
        (Fmt $entry.deployment_sim_seconds 3),("$(Fmt ($entry.cpu_reserved_ratio_all*100))%"),
        ("$(Fmt ($entry.ram_reserved_ratio_all*100))%"),(Fmt $entry.planner_wall_ms_median 3))
    $tableRows += "<tr>" + (($cells | ForEach-Object { "<td>$(Escape $_)</td>" }) -join "") + "</tr>"
    $mdRows += "| " + ($cells -join " | ") + " |"
}
$comparisonRows = @()
foreach ($entry in $comparisons) {
    $value = if ($entry.time_comparable) { "$(Fmt $entry.beam_time_reduction_pct)%" } else { "不直接比较" }
    $comparisonRows += "<tr><td>$($entry.chain_count)</td><td>$(Escape $entry.baseline)</td><td>$value</td><td>$(Escape $entry.reason)</td></tr>"
}
$variationText = if ($variations.Count) {
    "重复运行中发现非计时指标变化：$($variations -join '; ')。应先检查确定性，暂不据此推断稳定优势。"
} elseif ($manifest.repetitions -gt 1) {
    "已执行的重复运行中，服务数、完整链数、部署时间及资源预留指标一致。"
} else { "每个组合仅运行一次，尚未检验重复运行的一致性。" }
$definition = "本轮固定 pressure 场景的六个节点，仅改变请求业务链数量；每条链为 collect → preprocess → detect → alert。各系统版本的资源需求、包大小和启动时间沿用 Java 代码中的设定，Beam Search 束宽为 64。普通指标按重复运行求均值，规划耗时图取中位数，最小值和最大值保存在 summary.csv。资源预留比例表示模型分配容量，不是实测 CPU 或 RAM 利用率。"
$limits = "这些结果描述固定合成场景下的离散事件部署仿真。当前只检查操作系统与 CPU/RAM 容量约束，未验证真实容器、RTP、驱动/API 或安全策略兼容性。部署时间只覆盖被接纳的服务，应结合服务和完整业务链就绪数量解释；完整链数量相同也不代表链的身份相同。各组合启动独立 JVM，没有排除 JIT/预热影响，规划耗时仅作描述；重复同一确定性输入不能代替随机场景或独立样本，报告不作显著性或普遍最优结论。"
$figureHtml = @($chartSpecs | ForEach-Object {
    "<figure><img src='figures/$($_[0]).png' alt='$(Escape $_[2])'><figcaption>$(Escape $_[2])</figcaption></figure>"
})
$html = @"
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>异构微服务部署负载实验</title>
<style>
body{font:16px/1.75 "Microsoft YaHei",Arial,sans-serif;color:#182338;background:#f3f6fa;margin:0}
main{max-width:1200px;margin:32px auto;padding:32px;background:white;border-radius:12px}
h1{font-size:29px;margin-top:0}h2{font-size:21px;margin-top:32px}.meta{color:#526175}
.note{padding:15px 20px;background:#eff6ff;border-left:4px solid #2563eb}.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px;white-space:nowrap}
th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #dbe3ee}th{background:#edf2f8}
tr:nth-child(even){background:#f8fafc}figure{margin:24px 0;padding:8px;border:1px solid #e2e8f0}
img{display:block;width:100%;height:auto}figcaption{color:#526175;padding:8px 12px}a{color:#1d4ed8}
</style></head><body><main><h1>异构微服务部署负载实验</h1>
<p class="meta">批次：$(Escape $manifest.run_id) · $($rows.Count) 次运行 · 每组 $($manifest.repetitions) 次</p>
<div class="note">$(Escape $definition)</div><h2>最大负载下的结果：$maxLoad 条业务链</h2>
<ul>$(($largestText | ForEach-Object { "<li>$(Escape $_)</li>" }) -join "")</ul><p>$(Escape $variationText)</p>
<h2>完整结果表</h2><div class="scroll"><table><thead><tr>
<th>链数</th><th>算法</th><th>就绪服务</th><th>完整链</th><th>服务就绪率</th><th>完整链就绪率</th>
<th>部署时间/s</th><th>CPU预留</th><th>RAM预留</th><th>规划耗时中位数/ms</th></tr></thead>
<tbody>$($tableRows -join $nl)</tbody></table></div><h2>负载变化曲线</h2>$($figureHtml -join $nl)
<h2>相同就绪数量下的时间比较</h2>
<p>正值表示 Beam Search 比基线用时更少，负值表示用时更多。仅当就绪服务数和完整链数均相同时计算，这不是对实际业务价值完全等价的证明。</p>
<div class="scroll"><table><thead><tr><th>链数</th><th>基线</th><th>Beam时间缩短比例</th><th>比较条件</th></tr></thead>
<tbody>$($comparisonRows -join $nl)</tbody></table></div><h2>指标解释和适用范围</h2><p>$(Escape $limits)</p>
<h2>数据与复现</h2><p><a href="runs.csv">逐次汇总</a> · <a href="summary.csv">分组汇总</a> ·
<a href="time-comparisons.csv">条件化时间比较</a> · <a href="manifest.json">配置与环境</a> ·
<a href="source-hashes.csv">源码哈希</a> · <a href="report.md">Markdown报告</a></p>
<p>原始 CSV 位于 raw/，完整日志位于 logs/，源码和脚本快照位于 snapshot/。</p></main></body></html>
"@
$md = @"
# 异构微服务部署负载实验

## Material Passport
- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: descriptive analysis
- Origin Date: $($manifest.started_at)
- Verification Status: ANALYZED
- Version Label: load-study-v1
- Evidence: runs.csv, raw/, logs/, manifest.json, source-hashes.csv

## 实验设计
$definition

## 最大负载结果
$($largestText -join ($nl+$nl))

## 完整结果
| 链数 | 算法 | 就绪服务 | 完整链 | 服务就绪率 | 完整链就绪率 | 部署时间/s | CPU预留 | RAM预留 | 规划耗时中位数/ms |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
$($mdRows -join $nl)

## 重复运行一致性
$variationText

## 解释范围
$limits

六幅 PNG 图保存在 figures/；time-comparisons.csv 仅对相同就绪服务数量及完整链数量的条件计算时间缩短比例。所有运行均保留，未按算法表现筛选负载点。
"@
$utf8 = New-Object System.Text.UTF8Encoding($true)
[ordered]@{
    built_at = (Get-Date).ToString("o")
    report_script_sha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash
    source_runs_sha256 = (Get-FileHash -LiteralPath (Join-Path $BatchDir "runs.csv") -Algorithm SHA256).Hash
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $BatchDir "report-metadata.json") -Encoding utf8
[System.IO.File]::WriteAllText((Join-Path $BatchDir "report.html"),$html,$utf8)
[System.IO.File]::WriteAllText((Join-Path $BatchDir "report.md"),$md,$utf8)
$summary | Select-Object chain_count,algorithm,ready,workflow_ready,deployment_sim_seconds | Format-Table -AutoSize | Out-Host
Write-Host "Created six PNG figures, summary.csv, time-comparisons.csv, report.html and report.md."
