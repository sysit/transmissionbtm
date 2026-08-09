# 功能地图 & 架构现状（2026-08-09）

> 本文基于对**实际代码**的三层盘点（ArkTS 层 / C++ N-API 层 / 文档与配置层）编写，
> 目标是给当前项目一个**准确、无水分**的现状图景：什么能用、什么已死、什么被推迟，
> 以及架构是怎么跑的。docs/06、docs/07 是规划性文档，本文只反映**代码现状**。
>
> **对照更新（2026-08-09）**：与源头项目 transmissionbtc 的架构对照见
> [docs/10-architecture-compared-with-transmissionbtc.md](10-architecture-compared-with-transmissionbtc.md)。
> 核心结论：线程模型相对原版退化（事件线程派发丢失）、magnet/HTTP流媒体/UPnP/监视目录/URL添加
> 是「移植欠账」而非新功能。§4 优先级据此修正，见 docs/10 §6。
> **可执行清单**：重构任务分级见
> [docs/11-refactoring-checklist.md](11-refactoring-checklist.md)。

---

## 1. 功能地图（实际状态）

图例：✅ 已实现可用 ｜ ⚠️ 部分可用/有缺陷 ｜ 🗑️ 死代码/未接线 ｜ ⏳ 推迟（v1.1+）

### 1.1 种子核心（全部 ✅ 经 M7 E2E 在真机验证）

| 功能 | 入口 | 说明 |
|------|------|------|
| 会话生命周期（启动/停止/挂起） | `DownloadsPage.initSession()` | 原生 libtransmission 4.1 进程内运行 |
| 种子列表 + 1s 轮询 | `DownloadsPage` + `TorrentCard` | 进度/速度/ETA/做种状态 |
| 添加种子（文件） | `AddTorrentPage` → `torrentAdd` | **2026-08-09 修复**：picker `file://` URI → 复制到沙箱 cache 真实路径 |
| 暂停/恢复/校验/重新通告 | `TorrentContextMenu` | 走 `runInTransmissionThread` |
| 删除（含数据/不含数据） | `TorrentContextMenu` | ⚠️ 异步：`tr_torrentRemove` fire-and-forget，UI 靠 1s 轮询掩盖 |
| 迁移下载位置 | 菜单 → `torrentSetLocation` | E2E 7.11 已验证 |
| 文件树 + 选择（DnD/优先级） | `FileTreePage` + `FileTreeView` | `setWanted` → SKIP，E2E 7.8 已验证 |
| 多种子并发 | — | E2E 7.9（10 个并发）已验证 |

### 1.2 设置与偏好（✅ 已接线）

| 功能 | 入口 |
|------|------|
| 偏好持久化（40+ 键，类型化 getter/setter） | `models/Preferences.ets`（`@ohos.data.preferences`） |
| 下载/速度/网络/黑名单/RPC/做种设置 UI | `SettingsPage`（6 分组） |
| 代理设置（host/port/认证） | `ProxyPage` → `buildSettingsJson` → `proxy-url`（会话启动时应用） |
| 加密模式/端口/RPC 白名单 | 同上，映射进 session config |

### 1.3 有缺陷 / 未完成的路径（⚠️）

| 功能 | 现状 |
|------|------|
| **磁力链接（Magnet）添加** | `AddTorrentPage` 有 Magnet 页签 + 解析 spinner，但 **native 侧无任何 magnet 解析代码**（grep 证实）。调用必然 `PARSE_ERR`。属已知延后项（"magnet-link native parsing"）。**当前等于是坏的入口** |
| 系统磁力链/.torrent 意图 | `module.json5` skill 已声明（5 种 URI scheme），但同样落到失败的 magnet 路径 |
| 真实下载/做种 | 引擎可跑，但 **7.3/7.4 下载完整性从未在真机验证**（需可连 tracker+seed） |
| 代理生效 | 设置已接入 session config，但未做端到端验证 |

### 1.4 死代码 / 未接线（🗑️）

| 模块 | 现状 |
|------|------|
| `services/TransmissionService.ets`（443 行） | 后台服务，**已从 module.json5 移除**（HarmonyOS NEXT system-app-only）。`EntryAbility` 仍在调用 `startUIServiceExtensionAbility` → 每次启动静默失败 |
| `services/WakeLockManager.ets` | 仅被死掉的 TransmissionService 引用 → **实际死** |
| `services/ConnectivityMonitor.ets` | 同上 → **实际死**（网络丢失暂停/恢复、WiFi-only 全部失效） |
| N-API 12 个方法从未被 ArkTS 调用 | `curlDownload`、`torrentGetPiece`、`torrentGetPieceHash`、`torrentSetPiecesHiPri`、`torrentFindFile`、`semCreate/Destroy/Post`、`envUnset`、`stdRedirect`、`hashLength`、`hashGetTorrentHash` |
| `torrentSetPiecesHiPri` | C++ 层本身就是空操作（`FIXME: need 4.1 API`），双层死 |
| NativeBridge 死方法 | `getEncryptionMode()`、`transmissionVersion()`、`hashStringToBytes()` |
| `models/SessionState.ets` | `@Provide sessionState` 注入了但**无任何子页面消费** |
| `entrybackupability/EntryBackupAbility.ets` | 15 行纯日志桩 |

### 1.5 推迟到 v1.1+（⏳，见 docs/06 §11）

UPnP/DLNA/SSDP（9 项）、HTTP 流媒体服务器（7 项）、M3U、监视目录、深色主题、RU 本地化、
RSS、备用 Web UI、双向存储适配器。共 **22 项**，代码中均不存在。

---

## 2. 架构现状

### 2.1 三层结构

```
┌─────────────────────────────────────────────────────────────┐
│  ArkTS / ArkUI 应用层（30 个 .ets，约 7.6K 行）              │
│  pages/ 7 · components/ 11 · models/ 7 · services/ 3        │
│  bridge/ 1 · utils/ 2 · entryability/ 1                     │
├─────────────────────────────────────────────────────────────┤
│  N-API 桥（C++，10 .cc/.cpp + commons.h，约 2.5K 行）        │
│  42 个 N-API 导出 → NativeBridge.ets 暴露 ~28-31 个          │
│  全部调用集中在 NativeBridge 单例（架构约束已被遵守）         │
├─────────────────────────────────────────────────────────────┤
│  libtransmission 4.1 + 依赖（C/C++，18 个 .a，arm64-v8a）    │
│  transmission/openssl/curl/libevent + dht/psl/utp/...        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 数据流（当前真实运行方式）

```
EntryAbility
  ├─ 初始化 PreferencesManager
  ├─ (残留) startUIServiceExtensionAbility(TransmissionService) → 必然失败，已捕获
  └─ 加载 pages/Index（4 个 Tab）
       Index
       ├─ DownloadsPage ── 会话宿主（进程内）
       │    initSession(): defaultSessionConfig()
       │      → applySandboxPaths()   // /storage/... 被覆盖为 filesDir/... 并 mkdir
       │      → TransmissionSession.start(config) → NativeBridge.sessionStart → native
       │    ├─ 1s 轮询: getTorrentStatBriefAll() → TorrentInfo.refreshStats() → UI
       │    ├─ FAB → AddTorrentPage（文件 picker → cache 真实路径 / Magnet ⚠️）
       │    ├─ 长按 → TorrentContextMenu → start/stop/remove/verify/reannounce/location
       │    └─ 文件 → FileTreePage → FileTreeView / FileTreeModel / TorrentFile.setWanted
       ├─ SettingsPage ── 纯 Preferences CRUD（不碰 native）
       ├─ ProxyPage ── 纯 Preferences CRUD
       └─ AboutPage ── NativeBridge.getVersion()（唯一直接调桥的页面）

🗑️ 死分支：TransmissionService → WakeLockManager / ConnectivityMonitor / TSFN 回调
```

### 2.3 关键架构事实

1. **会话在 UI 进程内运行**（`DownloadsPage` 持有 `TransmissionSession`）。原设计的前台服务已移除。
2. **桥接模式被严格遵守**：所有 `native.*` 调用集中在 `NativeBridge.ets`（32 个调用点），组件层只经 `TransmissionSession` 等模型访问。
3. **`runInTransmissionThread` 在调用线程同步执行**（4.0.6 移除 `tr_runInEventThread` 后改为直接执行）——所有种子操作阻塞 UI 线程，含文件 I/O。
4. **设置走「即时生效」**：组件 `@Watch`/`onChange` → `PreferencesManager` 持久化；会话启动时经 `buildSettingsJson()` 映射为 Transmission 4.1 的 kebab-case 键。
5. **`tr_torrentRemove` 异步 fire-and-forget**（分发到会话事件线程），UI 靠 1s 轮询掩盖，同步假设均不可靠。

---

## 3. 文档 vs 代码的失真点（整理时发现的坑）

| 声称 | 实际 |
|------|------|
| CLAUDE.md「~21 个 ArkTS 文件」 | **30 个**（pages 7 + 其余 23） |
| CLAUDE.md「12 个 C++ 文件」 | **10 个 .cc/.cpp + commons.h** |
| CLAUDE.md「40 方法 / 31 公共 NativeBridge」 | native 导出 **42**，NativeBridge **~28-31**（各 agent 计数略有出入，见 §1.4） |
| docs/01「40 方法、OpenSSL 1.1.1l、curl 7.78」 | 42 方法、OpenSSL **3.0.15**、curl **8.5.0**、Transmission **4.1** |
| CLAUDE.md「compatibleSdk 5.0.0/API12」 | 实际 compatible = target = **6.1.1(24)** |
| CLAUDE.md「所有 codex 发现已修复」 | `.ai-review/codex-review.md` 仍列有未解决项（`getPercentDone` 反转、`Err::set` 空指针、无会话线程派发、`tsfnReleased` 竞态、TorrentAdd 返回码混淆、settingsJson 被忽略） |
| CLAUDE.md「third_party_stubs.cc 为空」 | 该文件**已不存在**（4.1 构建消解全部桩） |
| **版本控制** | **不是 git 仓库**，无任何提交历史 |

---

## 4. 清理与加固建议（按优先级）

### P0 — 决策性事项
1. **初始化 git**：`git init` + 首次提交，锁定当前可用基线（项目目前完全无版本控制，任何改动不可回退）。
2. **magnet 添加**：要么实现（原生 `tr_ctorSetMetainfoFromMagnet`/curl 解析），要么**禁用 Magnet 页签**——当前是必然失败的坏入口。

### P1 — 死代码收口（三选一：删除 / 复活 / 明确标记）
3. **服务残留路径**：`EntryAbility.startTransmissionService()` 每次启动静默失败 → 删除该调用，或改成「检测服务能力不可用即跳过」。
4. **WakeLockManager / ConnectivityMonitor**：若确认不做后台服务，删除；若想保留，需在 `DownloadsPage` 的进程内会话里重新接线（唤醒锁对真实下载是刚需——无唤醒锁 CPU 会挂起）。
5. **12 个死 N-API 方法 + NativeBridge 死方法**：prune 或集中注释说明。`torrentSetPiecesHiPri`（C++ 层空操作）建议直接删。

### P2 — 正确性
6. **codex-review.md 未解决项**：`getPercentDone` 反转、`Err::set` 空指针、TSFN 竞态——逐项核对是否真的已修，若未修则修或明确降级记录。
7. **`SessionState` 未消费**：删除或真正接线（顶部状态栏显示会话状态）。

### P3 — 文档
8. 更新 CLAUDE.md 失实计数（§3 表格）。
9. 删掉 `docs/01` 中已过时的引擎版本描述，或标注「历史规划」。

---

## 5. 建议的下一步

用户最常见的两个真实诉求，按本文给出的现状：
- **想立刻稳定可用** → 做 §4-P0（git + magnet 处理），其余保留现状即可。
- **想继续推进 v1.0** → 优先补「进程内会话」缺失的能力：唤醒锁、网络感知、TSFN 状态回调（这三样当前都因服务移除而失效），是功能完整性上最大的真实缺口。
