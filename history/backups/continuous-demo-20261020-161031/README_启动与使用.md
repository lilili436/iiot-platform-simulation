# 第26步：配置校验与工业环境故障演练台

本步合并交付“配置加载 + 小规模精确校验 + 可视化演示第一版”。原simulation源码不覆盖，每次创建独立的可运行项目。所需依赖仍为现有JDK21、Maven和CloudSim；演示界面是本地软件，由Java内置HTTP服务器提供，不需要联网、不需要安装前端包或Python。

## 1. 先启动可视化软件

在原simulation目录执行：

```powershell
& "..\第26步_配置校验与工业演练台\start-industrial-demo.ps1"
```

出现 INDUSTRIAL DEMO 后，在独立浏览器打开 http://127.0.0.1:8765 。建议最大化窗口，汇报时可按F11全屏。终端保持运行，Ctrl+C停止。如果端口已被其他程序占用，不要停止其他程序，可改用：
```powershell
& "..\第26步_配置校验与工业演练台\start-industrial-demo.ps1" -Port 8766
```

此时打开 http://127.0.0.1:8766 。新会话目录显示在终端SESSION行，位于simulation/results/industrial-demo-*/。

界面包含：电机与循环泵、模拟温度/振动/转速、四阶段业务链、六个异构节点的服务位置与资源预留、故障诊断、修复动作、实际CloudSim部署事件、演练日志和JSON导出。

## 2. 推荐先演示“节点离线”

1. 保留束搜索算法，观察当前collect/preprocess/alert所在节点。
2. 故障类型选择“节点离线”，目标默认选择当前采集服务所在节点。
3. 点“注入故障”：该节点离线，受影响服务及其下游被阻断。
4. 点“检查与诊断”：查看NODE_OFFLINE及UPSTREAM_UNAVAILABLE。
5. 点“执行修复”：重新调用Java算法及完整能力检查，在剩余节点重新部署。迁移列表和CloudSim事件都随实际输出更新。
6. 点“验证恢复”：服务与依赖均可用且工艺采样正常，才能显示“业务已恢复”。
7. 故障节点继续显示离线，说明恢复的是业务，通过隔离和重部署实现，并没有声称节点硬件被修好。
8. 点“导出演练记录”，保留本次配置来源、方案、诊断、迁移及事件。另有project/demo-session/events.jsonl持续记录操作。

## 3. 再演示“电机过热”

1. 点“重置环境”，选择“电机温度过高”，目标设备固定M-01。
2. 注入后温度曲线越过80°C阈值，设备显示告警；平台能力没有改变。
3. 诊断给出TEMPERATURE_HIGH，修复开启模拟冷却。
4. 每次演练采样使温升衰减到上一时刻的0.65倍。等待或使用“推进1秒”，连续3次温度/振动正常后再验证。
5. 不满足条件时保留等待状态，不靠按钮直接把告警改成成功。

还支持传感器驱动缺失、运行环境不可用，均通过真实Java兼容检查重新规划。若目标节点未承载相关服务，诊断如实说明“当前无业务影响”。每轮只注入一项故障，另一轮先重置。切换算法也会重置环境。多个浏览器标签共享同一个本地演练会话；汇报时只保留一个标签，避免多个页面同时推进采样。

## 4. 运行配置和精确校验工作包

可先停止演示，再在原simulation目录执行：
```powershell
& "..\第26步_配置校验与工业演练台\run-config-checks.ps1"
```

通过后输出REPORT。默认执行100项检查、24次配置驱动的规划/CloudSim运行，产生report.html、report.md、summary.csv、exact-gaps.csv和完整results.json。

精确求解限制为最多8项服务，最多200万搜索状态或10秒。证明范围是固定配置的稳定拓扑次序下的接纳/版本/节点选择，采用节点内FIFO；没有穷举所有部署次序。预算不足时标记未证明最优，不把当前最好解当最优解。

## 5. 本步发现的目标冲突

手工反例使用一个CPU容量3的节点，四阶段长链每阶段需求1，另有单服务业务需求3。服务数优先的精确解接纳长链前三项，3项服务、0条完整业务；完整链优先接纳独立业务，1项服务、1条完整业务。

原束搜索仍沿用“服务数、部署时间、活跃节点”的排序。这里明确展示冲突，没有暗中更换目标或只展示有利结果。是否将完整链作为首要目标，是下一阶段算法设计的明确决策点。

## 6. 配置文件

每个configs子目录均含：
- scenario.properties：schema_version=1、scenario_id、description。
- nodes.csv：节点资源、架构、运行环境、API、驱动、安全能力及来源。
- services.csv：逻辑服务ID、依赖ID，依赖用竖线分隔。
- variants.csv：版本ID、服务归属、OS、资源/包大小/启动时间、所需能力及来源。

能力集合也用竖线分隔。支持UTF-8/BOM、引号、字段内逗号及中文证据说明。缺字段、错版本、重复ID、依赖缺失/环、无服务版本、非法资源、未知来源等在规划前拒绝。
origin只能为SYNTHETIC或MEASURED，evidence不可为空；MEASURED只是来源声明，软件不会自动认证引用是真实测量。

示例配置：pressure-c1/c2/c3-uniform、pressure-c1-mixed、demo-industrial、objective-conflict。demo使用更充足的原demo资源，保证展示重点是故障后的适配及迁移；不得把它与pressure实验混作同一资源场景。

## 7. 实现入口

实际Java代码在本轮结果的project/src/main/java/org/example/iiot内：
- config/ScenarioLoader.java：统一配置及失败诊断。
- placement/PlatformPolicy.java：配置驱动的能力检查，供所有算法共享。
- placement/ExactPlanner.java：独立枚举与前驱图时间核验。
- PlanRuntime.java：算法、资源检查、CloudSim执行及结构化输出。
- demo/DemoEngine.java：故障状态机、诊断、冷却、重规划、恢复验证。
- demo/DemoServer.java：仅监听127.0.0.1的本地界面接口。
- VerificationMain.java：100项检查与24次配置实验。
- web/index.html、style.css、app.js：展示界面。
工具包中的.java.txt为创建项目时使用的源码载荷；patch-metadata.json核对原项目和载荷哈希，source-hashes.csv保存实际运行输入/代码/界面的哈希。

## 8. 演示边界与后续

工业曲线、节点声明和故障均为合成模拟。Java部署算法和CloudSim事件确实执行，但没有启动真实容器、RTP或传感器驱动；工艺数据的演练秒也不是CloudSim部署秒，界面分别标明。监测曲线作为独立观测通道展示，即使业务链受阻仍可看到设备模拟状态。

这一版可以演示“环境→故障→检查→处理→验证”。后续仍需更广场景、算法目标决策、真实平台执行验证及最终报告/PPT。它是可运行的演示初版，不是完整项目已全部验收的声明。

Material Passport: academic-research-suite / experiment-agent; code-experiment; 2026-10-20; IMPLEMENTATION_QA_PASSED_FORMAL_RUN_PENDING; workbench-v1. 人工阅读标记未声明。
