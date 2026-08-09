# transmissionhm 重构清单（2026-08-09）

> 合并自：docs/09（功能地图）+ docs/10（架构对照）+ RPC/Web 半成品发现 +
> 本次对 `.ai-review/codex-review.md` 的**逐项核实**。
> 清单按可执行性分级，每项标注 位置 / 工作量 / 状态。

---

## 现状一句话

分层和桥接是忠实的，但**引擎工作在 UI 线程上跑**（`runInTransmissionThread` 是无调用方的死代码，
`DEF_TORRENT_OP` 直接调 `tr_*`），有 1 个 P0 用户可见 bug（进度反转），
5 项功能是移植欠账，若干安全边界未校验，文档大量失实，且整个项目**零版本控制**。

---

## ✅ 已修复（基线，勿重复）

| # | 事项 | 位置 |
|---|------|------|
| 0.1 | 添加种子失败：picker `file://` URI → cache 真实路径 | AddTorrentPage.copyPickerUriToCache |
| 0.2 | `/storage` 不存在：applySandboxPaths → filesDir 并 mkdir | DownloadsPage |
| 0.3 | codex-review 已修项（**本会话核实**）：Err::set 空指针、settingsJson 解析、TorrentAdd 返回码、tr_hex_to_binary 长度校验、TSFN re-init 复位 | commons.h/cc、transmission.cc、AddTorrentPage、native_to_arkts.cc |

---

## 阶段 A — 安全基线（S 级改动，当日可完）

| # | 事项 | 为什么 | 位置 | 状态 |
|---|------|--------|------|------|
| A1 | **git init + 首次提交** | 当前零版本控制，任何改动不可回退 | 根目录 | ✅ `0aa0aa0` |
| A2 | **默认 `enableRpc=false`** | 无 Web 前端、无 Web 组件可打开；监听 9091 白担风险；白名单一旦放宽到局域网 + 无认证 = 局域网内可控 | `SessionConfig.ets:78` | ✅ `0aa0aa0` |
| A3 | **移除 EntryAbility 服务启动调用** | `TransmissionService` 已从 module.json5 移除，每次启动必然静默失败 | `EntryAbility.ets:107` | ✅ `0aa0aa0` |
| A4 | RPC 设置 UI 与能力对齐 | SettingsPage 有完整 RPC 组（端口/白名单/认证）但能力不存在，属空壳 | SettingsPage | ✅ `0aa0aa0` |

## 阶段 B — 架构修复（结构性，最高优先）

| # | 事项 | 为什么 | 位置 | 量 | 状态 |
|---|------|--------|------|----|------|
| B1 | **真实事件线程派发** | 引擎 `tr_*` 直接跑在 ArkTS/UI 线程（`DEF_TORRENT_OP` 等）；`runInTransmissionThread`(commons.cc:210) **零调用方**且 sem 空转（post 后立刻 wait）。这是 codex-review P0 + docs/10 §2 的唯一结构性退化 | `commons.cc` + `torrent.cc` 全部 op | L | ✅ `2ca65f8`：全部 tr_* op 路由进事件线程 |
| B2 | **TSFN 竞态收口** | `tsfnReleased` 裸 bool 跨线程读写；用 `release` 而非 `abort`，停止时可能用已释放句柄。re-init 复位已修，竞态本体未修 | `native_to_arkts.cc` | M | ✅ 基线内（`26d3d0f` codex P0）：tsfnMutex 守卫全部句柄访问 + 全 release（无 abort）+ re-init 复位 + freeOnEnqueueFailure |
| B3 | **会话句柄注册表** | `getSession` 信任 JS 传入 BigInt → 野指针；`toPtr` 返回 BigInt(0) 时原生空指针解引用 | `commons.cc` + `NativeBridge.ets` | M | ✅ `d2537c9`：live-session 注册表 + 原子 check-and-erase |

> B1 拆解：方案 A（推荐）pthread + 工作队列重写 `runInTransmissionThread` 为「投递专用线程 + 阻塞等待」，
> 并把所有 op 路由进它（保留同步返回，ArkTS 零改动）；方案 B 转 N-API async + Promise。
> 已实现（`2ca65f8`）。

## 阶段 C — 逻辑正确性（P0/P1 独立 bug，小改）

| # | 事项 | 为什么 | 位置 | 量 | 状态 |
|---|------|--------|------|----|------|
| C1 | **getPercentDone 反转** | 全新种子 `lud==swd` → 返回 1.0，**新种子显示 100% 完成**，污染所有进度/`isFinished`/「已完成」标签 | `torrent.cc:68` | S | ✅ `0c08b18`：进度归一 + isFinished 一致 |
| C2 | **边界校验批量** | `env.cc` 状态未查 + len 越界；`hash.cc` 未校验 40 位 hex；`TorrentGetPieceHash` 未查 ArrayBuffer 长度；`TorrentStatBrief` STOPPED 状态 `stat[i+6..9]` 为未初始化垃圾 | `env.cc` `hash.cc` `torrent.cc` | M | ✅ `0c08b18`：env/hash 越界与 hex 校验补齐 |
| C3 | **SessionStop 双重停止守卫** | 二次 stop 关闭已释放会话 → use-after-free；`tr_sessionClose(…, 15.0)` 可阻塞 15s | `transmission.cc` | S | ✅ `d2537c9`（随 B3 注册表）：unregisterSessionHandle 原子守卫，stop 幂等 |
| C4 | **downloadedEver 求和 + isFinished** | `downloadedEver = haveValid + uploadedEver` 无意义；随 C1 一并修 | `TorrentInfo.ets` | S | ✅ `0c08b18`：downloadedEver = haveValid（注释记录 codex P2） |

## 阶段 D — 功能欠账（移植丢失，按价值排序）

| # | 事项 | 现状 / 参照 | 位置 | 量 |
|---|------|-------------|------|----|
| D1 | **magnet 添加** | ✅ `2c488f4`：`tr_ctorSetMetainfoFromMagnetLink` 原生磁力（BEP9 后台取元数据，立即入列，不再 PARSE_ERR）+ 接受裸 40-hex info-hash；AddTorrentPage 去掉假 resolve spinner | torrent.cc + AddTorrentPage | L |
| D2 | **URL 直加** | ✅ `2c488f4`：`curlDownload` 经 NativeBridge 接线 → AddTorrentPage URL 页签 → 下载到 cache → 走现有文件路径；原生强制 http(s)://（拒绝 file:// 任意写） | curl.cc → NativeBridge → UI | S |
| D3 | **唤醒锁进程内复活** | ✅ `34a0333`：DownloadsPage 1s 轮询按 `hasDownloadingTorrents`（含 CHECK/Wait）变化态 acquire/release BACKGROUND 锁；KEEP_BACKGROUND_RUNNING 权限已在 module.json5，设备拒绝时降级记日志不崩 | WakeLockManager → DownloadsPage 会话 | M |
| D4 | **网络感知复活** | ✅ `34a0333`：DownloadsPage 会话启动后注册 ConnectivityMonitor，lost→`suspend(true)`/available→`suspend(false)`（`tr_sessionSetPaused`），netPaused 转换守卫；wifi_only 偏好门控保留 | ConnectivityMonitor → DownloadsPage | M |
| D5 | HTTP 流媒体（等片/边下边播/M3U） | **决策：延后 v1.1+（已评估）**。无 HttpServerService/任何流媒体代码；L 级旗舰（HTTP Range/Content-Range + 顺序优先级）；CLAUDE.md:94 已列 v1.1+。`torrentGetPiece`/`torrentSetPiecesHiPri` 保留为预留（E1） | 评估 v1.0 范围 → v1.1+ | L |
| D6 | UPnP/DLNA、监视目录 | **决策：v1.1+**（清单自定）；CLAUDE.md:94 已延后（UPnP/DLNA/SSDP、Watch Dirs） | v1.1 | L |
| D7 | Web 控制面 | **决策：不做（v1.0 内）**。依赖 A2=`enableRpc=false`；开回 RPC 撤销安全基线，且无 Web 组件打开入口。若未来 v2 恢复，需逆向开 enableRpc + rawfile 打包轻量 web UI | rawfile + Web 组件 | L |

## 阶段 E — 死代码收口

| # | 事项 | 决策 |
|---|------|------|
| E1 | 12 个死 N-API 方法分类 | ✅ 删 7 纯残留：sem.cc（semCreate/Destroy/Post）整删、stdredirect.cc（stdRedirect）整删、envUnset、hashLength、hashGetTorrentHash；注册 + CMakeLists 同步。**留 4 预留**：torrentGetPiece / torrentGetPieceHash / torrentSetPiecesHiPri / torrentFindFile 加 RESERVED 注释（D5 流媒体/预览储备）。curlDownload 已在 D2 接线，非死 | 
| E2 | WakeLockManager / ConnectivityMonitor | ✅ 随 D3/D4 复活接线（`34a0333`），保留 |
| E3 | TransmissionService.ets | ✅ 已删除：系统独占能力（consumer 设备不可运行），exports（SessionEventType/EventListener）无人 import，其 wake-lock/connectivity 逻辑已由 D3/D4 进程内接管（DownloadsPage） |
| E4 | SessionState 未消费 | ✅ 删 `SessionState` 类 + Index `@Provide sessionState`（全树无 @Consume）；`SessionRunState` 保留（TransmissionSession 在用） |
| E5 | EntryBackupAbility 桩 | **保留**：已注册的系统备份扩展点（module.json5:51），15 行日志桩无害 |

## 阶段 F — 文档校准

| # | 事项 | 结果 |
|---|------|------|
| F1 | CLAUDE.md 失实计数：~21→**30** 个 ets、12→**10** 个 cpp、40→**42** 方法、compatibleSdk 实为 **6.1.1(24)**、third_party_stubs.cc 已不存在、删除「所有 codex 发现已修复」措辞 | ✅ `3aee5f5`：实为 **33 ets / 8 cpp / 35 native 方法 / 32 NativeBridge 方法**，SDK 版本、third_party_stubs.cc、磁力欠账(DONE) 全部校准 |
| F2 | docs/01 引擎版本过时：OpenSSL 3.0.15 / curl 8.5.0 / Transmission 4.1 | ✅ `3aee5f5`：cmake 表 + 依赖树版本号全部修正，另补 libpsl.a / libMadlerCrcany.a |
| F3 | docs/06「v1.1 延后」重标注：**移植欠账**（magnet/流媒体/UPnP/监视目录/URL 添加）vs **系统墙**（开机自启/前台服务） | ✅ `3aee5f5`：延后表加「分类」列 + 表下结论注；5.6 URL/magnet 添加标为完成（D1/D2） |
| F4 | 本清单链接进 docs/09、docs/10 | ✅ 已在（docs/09:11-12、docs/10:157），核验无悬挂链接 |

---

## 建议执行序

1. **C1（先做）**：S 级改动修一个 P0 用户可见 bug（新种子显示 100%）。
2. **A1 → A2 → A3**：当日完成，锁基线 + 关掉多余监听 + 删必然失败的调用。
3. **B1（独立分支）**：结构性修复，量最大，做完后 UI 线程不再被引擎阻塞。
4. **C2 → C3 → C4 → B2 → B3**：安全边界 + 竞态。
5. **D1 + D2**：两个「低投入高价值」欠账（magnet、URL 添加）。
6. **E + F**：死代码收口 + 文档校准，可穿插。

## 验证基线

- 每阶段后：`./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon`
- 真机回归：`assembleHap -p module=entry@ohosTest` + `hdc install` + `aa test`（**222 用例** — E4 删 SessionState 类后随删 10 个死用例，重点 7.1 会话 / 7.2 添加+列表 / 7.8 DnD / 7.9 并发 / 7.11 迁移 / 7.12 删除）
- 安全项：A2 后 `hdc shell` 确认 9091 不再监听
