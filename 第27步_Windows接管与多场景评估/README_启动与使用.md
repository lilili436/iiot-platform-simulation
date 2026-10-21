# 第27步：Windows跨平台接管与多拓扑评估

本工具包只补充两项：Windows等接管平台的直观选择，以及多拓扑、随机场景和更完整的算法评估。原simulation源码和第26步工具包保留；每次运行创建独立结果目录。

## 打开演练台

1. 双击“启动演练台.cmd”，等待出现 INDUSTRIAL DEMO。
2. 双击“打开演示页面.url”，或访问 http://127.0.0.1:8765/。
3. 终端保持运行。重启后是新会话，已有会话需先导出记录。

在simulation目录也可执行：
```powershell
& "..\第27步_Windows接管与多场景评估\start-industrial-demo.ps1"
```

## 演示Windows接管

1. 保留束搜索初始方案：collect/preprocess/alert在vx-01，detect在linux-01。
2. 在右侧“故障接管平台”选择“Windows 接管”。修改该选项不会重置或迁移现有服务。
3. 向vx-01注入传感器驱动缺失、离线或运行环境不可用之一。
4. Windows兼容节点接管三个服务，业务卡片显示Windows版本名；接管记录显示原/新节点、OS和版本。
5. 检查与诊断→执行修复→验证恢复。vx-01恢复在线，CPU/RAM预留为0，成为备用节点；服务不自动回迁。
6. 下一轮可故障注入当前Windows承载节点，并选择Linux或VxWorks接管；同平台及已修复节点也可再次测试。
7. 检测服务没有VxWorks版本。若向检测节点注入故障且强制VxWorks接管，系统拒绝注入并解释原因，原会话不变；选择Windows则可接管。
8. 自动模式继续优先兼容的同平台空闲节点。故障未修复并验证前不叠加故障。

指定平台只约束迁移服务，其它健康节点的部署保留。仍执行OS、架构、运行时、API、驱动、安全、累计CPU/RAM和依赖检查，不为展示而绕过约束。过热仍只开启模拟冷却，不迁移部署。

Windows接管是Java/CloudSim中的平台版本与节点画像切换，不代表启动了真实Windows容器。

## 一键验收与实验

- “运行验收.cmd”：配置/精确检查、接管集成检查、连续恢复、HTTP与前端渲染检查。
- “运行多场景评估.cmd”：上述检查 + 完整扩展实验 + PNG图表、CSV和HTML报告。

```powershell
& "..\第27步_Windows接管与多场景评估\run-evaluation.ps1" -Mode All
```

脚本输出REPORT路径，结果保存在simulation/results/extended-study-时间-编号/。失败时保留输入、日志和当前结果，并标记FAILED。不会覆盖既有实验结果。

依赖：JDK21、Maven、已构建的CloudSim7.0.1、Python3标准库、Node.js、Windows PowerShell5图表组件。默认优先使用本机Codex捆绑Python；也可通过-PythonExe、-NodeExe指定程序。原始Java项目不需要Python/Node，新增报告和界面验收才需要。

## 实验设计

- 固定种子：11、29、47、83、101。
- 四种拓扑：双业务链、分叉汇合、独立服务、随机DAG。
- 三种配置：ample、pressure、gap；节点资源、带宽和服务版本开销由种子确定，gap额外移除部分节点运行环境。
- 三种服务规模：4、8、12；共180组场景。同一输入提供给所有方法，完整输入JSON归档。
- 七种方法：First Fit、Round Robin、Best Fit、输入顺序束搜索W64，以及稀缺度排序束搜索W4/W16/W64。
- 两种评价目标：service_first和workflow_first；每组同输入预热1次、测量3次，共7560次测量，另有2520次预热。
- 演练台保留原有service_first默认；两种目标作为实验比较，不宣称已经替用户确定最终研究目标。
- service_first：服务数→部署时间→活跃节点数。workflow_first：完整业务数→服务数→部署时间→活跃节点数。
- 三个基础算法保留自身规则；两种目标仅改变束搜索及对应精确校验的偏好，所有方案使用相同指标评价。

完整业务定义为依赖图的无向连通分量全部就绪。图结构及就绪服务身份保留，不能仅凭服务数量推断完整业务数量。

## 如何解释报告

summary.csv保留每场景/目标/方法的结果和计时中位数、标准差；aggregate.csv按规模、拓扑、资源配置、目标分层汇总；paired-effects.csv记录W64相对基线、排序消融和不同束宽的配对差异。只有就绪服务身份相同才计算部署时间缩短。

4服务精确求解预算50万状态/2秒；8服务预算10万状态/250毫秒；12服务跳过精确求解。只有完成穷举且FIFO顺序一致时填写主目标最优性差距，其它留空。有限宽度不保证全局最优，预算不足不能称为已证明最优。

同输入重复用于观察计时变化，不当作独立随机场景。计时在同一JVM顺序执行，预热不能完全排除JIT/GC影响。CPU/RAM为资源预留比例，不是实际运行负载；较高不自动意味着更好。不同接纳量/身份的批次时间不能直接宣称性能提升。

## 源码入口与结果追溯

工具包.java.txt为源码载荷，启动时写入独立project/src/main/java。新增入口：
- placement/ObjectiveBeamPlanner.java：两种目标、输入/稀缺度排序及束宽参数。
- PlanRuntime.java：统一运行与指定平台接管。
- demo/DemoEngine.java、DemoServer.java：设置、失败注入原子性及会话状态。
- FinalCheckMain.java：跨平台接管及目标反例检查。
- StudyMain.java：带种子的场景生成、配对实验与原始结果。
- web/app.js、index.html：接管选择、平台版本及迁移展示。
- run-evaluation.ps1、summarize_report.py、build-final-figures.ps1：统一验收、分层统计与报告。

每批保存manifest.json、input-source-hashes.csv、源码载荷元数据、日志、原始输入、全部方案/拒绝原因/部署事件。第22～26步历史结果保留，本批结果单独记录。真实Swarm/VxWorks环境未执行验收，本次范围为本机代码与仿真。
