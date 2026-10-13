# CloudFlareScan Android APK 逆向分析报告

> 日期：2026-10-13。范围：用户提供的本地 `CloudFlareScan-Android.apk` 静态分析及 iOS 功能重建；未对第三方服务器做安全测试。工具：JADX 1.5.6、PowerShell。

## 目标与结论

APK 位于 `C:\Users\Admin\Downloads\CloudFlareScan-Android.apk`，大小 5,624,076 字节，SHA-256 为 `DD131C177D9A23281D322FF24391DDC805CFFDE6554121C11C2D1F7057741BAA`。Manifest 包名 `com.example.cfscanner`，版本 1.0，入口 `MainActivity`。包含三个 DEX、`ipv4.txt`、`ipv6.txt`、`colo.txt`，没有原生 `.so`。

主要流程是从内置网段随机生成候选 IP，测试指定端口的连接延迟，查询 Cloudflare 地区码，对低延迟候选下载测速，最后排序并导出 CSV。[iOS 工程](./CloudFlareScan.xcodeproj/project.pbxproj)重建了这一流程，但不是当前环境可签名安装的 IPA。

## 证据

| ID | 来源 | 可复核观察 | 复核方式 |
| --- | --- | --- | --- |
| E-001 | 原 APK；SHA-256 见上文 | 三个 DEX、三个文本资源、无 `.so` | `Get-FileHash -Algorithm SHA256 'C:\Users\Admin\Downloads\CloudFlareScan-Android.apk'`；查看 ZIP 条目 |
| E-002 | `work/cloudflare-scan-reverse/sources/com/example/cfscanner/MainActivity.java` | `loadIpRangesFromAssets` 读资源，IPv4 每段抽 1 个、IPv6 每段抽 10 个 | `rg -n 'loadIpRangesFromAssets|generateRandomIps' work/cloudflare-scan-reverse/sources/com/example/cfscanner/MainActivity.java` |
| E-003 | `work/cloudflare-scan-reverse/sources/com/example/cfscanner/Scanner.java` | TCP 配置有 1500 ms 超时；以 `Host: speed.cloudflare.com` 访问 `http://IP/cdn-cgi/trace` | `rg -n 'connectTimeout|readTimeout|cdn-cgi/trace|speed.cloudflare.com' work/cloudflare-scan-reverse/sources/com/example/cfscanner/Scanner.java` |
| E-004 | `work/cloudflare-scan-reverse/sources/com/example/cfscanner/SpeedTester.java` | `speed.cloudflare.com`、50 MiB 目标、单线程、默认 4 秒冷却、信任所有证书；JADX 未还原 `measureSpeed` 主体 | `rg -n 'testHost|downloadBytes|newSingleThreadExecutor|coolDownMs|trustAllCerts|Method not decompiled' work/cloudflare-scan-reverse/sources/com/example/cfscanner/SpeedTester.java` |
| E-005 | `work/cloudflare-scan-reverse/sources/com/example/cfscanner/MainActivity.java` | 地区/全量测速都取延迟最低前 N 个；CSV 含排名、IP、地区、延迟、速度、端口、类型 | `rg -n 'startRegionSpeedTest|startFullSpeedTest|exportResults|排名,IP地址' work/cloudflare-scan-reverse/sources/com/example/cfscanner/MainActivity.java` |

E-002 至 E-005 是本地反编译产物，未逐文件计算哈希。JADX 对若干第三方或协程类有反编译错误，因此只把可读业务代码和资源视为已验证证据。

## 发现

| ID | 级别 | 证据 | 位置 | 结论与状态 |
| --- | --- | --- | --- | --- |
| F-001 | n/a_re | E-002、E-003 | `MainActivity.generateRandomIps`、`Scanner.fetchColo` | 高置信度：地址源为内置网段，地区来自 Cloudflare trace；静态验证 |
| F-002 | n/a_re | E-004、E-005 | `SpeedTester`、`MainActivity.exportResults` | 高置信度：50 MiB 目标，测速结果可导出 CSV；静态验证 |
| F-003 | 中 | E-004 | `SpeedTester.trustAllCerts` | 高置信度：Android 原版测速禁用证书校验，可能接受伪造 TLS 响应；静态验证，未动态利用 |
| F-004 | n/a_re | E-004 | `SpeedTester.measureSpeed` | 中置信度：方法体未完整反编译，不能证明 iOS 字节统计与原版完全一致；待真机对照 |

## 调用路径

P-001（`path_type=callflow`）：`MainActivity.loadIpRangesFromAssets`（E-002）→ `generateRandomIps`（E-002、F-001）→ `Scanner.start/scanIp`（E-003）→ `fetchColo`（E-003、F-001）→ `startRegionSpeedTest/startFullSpeedTest`（E-005）→ `SpeedTester.start/measureSpeed`（E-004、F-002/F-004）→ `exportResults`（E-005）。残余风险：测速内部细节及 iOS 运行时行为未动态验证。

## 时间线和边界

1. 核对 APK 哈希、Manifest、DEX 与资源。
2. 用 JADX 提取 Java 视图，定位四个业务类。
3. 核对地址生成、连接测试、地区查询、测速和导出。
4. 用 SwiftUI 和 Network.framework 编写 iOS 功能重建，复制 APK 内置资源，静态检查工程文件。

未进行 Android 动态 Hook、iOS 编译、真机安装或测速对比。技能文档引用的工具索引文件在本地包中不存在，因此本报告只引用实际可用工具与可复核文件，不声称完成自动化 case 验证。
