# 第25步：平台能力约束与部署审计

本步把架构、运行环境、API、驱动和安全能力纳入兼容性检查，再通过独立审计检查部署输出。原 simulation 源码保持原样；每批在 results/platform-study-*/project 中创建可复查的副本。它仍是合成能力模型，没有检测真实机器或验证真实容器/RTP。

## 运行

在原 simulation 目录执行：

```powershell
& "..\第25步_平台能力约束工具包\run-platform-study.ps1"
```

默认：3、6条链 × uniform/mixed × base/full × 四种算法，共32次。束宽64，固定chain输入，编译一次，每次启动独立Maven/JVM。每组一次。入口先自动运行20项能力与依赖检查，末尾自动核对全部部署明细并生成报告。

显式执行3次确定性重复（96次）：
```powershell
& "..\第25步_平台能力约束工具包\run-platform-study.ps1" -Repetitions 3
```

自定义负载数组时在PowerShell中直接调用脚本：
```powershell
& "..\第25步_平台能力约束工具包\run-platform-study.ps1" -ChainCounts @(2,4,8)
```

无需安装Python、绘图包或其他Java依赖。需现有JDK21、Maven和Windows PowerShell5的内置Charting。不要同时向同一实验副本运行额外仿真。

## 本步新增实现

1. PlatformPolicy：不可变能力与需求集合、两种合成节点画像、五类明确拒绝码；未知服务声明直接报错。
2. CompatibilityChecker：四种算法统一使用base/full门控，保留OS及累计CPU/RAM限制。
3. PlatformAudit：无论门控是否开启，都独立检查已选部署；输出每个部署的需求、节点声明、原因码、局部合规与依赖闭包判定。
4. 候选审计：覆盖所有服务版本×节点组合，区分初始容量候选和实际部署项。
5. 批量实验：控制组、能力缺口组、门控开关、原始指标与新增指标并存。
6. 自动复核：重新从审计明细计算五类违规、合规服务及完整链，并核查对照不改变原模型指标。
7. 报告：默认六张PNG、完整结果表、原因分布、配对差异、源码/脚本快照与SHA256。

## 能力声明

所有符号都是本实验声明，非厂商兼容承诺：

| 范围 | uniform | mixed变化 |
|---|---|---|
| Linux包/节点 | X86_64，LINUX_CONTAINER | linux-02改为ARM64，包仍为X86_64 |
| Windows包/节点 | X86_64，WINDOWS_CONTAINER | win-02删除运行环境 |
| VxWorks包/节点 | ARM64，VX_RTP | vx-02删除FILTER_API、SENSOR_DRIVER、TLS_NETWORK |
| 其他能力 | 四项API、传感器驱动、三项安全标签齐全 | 其他节点保持uniform |

| 服务 | API | 驱动 | 安全要求 |
|---|---|---|---|
| collect | SENSOR_API | SENSOR_DRIVER | SIGNED_PACKAGE、TLS_NETWORK |
| preprocess | FILTER_API | 无额外要求 | SIGNED_PACKAGE |
| detect | INFERENCE_API | 无额外要求 | SIGNED_PACKAGE、TRUSTED_NODE |
| alert | ALERT_API | 无额外要求 | SIGNED_PACKAGE、TLS_NETWORK |

每种包另要求其架构与运行环境。安全能力采用必需集合包含关系，没有把安全策略简化成任意等级大小比较。标签不执行验签、TLS握手或可信启动。

## 怎么读指标

- 模型就绪：原CloudSim事件走到READY。
- 局部合规就绪：模型就绪，且本项部署满足全部能力声明。
- 合规就绪：局部合规，还要求所有上游依赖合规。多级传播，避免上游不合规却把下游计为可用。
- 合规完整链：一条链的4个服务全部合规就绪。
- 违规部署项：自身声明不满足的已选部署，一个部署可能涉及多个原因码。
- 依赖阻断：自身合规，但上游不合规造成的合规就绪扣除。

base只按OS与CPU/RAM规划，审计仍检查完整能力；full规划时直接排除能力缺口。两者的事件READY都保留，不把声明合规混成真实运行验证。

## 输出

每次新建 simulation/results/platform-study-时间-随机ID：

- report.html / report.md：可阅读报告。
- figures/：每个负载3张图，默认共6张。
- runs.csv / summary.csv：逐次与组内统计，含原指标与新增审计指标。
- paired-mode-effects.csv：full减base的配对差异，保留零值和负值。
- control-checks.csv：uniform门控开关及base不同画像的对照检查。
- audit-checks.csv：独立逐项核对结果。
- audits/*.assignments.csv：部署审计；*.candidates.csv：初始容量候选审计；同名*.csv：审计汇总。
- raw/、logs/、manifest.json：原始指标、日志、配置/状态；失败停止，无自动重试。
- project/、snapshot/、source-hashes.csv：独立副本、代码/脚本快照、哈希。

## 完成后核查

看到 COMPLETE: 32/32 runs 后打开 REPORT 行的report.html。重点看mixed/base是否存在违规、mixed/full是否零违规、合规完整链数量，以及control-checks.csv和audit-checks.csv是否全部通过。算法接纳更多事件READY，并不自动意味着更多可用完整链。

本步不预设beam_search必然最好，不把更少接纳任务带来的更短时间解释为提速。不进行显著性检验。确定性重复用于一致性和计时描述，不是独立场景样本。

## 单独复查/重建

在PowerShell中将变量填为真实批次路径：
```powershell
$batch = "D:\实际路径\simulation\results\platform-study-实际批次"
& "..\第25步_平台能力约束工具包\verify-platform-output.ps1" -BatchDir $batch
& "..\第25步_平台能力约束工具包\build-platform-report.ps1" -BatchDir $batch
```

若当前是PowerShell7，报告生成请用Windows PowerShell5调用build-platform-report.ps1，正式入口会自动选择正确版本。重建报告不更改失败批次的manifest状态。

## 尚未完成的真实平台工作

真实平台仍需逐台采集架构、内核/容器或RTP版本、运行库/ABI、API/驱动和安全策略，执行镜像/RTP启动、传感器数据链、日志/健康检查等验证。本步只为这些测量提供明确的字段和审计接口。

Material Passport: Origin Skill academic-research-suite / experiment-agent; Origin Mode code-experiment; Origin Date 2026-10-20; Verification Status IMPLEMENTATION_QA_PASSED_FORMAL_RUN_PENDING; Version platform-study-v1. 人工阅读标记未声明。
