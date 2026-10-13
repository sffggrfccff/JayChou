# CloudFlare Scan iOS

根据用户提供的 Android APK 静态分析结果，独立编写的 SwiftUI iPhone 工程。它不是 APK 转换文件，也不是已签名 IPA。

> 当前 Windows 环境没有 Xcode，因此只完成了源码与工程文件的静态检查，未完成 iOS 编译或真机测试。TrollStore 可安装无开发者签名的 IPA，但仍必须先用 Xcode 编译；不要把本目录直接改名为 `.ipa` 安装。

## 用 TrollStore 安装

此工程提供 [GitHub Actions 构建流程](./.github/workflows/build-trollstore-ipa.yml)。将本目录作为 GitHub 仓库根目录上传后，在仓库的 Actions 页面手动运行 `Build TrollStore IPA`。构建成功后下载 `CloudFlareScan-TrollStore` 构建产物，解压获得 `CloudFlareScan-TrollStore.ipa`，再在已安装 TrollStore 的 iPhone 中打开 IPA。此流程不会要求提供 Apple ID 密码或证书。

目前还没有可用的 GitHub 仓库或 macOS 构建入口，因此工作流尚未实际运行，不能保证工程已经通过编译或能在目标 iOS 版本正常运行。TrollStore 本身也须支持你的设备和 iOS 版本。

## 在 Mac 上构建

1. 安装 Xcode 15 或更新版本，在 Mac 上打开 `CloudFlareScan.xcodeproj`。
2. 选择 iPhone 模拟器，在 Xcode 中运行，先核对界面与扫描行为。
3. 如需在自己的 iPhone 上安装，在 Xcode 的 Signing & Capabilities 中选择自己的 Personal Team，换成唯一的 Bundle Identifier，连接手机并按提示开启开发者模式，然后从 Xcode 运行。免费 Apple ID 可以用于个人真机调试，但不能用于常规 IPA 分发；正式分发需要 Apple Developer Program。

## 使用

选择端口、并发和延迟上限，启动 IPv4 或 IPv6 扫描。扫描完成后可输入 `HKG` 等地区码进行地区测速，或对延迟最低的前 N 个地址进行完全测速。测速结果按 MB/s 降序排列，可复制 IP，或通过系统分享面板导出 CSV。

| 设置 | 默认 | 范围 |
| --- | ---: | ---: |
| TLS 端口 | 443 | 443、2053、2083、2087、2096、8443 |
| 扫描并发 | 50 | 1-100 |
| 延迟上限 | 220 ms | 1-2000 ms |
| 测速数量 | 10 | 1-50 |

程序从内置 IPv4 `/24` 网段各随机生成 1 个地址，从内置 IPv6 `/48` 等网段各随机生成 10 个地址并去重。测速逐个进行，每个地址最多下载 50 MiB，中间间隔 4 秒，因此可能消耗大量移动数据。

## 差异和限制

- Android 原版在测速时关闭了证书校验。iOS 版保留 `speed.cloudflare.com` 的 TLS 主机名/SNI，并正常校验证书，不会接受无效证书。
- JADX 未能完整反编译原版 `measureSpeed` 方法。iOS 版使用 `GET /__down?bytes=52428800`，只把完整、状态为 200 的响应计为有效测速。这是功能重建，不保证与原 APK 的测速数值完全一致。
- 地区查询与原版相同，通过指定 IP 的 HTTP 80 端口读取 `/cdn-cgi/trace`；失败显示 `N/A`，不能用于地区筛选。
- 扫描任务需要保持 App 在前台，iOS 挂起后台 App 时网络操作可能中断。
- 目前无法在本机执行 `xcodebuild`，实际编译和真机网络效果仍待 Mac 环境验证。

逆向证据与重建边界见 [分析报告](./2026-10-13_reverse-cloudflare-scan-report.md)。
