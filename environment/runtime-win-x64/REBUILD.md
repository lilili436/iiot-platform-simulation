# 便携包构建依据

Java 来源为已有 Eclipse Temurin JDK 21.0.12.1+1。重建命令（输出目录必须尚不存在）：

```powershell
jlink --module-path "$env:JAVA_HOME\jmods" --add-modules java.se,jdk.compiler,jdk.jartool,jdk.httpserver,jdk.zipfs,jdk.crypto.ec,jdk.unsupported --strip-debug --no-header-files --no-man-pages --compress=zip-6 --output java
```

打包生成目录根下的 bin/conf/legal/lib/release，并携带原始 JDK NOTICE。
Python 为 manifest 所列官方 ZIP 原样保留。Node.zip 只包含已按官方 SHA256 校验的 node.exe 和相同版本官方 LICENSE；未复制本机账户、配置、凭证或全局 npm 包。
运行 `scripts/runtime.ps1` 中的 Get-BundledRuntime 首次提取时会验证 SHA256。更新任何包时必须同时更新 manifest，并重新进行脱离系统环境的构建和验收。
