# TransmissionHM

**HarmonyOS BitTorrent Client** — 基于 [transmissionbtc](https://github.com/AndreyPavlenko/transmissionbtc) (Android v1.3.10) 移植，Java 应用层全部废弃，改用 **ArkTS + ArkUI** 重写。C/C++ 原生引擎 (libtransmission) 保留，JNI → N-API 适配。

## 架构

```
┌──────────────────────────────────┐
│  ArkTS / ArkUI 应用层             │  ← 65 Java 文件 → ArkTS 重写
├──────────────────────────────────┤
│  N-API Bridge (C++)              │  ← 40 个原生方法, ThreadSafeFunction 回调
├──────────────────────────────────┤
│  libtransmission + 依赖 (C)       │  ← 保留, JNI → N-API 适配
└──────────────────────────────────┘
```

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | ArkTS + ArkUI (@State/@Prop/@Provide) |
| 原生桥接 | N-API (OpenHarmony NDK) |
| BT 引擎 | libtransmission 4.0.6 (fork) |
| 密码学 | OpenSSL 3.2 |
| HTTP | libcurl 8.5 / `@ohos.net.http` |
| 事件循环 | libevent 2.1.12 |
| 构建 | Hvigor + CMake |
| 文件 I/O | `@ohos.file.fileaccess` |
| 偏好设置 | `@ohos.data.preferences` |

## 当前状态

```
v1.0 开发中 ━━━━━━━━━━━━━━━━━ 0%

□ M0  工程脚手架 & 原生编译     (3-5天)
□ M1  N-API 桥接层             (6-9天)
□ M2  存储适配层               (4-6天)
□ M3  偏好设置模块             (2-3天)
□ M4  Torrent 领域模型         (3.5-5.5天)
□ M5  HTTP 流媒体服务器        (2.5-3.5天)
□ M6  前台服务 & 系统集成      (3-4天)
□ M7  核心 UI                  (5-7天)
□ M8  设置 UI & 打磨           (2.5-4天)
□ M9  测试 & 加固              (3.5-5.5天)

总计: ~33-50 天 (串行)
```

## 文档

| 文档 | 内容 |
|------|------|
| [01 — 原生桥接与核心引擎](docs/01-native-bridge-and-core-engine.md) | 40 个 JNI 方法, 9 个 C++ 文件, CMake 构建 |
| [02 — Torrent 管理](docs/02-torrent-management.md) | Torrent/TorrentFile/TorrentDir 完整目录 |
| [03 — HTTP/UPnP/SSDP 服务器](docs/03-http-upnp-ssdp-server.md) | HTTP 服务器, UPnP DMS, SSDP (UPnP 已推迟) |
| [04 — UI 服务与设置](docs/04-ui-services-and-settings.md) | Activities, Views, Service, Settings |
| [05 — 架构恢复](docs/05-architecture-recovery.md) | ArkTS+N-API 架构, 数据流 |
| [06 — 功能地图与差距分析](docs/06-feature-map-and-gap-analysis.md) | 67 个 v1.0 功能 + 15 个推迟功能 |
| [07 — 开发计划](docs/07-development-plan.md) | 9 个里程碑, 94 个任务 |
| [08 — Java→ArkTS 映射](docs/08-java-to-arkts-mapping.md) | 65 个 Java 文件 → ArkTS 映射 |
| [M0 开工清单](docs/M0-kickoff.md) | M0 具体执行步骤 |

## 设计

- [Design Tokens](design/tokens.css) — CSS 自定义属性, 暗色工业精密风
- [Interactive Demo](design/demo.html) — 浏览器可直接打开的交互原型

## v1.0 范围

- ✅ Torrent CRUD, 磁力链接, 文件流媒体, RPC + Web UI
- ✅ 前台服务, WiFi-Only 模式, 代理配置, 设置
- 🚫 UPnP/DLNA/SSDP, M3U 播放列表, 监听目录 (→ v1.1+)
- 🚫 Dark Theme, 俄语本地化, RSS, Alt Web UI (→ v1.1+)

## 开发

需要 DevEco Studio + HarmonyOS SDK + NDK 工具链。M0 开工清单见 [docs/M0-kickoff.md](docs/M0-kickoff.md)。
