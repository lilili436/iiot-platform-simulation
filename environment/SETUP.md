# 环境交接

原机：Windows 11 x64；Temurin OpenJDK 21.0.12.1；Maven 3.10.0；CloudSim 7.0.1。

## 已携带

- Maven 3.10.0 发行包及其 LICENSE/NOTICE。
- CloudSim 7.0.1 源码、许可证及已构建 JAR。
- `maven-repository/`：当前工程编译用到的 JAR/POM 和仓库元数据（不包含个人 settings.xml 或凭证）。
- `maven-settings.xml`：无凭证的空白设置；`run.ps1` 默认使用它及本地仓库离线构建。

## 接收方安装

1. 从 https://adoptium.net/temurin/releases/?version=21 安装 JDK 21 x64。设置 `JAVA_HOME`，确保其 `bin` 下存在 java.exe、javac.exe。可用 `java -version` 验证。
2. 完整验收需要 Python 3.10+：https://www.python.org/downloads/windows/ 。勾选加入 PATH；不需要 pip 包。
3. 页面渲染检查需要 Node.js：https://nodejs.org/en/download 。加入 PATH；不需要 npm 包。
4. Git 可选：https://git-scm.com/downloads/win 。只下载 ZIP 查看/修改时不需要 Git。

这些是前置运行环境，未打包原机的系统目录、账户配置、浏览器、JDK/Python/Node 安装目录。无需复制原机用户名或目录结构。

若离线构建提示依赖缺失，先保留错误日志。联网后可显式运行 `.\run.ps1 -Action Build -Online` 下载 Maven 中央仓库缺项；默认不会联网。更换依赖版本后，接收方需自行补齐依赖缓存。

历史工具包假定 PATH 可找到 mvn/java 等，并使用旧基础工程哈希；新修改统一使用仓库根目录的 run.ps1 和 current/。
