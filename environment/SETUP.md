# Windows x64 便携环境

当前主入口为根目录 `启动演示.cmd`（同 `START-DEMO.cmd`），完整解压即可运行，无需安装 Java、Maven、Python、Node.js 或设置环境变量。

## 系统条件

- Windows 10/11，Intel/AMD x64，系统自带 Windows PowerShell 5.1 和现代浏览器。
- 解压到可写目录，建议 `C:\iiot`；不能直接从 ZIP 预览窗口运行。
- 需要足够的磁盘空间供源码、便携工具和新实验结果使用；完整交接及解压缓存建议预留 1 GB 以上。
- macOS、Linux、ARM64 不使用这些 Windows x64 二进制；需要自行配置相应运行环境。

## 已携带的工具

| 组件 | 版本/来源 | 用途 |
|---|---|---|
| Java | Eclipse Temurin 21.0.12.1+1，通过 jlink 生成含 javac 的模块化环境 | 离线编译、演示、Java 仿真与检查 |
| Python | 3.14.8，Python.org 官方 Windows x64 嵌入包 | HTTP/UI 验收和报告整理 |
| Node.js | 24.21.0，已核对官方 node.exe SHA256，附官方 LICENSE | JavaScript 语法与页面渲染检查 |
| Maven | 3.10.0 发行包及本地 JAR/POM 缓存 | 离线构建 |
| CloudSim | 7.0.1 源码及已构建 JAR | 离散事件仿真 |

便携归档在 `runtime-win-x64/`，首次使用按需解压到本目录 `.runtime/`。不修改系统注册表、全局 PATH 或 JAVA_HOME。`manifest.json` 记录归档和关键可执行文件的 SHA256，首次解压会核对。保留各自的 LICENSE/legal/NOTICE。Python 和 Node 的官方来源：

- [Python 3.14.8](https://www.python.org/downloads/release/python-3148/)
- [Node.js 24.21.0 SHA256](https://nodejs.org/download/release/v24.21.0/SHASUMS256.txt)

Java 包只包含本工程所需模块，并非完整 JDK 发行版（不含 jlink、jpackage 等未使用工具）；原有工程修改编译、演示和验收使用携带的 javac。Python 嵌入包不附 pip，Node 包不附 npm；本工程不需要它们。若接收方新增第三方依赖，应自行配置相应开发环境。

## 常见问题

- 提示端口占用：关闭此前开启的演示终端，或运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Action Demo -Port 8766`。
- 未自动打开浏览器：等待终端出现 `INDUSTRIAL DEMO`，手动访问终端显示的网址。
- 运行库校验失败：重新完整下载、解压；中途解压失败的 `.runtime` 子目录可先改名，再重试。没有自动递归删除逻辑。
- 离线构建失败：保留错误信息和日志。新修改引入未携带依赖时，可显式使用 `-Online` 下载缺项。
- 系统/企业策略阻止脚本或程序：需由接收方按本机管理要求处理，便携包不改动安全设置。

此包用于合成工业场景和跨平台部署仿真，不包含 Docker Swarm 或 VxWorks SDK/目标板；真实平台验收仍未执行。
