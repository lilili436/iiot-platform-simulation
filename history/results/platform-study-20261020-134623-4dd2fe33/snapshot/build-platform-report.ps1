[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BatchDir)
$ErrorActionPreference = "Stop"
$BatchDir = (Resolve-Path -LiteralPath $BatchDir).Path
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing
$inv = [Globalization.CultureInfo]::InvariantCulture
$nl=[Environment]::NewLine
function Number($value) { return [double]::Parse([string]$value,$inv) }
function Fmt($value,[int]$digits=2) { return ([double]$value).ToString("F$digits",$inv) }
function Escape($value) { return [Net.WebUtility]::HtmlEncode([string]$value) }
$manifest = Get-Content -LiteralPath (Join-Path $BatchDir "manifest.json") -Raw -Encoding utf8 | ConvertFrom-Json
$rows = @(Import-Csv -LiteralPath (Join-Path $BatchDir "runs.csv") -Encoding utf8)
if ($rows.Count -ne $manifest.expected_runs) { throw "Incomplete experiment matrix." }
$algorithms = @("first_fit","round_robin","best_fit","beam_search")
$metrics = @("ready","workflow_ready","compliant_ready","locally_compliant_ready","dependency_blocked_ready",
    "compliant_workflows","violating_assignments","deployment_sim_seconds","planner_wall_ms",
    "cpu_reserved_ratio_all","ram_reserved_ratio_all","arch_mismatch_count","runtime_missing_count",
    "api_missing_count","driver_missing_count","security_mismatch_count")
$summary = @()
$variations = @()
foreach ($chains in $manifest.chain_counts) {
    foreach ($profile in @("uniform","mixed")) {
        foreach ($mode in @("base","full")) {
            foreach ($algorithm in $algorithms) {
                $group = @($rows | Where-Object {
                    [int]$_.chain_count -eq $chains -and $_.capability_profile -eq $profile -and
                    $_.compatibility_mode -eq $mode -and $_.algorithm -eq $algorithm
                })
                if ($group.Count -ne $manifest.repetitions) { throw "Missing or duplicate experiment cell." }
                if (@($group.repeat_index | Sort-Object -Unique).Count -ne $group.Count) { throw "Duplicate repeat identity." }
                $entry = [ordered]@{ chain_count=$chains; capability_profile=$profile; compatibility_mode=$mode;
                    algorithm=$algorithm; repetitions=$group.Count; requested=4*[int]$chains }
                foreach ($metric in $metrics) {
                    $values = @($group | ForEach-Object { Number $_.$metric } | Sort-Object)
                    $stat = $values | Measure-Object -Average -Minimum -Maximum
                    $entry[$metric]=$stat.Average
                    if ($metric -eq "planner_wall_ms") {
                        $mid=[int][Math]::Floor($values.Count/2)
                        $entry.planner_wall_ms_median = if ($values.Count%2) { $values[$mid] } else { ($values[$mid-1]+$values[$mid])/2 }
                        $entry.planner_wall_ms_min=$stat.Minimum
                        $entry.planner_wall_ms_max=$stat.Maximum
                    } elseif ($stat.Maximum-$stat.Minimum -gt 0.0000001) {
                        $variations += "$chains / $profile / $mode / $algorithm / $metric"
                    }
                }
                $summary += [pscustomobject]$entry
            }
        }
    }
}
$summary | Export-Csv -LiteralPath (Join-Path $BatchDir "summary.csv") -NoTypeInformation -Encoding utf8
$paired=@()
$controls=@()
foreach ($chains in $manifest.chain_counts) {
    foreach ($algorithm in $algorithms) {
        foreach ($profile in @("uniform","mixed")) {
            $on=$summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq $algorithm -and $_.capability_profile -eq $profile -and $_.compatibility_mode -eq "full" }
            $off=$summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq $algorithm -and $_.capability_profile -eq $profile -and $_.compatibility_mode -eq "base" }
            $paired += [pscustomobject]@{
                chain_count=$chains; capability_profile=$profile; algorithm=$algorithm
                model_ready_delta_full_minus_base=$on.ready-$off.ready
                compliant_ready_delta_full_minus_base=$on.compliant_ready-$off.compliant_ready
                compliant_workflows_delta_full_minus_base=$on.compliant_workflows-$off.compliant_workflows
                violations_delta_full_minus_base=$on.violating_assignments-$off.violating_assignments
                base_seconds=$off.deployment_sim_seconds; full_seconds=$on.deployment_sim_seconds
            }
            if ($profile -eq "uniform") {
                $match=$true
                foreach ($metric in @("ready","workflow_ready","deployment_sim_seconds","cpu_reserved_ratio_all","ram_reserved_ratio_all")) {
                    if ([Math]::Abs($on.$metric-$off.$metric) -gt 0.0000001) { $match=$false }
                }
                $controls += [pscustomobject]@{ chain_count=$chains; algorithm=$algorithm; control="uniform base vs full"; passed=$match }
                if (!$match) { throw "Uniform negative control changed core metrics." }
            }
        }
        $u=$summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq $algorithm -and $_.capability_profile -eq "uniform" -and $_.compatibility_mode -eq "base" }
        $m=$summary | Where-Object { $_.chain_count -eq $chains -and $_.algorithm -eq $algorithm -and $_.capability_profile -eq "mixed" -and $_.compatibility_mode -eq "base" }
        $match=$true
        foreach ($metric in @("ready","workflow_ready","deployment_sim_seconds","cpu_reserved_ratio_all","ram_reserved_ratio_all")) {
            if ([Math]::Abs($u.$metric-$m.$metric) -gt 0.0000001) { $match=$false }
        }
        $controls += [pscustomobject]@{ chain_count=$chains; algorithm=$algorithm; control="gate-off uniform vs mixed"; passed=$match }
        if (!$match) { throw "Disabled gate changed core simulation metrics." }
    }
}
$paired | Export-Csv -LiteralPath (Join-Path $BatchDir "paired-mode-effects.csv") -NoTypeInformation -Encoding utf8
$controls | Export-Csv -LiteralPath (Join-Path $BatchDir "control-checks.csv") -NoTypeInformation -Encoding utf8
$figDir=Join-Path $BatchDir "figures"
New-Item -ItemType Directory -Path $figDir -Force | Out-Null
$specs=@(
    @("compliant-services","compliant_ready","Dependency-closed compliant READY services"),
    @("compliant-workflows","compliant_workflows","Complete declared-compliant workflows"),
    @("violations","violating_assignments","Assignments violating declared capabilities")
)
$figures=@()
foreach ($chains in $manifest.chain_counts) {
    foreach ($spec in $specs) {
        $chart=New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        try {
            $chart.Width=1440; $chart.Height=900
            $chart.BackColor=[Drawing.Color]::White; $chart.AntiAliasing="All"
            $area=New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea("main")
            $area.AxisX.Title="Placement algorithm"
            $area.AxisX.Interval=1
            $area.AxisX.MajorGrid.Enabled=$false
            $area.AxisY.Title="Count (mean over configured repetitions)"
            $area.AxisY.Minimum=0; $area.AxisY.LabelStyle.Format="0.##"
            $area.AxisY.Maximum=if ($spec[1] -eq "compliant_workflows") { [double]$chains } else { 4*[double]$chains }
            foreach ($axis in @($area.AxisX,$area.AxisY)) {
                $axis.TitleFont=New-Object Drawing.Font("Arial",15)
                $axis.LabelStyle.Font=New-Object Drawing.Font("Arial",12)
                $axis.MajorGrid.LineColor=[Drawing.ColorTranslator]::FromHtml("#e2e8f0")
            }
            $chart.ChartAreas.Add($area)
            $title=$chart.Titles.Add("$($spec[2])$nl Mixed synthetic profile / $chains requested workflows")
            $title.Font=New-Object Drawing.Font("Arial",19,[Drawing.FontStyle]::Bold)
            $legend=New-Object System.Windows.Forms.DataVisualization.Charting.Legend("mode")
            $legend.Docking="Bottom"; $legend.Font=New-Object Drawing.Font("Arial",13)
            $chart.Legends.Add($legend)
            foreach ($mode in @("base","full")) {
                $series=New-Object System.Windows.Forms.DataVisualization.Charting.Series($mode)
                $series.LegendText=if($mode -eq "base"){"OS + CPU/RAM only"}else{"Full declared capability gate"}
                $series.ChartType="Column"; $series.IsValueShownAsLabel=$true
                $series.LabelFormat="0.##"; $series.Font=New-Object Drawing.Font("Arial",14)
                $series.Color=[Drawing.ColorTranslator]::FromHtml($(if($mode -eq "base"){"#d97706"}else{"#2563eb"}))
                foreach ($algorithm in $algorithms) {
                    $value=$summary | Where-Object { $_.chain_count -eq $chains -and $_.capability_profile -eq "mixed" -and $_.compatibility_mode -eq $mode -and $_.algorithm -eq $algorithm }
                    $pointIndex=$series.Points.AddXY([double]($series.Points.Count+1),[double]$value.($spec[1]))
                    $series.Points[$pointIndex].AxisLabel=$algorithm
                }
                $chart.Series.Add($series)
            }
            $name="c{0:D2}-{1}.png" -f [int]$chains,$spec[0]
            $chart.SaveImage((Join-Path $figDir $name),[System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]::Png)
            $figures+=$name
        } finally { $chart.Dispose() }
    }
}
$tableRows=@(); $mdRows=@()
foreach ($e in $summary) {
    $cells=@($e.chain_count,$e.capability_profile,$e.compatibility_mode,$e.algorithm,
        "$(Fmt $e.ready 0)/$($e.requested)","$(Fmt $e.compliant_ready 0)/$($e.requested)",
        "$(Fmt $e.workflow_ready 0)/$($e.chain_count)","$(Fmt $e.compliant_workflows 0)/$($e.chain_count)",
        (Fmt $e.violating_assignments 0),(Fmt $e.dependency_blocked_ready 0),(Fmt $e.deployment_sim_seconds 3),
        (Fmt $e.planner_wall_ms_median 3))
    $tableRows += "<tr>"+(($cells | ForEach-Object {"<td>$(Escape $_)</td>"}) -join "")+"</tr>"
    $mdRows += "| "+($cells -join " | ")+" |"
}
$reasonRows=@()
foreach ($e in @($summary | Where-Object { $_.capability_profile -eq "mixed" -and $_.compatibility_mode -eq "base" })) {
    $reasonRows += "<tr><td>$($e.chain_count)</td><td>$($e.algorithm)</td><td>$($e.arch_mismatch_count)</td><td>$($e.runtime_missing_count)</td><td>$($e.api_missing_count)</td><td>$($e.driver_missing_count)</td><td>$($e.security_mismatch_count)</td></tr>"
}
$comparisonRows=@()
foreach ($e in $paired) {
    $comparisonRows+="<tr><td>$($e.chain_count)</td><td>$($e.capability_profile)</td><td>$($e.algorithm)</td><td>$($e.model_ready_delta_full_minus_base)</td><td>$($e.compliant_ready_delta_full_minus_base)</td><td>$($e.compliant_workflows_delta_full_minus_base)</td><td>$($e.violations_delta_full_minus_base)</td></tr>"
}
$uniformCount=@($controls | Where-Object passed -eq $true).Count
$mixedBase=@($summary | Where-Object { $_.capability_profile -eq "mixed" -and $_.compatibility_mode -eq "base" })
$mixedFull=@($summary | Where-Object { $_.capability_profile -eq "mixed" -and $_.compatibility_mode -eq "full" })
$violatingCases=@($mixedBase | Where-Object violating_assignments -gt 0).Count
$allFullClean=@($mixedFull | Where-Object violating_assignments -gt 0).Count -eq 0
$overview="已完成$($rows.Count)次运行。$uniformCount/$($controls.Count)项对照核查通过。mixed场景关闭能力门控时，$violatingCases/$($mixedBase.Count)组存在声明能力违规；启用完整门控后，所有组零违规：$allFullClean。合规就绪还要求全部上游依赖合规；数量减少不自动代表算法退化，数量增加也不自动代表实际平台可运行。"
$variationText=if($variations.Count){"重复中非计时指标发生变化："+($variations -join "; ")}elseif($manifest.repetitions -gt 1){"本轮重复的非计时指标一致；确定性重复不等于独立场景样本。"}else{"每组仅运行一次；规划耗时中位数等于本次观测，尚未验证重复一致性。"}
$limits="本模块使用固定合成声明。X86_64、ARM64、容器/RTP、API、驱动及安全标签均为模型字段。SIGNED_PACKAGE/TLS_NETWORK/TRUSTED_NODE只表示集合约束，未执行验签、TLS连接或可信启动。未探测真实设备、ABI、驱动或操作系统版本。原READY仅为离散事件状态；合规READY为该状态叠加声明和依赖闭包检查。部署时间仅覆盖已接纳服务，不能因任务减少直接宣称提速。资源预留不等于实测利用率；独立JVM未排除JIT/预热，计时仅作描述；不做显著性、真实跨平台成功率或普遍最优结论。"
$definitions=@"
<h2>模型声明与对照</h2>
<p>uniform：每个节点具有其OS对应架构/运行环境、四项逻辑API、传感器驱动和三项安全标签，作为新增检查的阴性对照。mixed：仅改变下表能力；节点容量、服务资源需求及事件时延沿用原模型。全部四种算法共享同一个CompatibilityChecker。</p>
<table><tr><th>节点</th><th>mixed相对uniform的变化</th><th>可触发原因</th></tr>
<tr><td>linux-02</td><td>X86_64 → ARM64，Linux服务包仍声明X86_64</td><td>ARCH_MISMATCH</td></tr>
<tr><td>win-02</td><td>无WINDOWS_CONTAINER运行环境</td><td>RUNTIME_UNSUPPORTED</td></tr>
<tr><td>vx-02</td><td>缺FILTER_API、SENSOR_DRIVER、TLS_NETWORK</td><td>API_MISSING、DRIVER_MISSING、SECURITY_POLICY_MISMATCH</td></tr></table>
<p>collect要求SENSOR_API/SENSOR_DRIVER/签名与TLS；preprocess要求FILTER_API/签名；detect要求INFERENCE_API/签名与可信节点；alert要求ALERT_API/签名与TLS。每种版本另要求其架构和运行环境。API/驱动是本实验抽象契约名，未声称具体厂商实现支持。</p>
"@
$figHtml=($figures | ForEach-Object {"<figure><img src='figures/$_' alt='$_'><figcaption>$(Escape $_)</figcaption></figure>"}) -join $nl
$header="<tr><th>链数</th><th>能力场景</th><th>门控</th><th>算法</th><th>模型就绪</th><th>合规就绪</th><th>模型完整链</th><th>合规完整链</th><th>违规部署</th><th>依赖阻断</th><th>事件部署/s</th><th>规划中位/ms</th></tr>"
$html=@"
<!doctype html><html lang='zh-CN'><meta charset='utf-8'><title>平台能力约束与部署审计</title>
<style>body{font:17px/1.75 'Microsoft YaHei',sans-serif;color:#172b46;background:#f1f5f9;margin:0}main{max-width:1600px;margin:auto;background:white;padding:42px}h1,h2{line-height:1.4}table{border-collapse:collapse;width:100%;font-size:15px;margin:20px 0}th,td{padding:12px;border-bottom:1px solid #dbe5ef;text-align:left}th{background:#eaf0f7}tr:nth-child(2n){background:#f7f9fb}img{width:100%;height:auto}figure{margin:24px 0}code{background:#eef2f7;padding:2px 5px}.scroll{overflow:auto}.note{background:#edf4ff;padding:20px}</style>
<main><h1>平台能力约束与部署审计</h1>
<p>批次：$(Escape $manifest.run_id)；束宽：$($manifest.beam_width)；固定chain布局；每组$($manifest.repetitions)次。</p>
<div class='note'><b>结果概览</b><p>$overview</p></div>
$definitions
<h2>就绪指标口径</h2><p>模型就绪：原事件模型的READY。局部合规：本部署本身满足五类能力声明。合规就绪：READY且自身、所有上游依赖均合规。合规完整链：整条依赖连通业务链均合规就绪。依赖阻断：自身局部合规却因上游不合规而未计入合规就绪。</p>
<h2>完整结果</h2><p>$variationText</p><div class='scroll'><table>$header$($tableRows -join "")</table></div>
<h2>门控开关配对差异</h2><p>所有差值为full减base，零值和负值均保留。服务数和链数相同也不保证服务身份相同，因此本报告不自动计算提速比例。</p>
<table><tr><th>链数</th><th>场景</th><th>算法</th><th>模型就绪差</th><th>合规就绪差</th><th>合规完整链差</th><th>违规数差</th></tr>$($comparisonRows -join "")</table>
<h2>关闭门控时的违规类别</h2><p>仅mixed/base。每个类别统计涉及该类问题的部署项；同一项可有多类问题，各列相加可能大于违规项总数。未被选择的候选缺口见audits/*.candidates.csv。</p>
<table><tr><th>链数</th><th>算法</th><th>架构</th><th>运行环境</th><th>API</th><th>驱动</th><th>安全能力</th></tr>$($reasonRows -join "")</table>
<h2>mixed场景配对图</h2>$figHtml
<h2>适用范围</h2><p>$limits</p>
<h2>复核入口</h2><p>runs.csv为逐次汇总；summary.csv为组内统计；paired-mode-effects.csv记录配对差值；control-checks.csv记录阴性对照。audits/*.assignments.csv逐项列出需求、节点能力、原因码和依赖闭包判定；*.candidates.csv覆盖所有服务版本与节点的初始容量候选，不含动态剩余容量。raw/保留原始模型指标；project/为独立实验副本；snapshot/及source-hashes.csv保留源码与脚本。manifest.json记录配置、状态与环境。</p>
<p>Material Passport: Origin Skill academic-research-suite / experiment-agent; Origin Mode code-experiment; Origin Date 2026-10-20; Verification Status LOCAL_GENERATED_DESCRIPTIVE; Version platform-study-v1. 人工阅读标记：未声明。</p></main></html>
"@
[IO.File]::WriteAllText((Join-Path $BatchDir "report.html"),$html,(New-Object Text.UTF8Encoding($true)))
$md=@"
# 平台能力约束与部署审计
$overview

$variationText

| 链数 | 场景 | 门控 | 算法 | 模型就绪 | 合规就绪 | 模型链 | 合规链 | 违规项 | 依赖阻断 | 部署/s | 规划/ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
$($mdRows -join $nl)

## 指标范围
$limits

逐项审计见audits/，配对差异见paired-mode-effects.csv，对照检查见control-checks.csv。
Material Passport: academic-research-suite / experiment-agent; code-experiment; 2026-10-20; LOCAL_GENERATED_DESCRIPTIVE; platform-study-v1. 人工阅读标记未声明。
"@
[IO.File]::WriteAllText((Join-Path $BatchDir "report.md"),$md,(New-Object Text.UTF8Encoding($true)))
Write-Host "Created $($figures.Count) PNG figures, summary.csv, paired-mode-effects.csv, control-checks.csv, report.html and report.md."
