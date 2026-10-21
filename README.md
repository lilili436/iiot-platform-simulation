# 工业微服务跨平台部署与故障恢复仿真

这是现有工作区的一次性交接快照。接收方下载后可独立阅读、运行和修改；原作者不必参与后续提交。所有者已选择公开仓库：任何人都可查看下载，仓库写权限仍由所有者控制。

## 从哪里开始

- **后续修改 `current/`**：最新可编辑 Java 源码、工业演练页面和 CSV 场景配置，已包含 Windows 接管和多拓扑评估。
- `tests/`：连续故障、Windows 接管、HTTP 接口和页面渲染检查。
- `scripts/`、`run.ps1`：从仓库相对路径构建、运行、验收、生成新实验报告。
- `simulation/`：旧版基础工程；`第22步_*` 至 `第27步_*`：历史增量工具包。它们保留原始哈希，不作为新修改入口。
- `history/results/`、`history/backups/`：原有实验数据、日志、报告及备份。历史报告中的 D/E 盘路径是当时记录，并非新电脑的运行要求。
- `environment/`：环境清单、依赖缓存、源文件清单；`apache-maven-3.10.0/`、`cloudsim-7.0.1/` 保留第三方源码/发行包和许可证。

## 接收方运行

**Windows 10/11，Intel/AMD 64 位：完整下载 ZIP、解压后即可运行。** 已携带便携 Java 21（含 javac）、Python、Node.js、Maven 和编译依赖，不需要安装这些工具、不需要设置 JAVA_HOME/PATH、不需要管理员权限，默认构建和运行不访问互联网。

1. 在 GitHub 选择 `Code → Download ZIP`，完整解压到可写短目录，例如 `C:\iiot`。不要在 ZIP 预览窗口里直接启动。
2. 双击 **`启动演示.cmd`** 或 **`START-DEMO.cmd`**。首次会校验并解压便携 Java，然后离线编译，并在服务就绪后自动打开浏览器。
3. 保持终端打开；页面地址为 `http://127.0.0.1:8765/`。结束演示时在终端按 `Ctrl+C`。
4. 双击 **`本机验收.cmd` / `VERIFY.cmd`** 可运行检查；双击 **`完整算法评估.cmd` / `RUN-STUDY.cmd`** 可运行完整实验。验收/实验首次使用时才解压 Python 和 Node.js。

源码修改仍在 `current/`，下次启动会重新编译。新报告在 `runs/`。历史步骤说明中要求手动安装 Java/Python/Node 的内容只适用于旧版入口。

验收记录见 [便携验收](environment/portable-acceptance/acceptance.json)：已在本机用清空工具环境、冷启动、中文含空格的新目录检查，以及 180 场景/7,560 次完整评估；尚未在接收方实体电脑上实测。

也可在根目录 PowerShell 中运行：

```powershell
# 一次构建，默认离线使用随仓库交接的 Maven 依赖缓存
.\run.ps1 -Action Build
# 终端保持打开；浏览器访问 http://127.0.0.1:8765/
.\run.ps1 -Action Demo
# 独立验收：配置、精确校验、连续故障、Windows 接管及 HTTP/UI
.\run.ps1 -Action Verify
# 完整实验：180 个种子场景、7560 次测量及预热、报告和 PNG
.\run.ps1 -Action Study
```

如执行策略阻止本地脚本，可针对这一次运行：
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Action Demo`。
可用参数：`-Port 8766`、`-NoBrowser`（不自动打开页面）、`-PythonExe <路径>`、`-NodeExe <路径>`。
新输出位于 `runs/`，不会覆盖交接的历史结果。`Ctrl+C` 停止演示服务。

## 演示与结果范围

演练台支持离线、驱动缺失、运行环境缺失和工艺温度异常；可选择 Windows 接管，观察平台/版本切换及诊断。健康服务固定，备用节点接管，原节点修复后显示在线并保持备用，不自动回迁；验证后可继续下一轮，也可主动重置。

评估包含 chain、fork_join、independent、random_dag，五个随机种子、三种资源/能力配置、三种规模、基础算法/束宽/排序对照，以及服务数优先和完整业务优先两个目标。精确求解受规模/时间预算限制，报告区分已证最优与未证。规划耗时受 JVM 预热影响，不能把单次结果解释为普遍优势。

便携包适用 Windows x64；不是 macOS/Linux 运行包。其边界与运行库来源见 [环境说明](environment/SETUP.md)。

**当前是本机代码和仿真验收**；未验收真实 Docker Swarm、Windows 容器或 VxWorks RTP/目标板。安装了依赖不等于完成真实平台部署。

## 完整性与历史缺失

`environment/source-snapshot.csv` 记录从原工作区收集的文件及 SHA256。交接新增文件另记录在 `environment/handoff-files.csv`。复制时排除了个人凭证、用户 Maven 设置、编辑器缓存和可重新生成的编译输出，保留必需的 CloudSim JAR。

早期文档引用的两个 E 盘 Python 原型在本机已不存在；具体路径见 `environment/inventory.json`。本仓库保存当前实际存在的源码与结果，不能据旧说明认定缺失原型已交接。

第三方代码按各目录原有 LICENSE/NOTICE 使用；此交接不改变第三方许可，也不替自有代码新增开源许可。

## 后续修改

接收方可以直接修改下载副本；如需自行保存版本，可在自己的账号下建立新仓库。公开仓库无需邀请即可查看下载。对方可 Fork 到自己的 GitHub 账号或另建仓库继续修改；不需要授予对方本仓库写权限，也不需要共享密码。

## 首次上传（所有者）

本地目录已建立 Git 提交。若尚未完成 Git 的 GitHub 登录，在此目录打开终端，执行：

```powershell
git credential-manager github login --username lilili436 --device
.\publish-github.ps1
```

第一条命令会显示 GitHub 官方设备登录网址与一次性代码，由所有者自己在网页完成登录。第二条只在确认当前账号是 lilili436 后创建**公开**仓库并上传，拒绝覆盖已有不同内容。凭证由 Git Credential Manager 管理，不写入源码。上传后才可分享脚本打印并核验的仓库网址。
