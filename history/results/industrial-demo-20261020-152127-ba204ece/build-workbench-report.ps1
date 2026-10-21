[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BatchDir)
$ErrorActionPreference="Stop"
$BatchDir=(Resolve-Path -LiteralPath $BatchDir).Path
$data=Get-Content -LiteralPath (Join-Path $BatchDir "project\verification\results.json") -Raw -Encoding utf8 | ConvertFrom-Json
if($data.status -ne "PASS" -or $data.results.Count -ne 24){throw "Verification did not complete"}
$inv=[Globalization.CultureInfo]::InvariantCulture
function F($x){return ([double]$x).ToString("F3",$inv)}
function E($x){return [Net.WebUtility]::HtmlEncode([string]$x)}
$rows=@();$md=@();$gaps=@()
foreach($r in $data.results){
    $certificate=if($r.exact){if($r.optimal){"枚举完成（固定次序）"}else{"达到预算，未证明最优"}}else{"启发式"}
    $cells=@($r.scenario_id,$r.algorithm,"$($r.ready)/$($r.requested)","$($r.workflow_ready)/$($r.workflow_requested)",(F $r.deployment_seconds),(F $r.predicted_seconds),$certificate,$r.visited)
    $rows+="<tr>"+(($cells|ForEach-Object{"<td>$(E $_)</td>"}) -join "")+"</tr>"
    $md+="| "+($cells -join " | ")+" |"
    if(!$r.exact){
        $reference=$data.results | Where-Object {$_.scenario_id -eq $r.scenario_id -and $_.algorithm -eq "exact_service"}
        $comparable=$reference.optimal -and [int]$r.ready -eq [int]$reference.ready
        $gap=if($comparable){[double]$r.deployment_seconds-[double]$reference.deployment_seconds}else{$null}
        $gaps+=[pscustomobject]@{scenario=$r.scenario_id;algorithm=$r.algorithm;reference_certified=$reference.optimal;
            service_gap=[int]$reference.ready-[int]$r.ready;
            time_gap_seconds_if_same_service_count=$gap;
            reference_scope="Fixed loaded topological order; placement/admission enumeration; per-node FIFO"}
    }
}
$data.results | Select-Object scenario_id,algorithm,requested,ready,workflow_requested,workflow_ready,deployment_seconds,predicted_seconds,planning_ms,exact,optimal,visited |
    Export-Csv -LiteralPath (Join-Path $BatchDir "summary.csv") -NoTypeInformation -Encoding utf8
$gaps | Export-Csv -LiteralPath (Join-Path $BatchDir "exact-gaps.csv") -NoTypeInformation -Encoding utf8
$service=$data.results|Where-Object {$_.scenario_id -eq "objective-conflict" -and $_.algorithm -eq "exact_service"}
$workflow=$data.results|Where-Object {$_.scenario_id -eq "objective-conflict" -and $_.algorithm -eq "exact_workflow"}
$findings="手工反例中，服务数优先接纳$($service.ready)项服务，但完整链为$($service.workflow_ready)；完整链优先接纳$($workflow.ready)项服务，完整链为$($workflow.workflow_ready)。这说明两种目标可能冲突。现有束搜索仍保留服务数→部署时间→活跃节点的原排序；本步没有静默改变算法目标。"
$scope="精确校验只针对最多8项服务的固定输入拓扑次序，穷举接纳、版本和节点选择，使用每节点FIFO规则；不穷举所有合法服务次序，不宣称全局部署调度最优。达到200万搜索状态或10秒预算时必须标记未证明最优。时间差是这一模型下的优化目标差距，不等同于相同实际业务工作量的实测提速。全部节点/能力及工艺演示数据为合成声明；来源字段MEASURED表示用户声明的证据引用，并不自动认证测量真实性。"
$nl=[Environment]::NewLine
$html=@"
<!doctype html><html lang='zh-CN'><meta charset='utf-8'><title>配置加载与精确校验报告</title>
<style>body{margin:0;background:#eff3f8;color:#18304a;font:16px/1.8 'Microsoft YaHei',sans-serif}main{max-width:1450px;margin:auto;padding:40px;background:white}h1,h2{line-height:1.4}table{border-collapse:collapse;width:100%;font-size:14px}td,th{padding:12px;border-bottom:1px solid #dbe4ee;text-align:left}th{background:#eaf1f8}tr:nth-child(2n){background:#f8fafc}.note{padding:20px;background:#eef5ff}.scroll{overflow:auto}code{background:#eef2f6;padding:3px}</style>
<main><h1>配置加载与小规模精确校验</h1><p>本批通过$($data.checks)项检查，完成24次配置驱动规划与CloudSim运行。</p>
<div class='note'><b>目标函数核验结果</b><p>$findings</p></div>
<h2>配置与失败诊断</h2><p>统一使用scenario.properties、nodes.csv、services.csv、variants.csv。检查版本、字段结构、必需值、唯一标识、有限正资源、依赖缺失/环、能力集合及来源标记；支持UTF-8 BOM、中文及带逗号的引号字段。非法输入在规划前拒绝。原Java项目保留。</p>
<h2>完整结果</h2><div class='scroll'><table><tr><th>场景</th><th>算法/目标</th><th>服务</th><th>完整链</th><th>CloudSim/s</th><th>独立时序/s</th><th>证明范围</th><th>搜索状态</th></tr>$($rows -join "")</table></div>
<h2>独立校验范围</h2><p>$scope</p>
<p>summary.csv保留逐组结果，exact-gaps.csv保存相对服务优先精确解的差距；project/verification/results.json包含具体服务身份、部署、来源和事件序列。配置及源码位于project/，哈希见source-hashes.csv；日志见logs/。</p>
<h2>可视化演示</h2><p>工具包另提供start-industrial-demo.ps1，启动本地工业演练台：设备、六个异构节点实例、四阶段服务链、温度曲线、故障注入、能力/依赖诊断、冷却或重新部署、恢复验证、记录导出。工艺和故障是模拟；重新规划调用Java算法，部署事件由CloudSim产生。</p>
<p>Material Passport: academic-research-suite / experiment-agent; code-experiment; 2026-10-20; LOCAL_VERIFIED_WITHIN_FIXED_ORDER_SCOPE; workbench-v1. 人工阅读标记未声明。</p></main></html>
"@
[IO.File]::WriteAllText((Join-Path $BatchDir "report.html"),$html,(New-Object Text.UTF8Encoding($true)))
$text=@"
# 配置加载与精确校验
通过$($data.checks)项检查，24次配置驱动运行。

$findings

| 场景 | 算法/目标 | 服务 | 完整链 | CloudSim/s | 独立时序/s | 证明范围 | 状态数 |
|---|---|---|---|---|---|---|---|
$($md -join $nl)

$scope

Material Passport: academic-research-suite / experiment-agent; code-experiment; 2026-10-20; LOCAL_VERIFIED_WITHIN_FIXED_ORDER_SCOPE; workbench-v1. 人工阅读标记未声明。
"@
[IO.File]::WriteAllText((Join-Path $BatchDir "report.md"),$text,(New-Object Text.UTF8Encoding($true)))
Write-Host "REPORT: $(Join-Path $BatchDir 'report.html')"
