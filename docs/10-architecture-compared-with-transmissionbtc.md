# 对照 transmissionbtc：架构再审视（2026-08-09）

> 本文对照源头项目 **transmissionbtc**（Android v1.3.10，`/Users/xiphis/projects/transmissionbtc`）
> 的完整架构（56 个 Java 类 + 40 个 JNI 方法），结合 `docs/09` 的功能地图现状，
> 对 transmissionbtm 做一次**架构方向**的再审视。
>
> 依据：本会话对 transmissionbtc 应用层 + native 层的两份逐文件盘点（2026-08-09）。

---

## 0. 结论先行

transmissionbtm 是 transmissionbtc 的**忠实骨架 + 退化线程 + 功能子集**。三层结论：

1. **线程模型退化（结构性，最严重）**：transmissionbtc 的每个 JNI 调用都把工作
   **注入 libtransmission 事件线程**执行（调用线程只是信号量阻塞等待），UI 线程从不跑引擎工作；
   我们的 N-API 桥把工作**直接在调用线程（= UI 线程）就地执行**。
   根源：原版依赖的 `tr_runInEventThread` 在上游 4.0.x 被移除，移植时降级为就地执行。
2. **后台三件套集体失效**：唤醒锁、WiFi/以太网感知、开机自启在原版是完整能力；
   在我们这里随前台服务移除而全部变成死代码。前两者**可在进程内会话里复活**，后者是系统墙。
3. **功能子集**：原版实现的 20 项功能我们移植了核心 10 项左右。**磁力链接、HTTP 流媒体、
   UPnP/DLNA、监视目录、按 URL 添加**这 5 项是原版已有、我们却归为「v1.1 延后」的——
   它们不是新功能，是**移植时丢失的欠账**。

好消息：**丢的都是能补回来的**。native 层 12 个「死方法」里有一半是给这些功能预留的，
补接线比重写成本低得多。

---

## 1. 架构对照总表

| 维度 | transmissionbtc | transmissionbtm | 对照 |
|------|-----------------|----------------|------|
| 整体模式 | 单进程 MVC + DataBinding | 单进程 ArkTS 组件化 | 同构 |
| 会话宿主 | 前台 Service（START_STICKY）持有 | DownloadsPage（进程内）持有 | 因系统约束被迫改变 |
| 引擎访问 | `Native.java` 全静态 JNI 包装 | `NativeBridge.ets` 单例包装 | 同构 |
| 会话句柄 | `long`（opaque） | `number`（opaque） | 同构 |
| 状态轮询 | `TorrentsList` 1s `Handler.postDelayed` | DownloadsPage 1s `setInterval` | 同构 |
| Tab 结构 | Downloads/Settings/**WatchDirs**/Proxy/About | Downloads/Settings/Proxy/About | 少了 WatchDirs |
| 线程模型 | JNI 阻塞等待 + **事件线程执行** | **调用线程就地执行** | **退化** ⚠️ |
| 事件回调 | rpcFunc → JNI attach → Handler.post(main) | TSFN 已实现但未消费 | 未接线 |
| 文件系统 | SAF 替换钩子（`tr_android_*` → StorageAccess） | POSIX 沙箱路径 | 方向不同、各自合理 |
| 设置 | SharedPreferences 枚举键 | preferences 40+ 键 | 同构 |
| 配置流入引擎 | tr_sessionLoadSettings + 启动参数 | buildSettingsJson + applySandboxPaths | 同构（4.1 API 变化） |
| 会话管理器 | `Transmission` 集中类（句柄+线程池+监视+唤醒+HTTP） | 分散在 DownloadsPage + 模型层 | 我们缺集中管理器 |

---

## 2. 线程模型：唯一需要正视的结构性退化

原版 `commons.cc` 的 `runInTransmissionThread`（**全部**状态/变更调用都走这里）：

```
JNI 调用线程:  分配 Future(sem_t) → tr_runInEventThread(session, ...) → sem_wait 阻塞
事件线程:      runInEventThread 执行 func → sem_post 解除阻塞
```

保证：**工作永远跑在 libtransmission 事件线程**，UI 线程只干等。

我们的 `commons.cc`：

```
调用线程: runFutureFunc(&f)   ← 直接在调用线程执行
```

`tr_runInEventThread` 在传输上游 4.0.x 被移除，移植时直接降级为就地执行。后果：
- 所有种子操作（含文件 I/O、校验）**阻塞 UI 线程**，长任务卡界面；
- libtransmission 内部状态原本只在事件线程被触碰（天然线程安全），现在我们失去了这层保证；
- 这是 codex-review P0「async session-thread dispatch」的根源，现在被原版架构坐实。

**恢复路径（按成本排序）：**
- **A. 自造事件线程（推荐）**：用 pthread + 队列把 `runInTransmissionThread` 的工作投递到
  专用线程执行，等价于重实现 `tr_runInEventThread`。改动集中在 `commons.cc` 一个函数；
  保留同步返回语义，ArkTS 端零改动。
- B. N-API async：改成 Promise + `napi_async_work`，ArkTS 端 await。改动大但 UI 完全不阻塞。
- C. 维持现状：真机 E2E 已验证种子操作可用（沙箱内文件 I/O 通常快），
  **对当前验收可接受**，但大规模文件操作有卡死风险。

---

## 3. 功能差距分析（原版有 → 我们没有）

| 原版功能 | 原版实现 | transmissionbtm | 差距定性 |
|----------|----------|----------------|----------|
| 磁力链接添加 | `torrentMagnetToTorrentFile`（native 完整实现，元数据下载 + 取消信号量） | **无 native 支持，UI 页签是坏的** | **移植丢失 → 必须补** |
| HTTP 流媒体服务器 | SimpleHttpServer + TorrentHandler（Range/等片/优先级） | 延后 v1.1 | 移植丢失（原版旗舰） |
| UPnP/DLNA/SSDP | SsdpServer + Descriptor + ContentDirectory | 延后 v1.1 | 移植丢失 |
| 监视目录 | FileObserver + 轮询 + 多目录映射 | 延后 v1.1 + 无 Tab | 移植丢失 |
| 按 URL 添加 | `Native.curl()`（http/https/ftp） | `curlDownload` 死方法，未接线 | 移植丢失 |
| 种子内选文件再添加 | DownloadTorrentActivity（先选文件后添加） | 先添加后文件树 | UX 差异 |
| 分享意图接收入口 | 5 种 URI scheme + 手动 URL 对话框 | 声明了 skill 但落到坏 magnet 路径 | 半坏 |
| 开机自启 | BootOrUpdateReceiver + START_ON_BOOT | 不可能（consumer 设备） | 系统墙 |
| WiFi/以太网仅限 | ConnectivityChangeReceiver + `wifi_eth_only` | ConnectivityMonitor 死 | 可进程内复活 |
| 唤醒锁 | PowerLock（PARTIAL_WAKE_LOCK + WIFI_MODE_FULL） | WakeLockManager 死 | 可进程内复活 |
| M3U 播放列表 | PlaylistHandler | 延后 v1.1 | 移植丢失 |
| RSS | 仅 TODO 桩 | 延后 v1.1 | 两边都延后 → **对齐** |
| 深色主题 | 无 | 延后 v1.1 | 原版也没有 → 对齐 |
| RU 本地化 | 仅 RU + EN | 延后 RU | 基本对齐 |

**结论**：docs/06 里我们写的「v1.1 延后」实际分两类——**移植欠账**（magnet、HTTP 流媒体、
UPnP/DLNA、监视目录、URL 添加，原版 100% 实现过）和**系统墙**（开机自启、前台服务）。
前者是「能补的债」，后者是「过不去的墙」。

---

## 4. 桥接层对照（40 JNI 方法 vs 42 N-API 导出）

命名与功能**几乎一一对应**，桥接层移植忠实度很高。差异：

- **我们丢了原版有但未移植的**：`torrentMagnetToTorrentFile`（magnet）、
  `torrentListFilesFromFile`（添加前预览文件）、`transmissionHasDownloadingTorrents`（唤醒锁依据）、
  `torrentGetError`（错误字符串）、`transmissionListTorrentNames`。
- **我们有 12 个死方法**，其中 `curlDownload` / `torrentGetPiece` / `torrentGetPieceHash` /
  `torrentSetPiecesHiPri` / `torrentFindFile` **对应原版真实功能**（URL 添加、等片流媒体）——
  它们是「为移植功能预留但从未接线」，**不是纯粹的垃圾，别急着删**。
  其余死方法（sem/env/stdRedirect/hashLength）才是真正无价值的残留。

---

## 5. 原版值得「借」、我们目前缺的架构组件

1. **`Transmission` 集中管理器**：原版一个类管会话句柄 + 线程池 + 监视目录 + 唤醒锁 + HTTP 服务。
   我们散在 DownloadsPage（会话）+ 模型层。建议抽 `TransmissionManager` 单例，收拢会话、唤醒锁、
   网络感知、可选服务的生命周期——这也为「进程内复活三件套」提供挂点。
2. **线程池**：原版 ExecutorService（0 核 / 30 最大 / CallerRunsPolicy）+ ScheduledExecutorService。
   我们完全没有；若做 §2-A（自造事件线程）则部分替代。
3. **URL 直加**：native `curl` 已存在，只需 ArkTS 接线（URL → 下载到 cache → 走现有文件添加路径），
   成本低、原版有。
4. **预添加文件选择**：原版添加前先列文件打勾；我们添加后才进文件树。可作体验改进，非必须。

---

## 6. 修正后的优先级（相对 docs/09）

| 级别 | 事项 | 说明 |
|------|------|------|
| **P0** | git init | 不变，任何改动不可回退 |
| **P0** | magnet 实现 | **从「可选项」升级为「移植欠账必须补」**（原版有完整 native 实现可参照） |
| **P0.5** | 恢复事件线程派发（§2-A） | 唯一结构性退化，codex-review P0 的正解；改 commons.cc 一处 |
| **P1** | 唤醒锁/网络感知 | 不是「删或留」，而是**必须在进程内会话里复活**（原版是下载完整性的刚需） |
| **P1** | 「v1.1 延后」重新标注 | magnet/HTTP流媒体/UPnP/监视目录/URL添加 = **移植欠账**，v1.0 范围可调整 |
| **P2** | 12 个死方法先别删 | 先接线 curl（URL 添加），评估 torrentGetPiece 家族（等片流媒体），其余再 prune |
| **P3** | CLAUDE.md 失实计数 | 不变（docs/09 §3 表格） |

---

## 7. 一句话总结

transmissionbtm = transmissionbtc 的**忠实骨架 + 退化线程 + 功能子集**：
分层和桥接跟原版同构，但丢了原版赖以流畅的事件线程派发，以及 magnet / 流媒体 / UPnP / 监视目录
五个已实现功能。**丢的都是能补回来的**——native 层死方法里一半是预留，补接线比重写便宜得多。

---

## 8. 落地

按优先级拆解的可执行任务清单见 [docs/11-refactoring-checklist.md](11-refactoring-checklist.md)。
