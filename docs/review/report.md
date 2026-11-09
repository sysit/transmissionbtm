# 架构与代码 Review — 2026-11-08

## 分级口径

按**失败可见性**分级，不按严重度。一次崩溃比一次静默错误好排查，所以"静默"权重最高：

| 级别 | 含义 | 用户感知 |
|---|---|---|
| **S1 静默** | 错了但没人知道，行为静默降级 | 功能"就是不工作"，无任何线索 |
| **S2 误导** | 报错了，但报的是假信息 | 看到错误却指向错误的方向 |
| **S3 崩溃** | 直接挂掉 | 立刻可见 |
| **S4 体验** | 功能正确但手感不对 | 能察觉 |

---

## 一、本轮修复的缺陷

| # | 级别 | 位置 | 症状 | 根因 | 处置 |
|---|---|---|---|---|---|
| 1 | **S2** | `AddTorrentPage.runCurlDownload` | URL 添加种子失败，弹窗 `下载失败：object Object` | `@Concurrent` worker 抛出的错误跨 taskpool 边界时，**类名和 message 双双被剥离**，主线程 `String(e)` 只剩 `[object Object]` | 把 try/catch 移进 worker 内部，返回字符串（字符串能跨边界） |
| 2 | **S1**（被 #1 掩盖） | `curl.cc:CurlDownload` | HTTPS 种子地址 100% 失败 | 交叉编译的 libcurl 8.5.0 在 OH 上**没有 CA 信任库**，`curl_easy_perform` 返回 `unable to get local issuer certificate` | 新增可选第 4 参 `caBundle` → `CURLOPT_CAINFO`；`rawfile/cacert.pem`（Mozilla，118 证书）随包分发 |
| 3 | **S1**（被 #2 掩盖） | `AddTorrentPage.ensureCaBundleInCache` | 证书路径 `error setting certificate file: /rawfile/cacert.pem` | `getContext().resourceDir` 在真机上**返回空串**，路径塌缩成 `/rawfile/cacert.pem` | 改用 `resourceManager.getRawFileContentSync` 读进内存，写入 `cacheDir`，传物理路径 |
| 4 | **S1** | `SessionController.hasDownloading` | native 抛异常时静默 `return false` | 这个返回值**直接决定保活锁的释放**；`false` = "没有下载" → 放掉 continuous task → 系统 ~5s 后冻结进程 → 后台断流 | 改为 `return true` + `hilog.error`（失败时保守保活） |
| 5 | **S1** | `TransmissionSession.applyStatBrief` | 5s 轮询里 `catch { return; }` | stat 调用一旦持续失败，列表**冻结在最后一次好值**，日志里一个字都没有 | 补 `hilog.error`；保留"沿用旧值"的降级 |
| 6 | **S3 隐患** | `torrent.cc:getInt64FromBigInt` | 无 | `uint64_t u;` **未初始化**，`napi_get_value_bigint_uint64` 失败时返回栈上垃圾 → 野指针 | 全仓零调用的死代码，**直接删除** |
| 7 | S4 | 11 个文件、34 处点击 | 所有点击无任何反馈 | 未使用 ArkUI 的 `clickEffect` | 统一 `CLICK_EFFECT`（LIGHT / 0.92），常量在 `utils/constants.ets` |
| 8 | S4 | `TorrentCard.build()` | 展开后点"暂停/重新通报"等小按钮，**整张卡片**跟着缩放；卡片收起与按钮动作**推断会同时触发**（E0：缩放已实测，双触发未单独观测） | 展开切换的 `clickEffect` + `onClick` 挂在卡片根节点上，把详情区一起包了进去 | 把切换下移到"头部+进度+统计"内层容器；详情区与按钮移出该容器。真机验证（E3）：头部可切换 / 详情区非按钮不切换 / 按钮动作正常。同类冒泡在 `SettingsResetDialog` 上以代码可证（E1），见本轮 #15 |
| 9 | S4 | `TorrentCard.ActionButton` | 40×36 的小按钮上，`scale 0.92 / LIGHT` 的缩放几乎看不出来 | 小控件上纯缩放的信噪比过低 | 按钮改用 `MIDDLE / 0.85`，并加 `stateStyles({ pressed: .opacity(0.45) })` 压暗整个按钮。`stateStyles` 必须挂在持有 `onClick` 的节点上（挂在子 `Text` 上不触发）。**截图未能验证**：列表项的 500ms 长按会先抢走触摸打开菜单，`snapshot_display` 抓不到按下帧 |

### 共同模式

#1 是**元缺陷**：它把 #2、#3 两个真实故障伪装成一句 `[object Object]`。三层问题串成一条链，每层都把下一层的证据藏起来。这是本项目最高频的失败模式 —— 不是"逻辑写错"，而是"错了之后现场被销毁"。

---

## 二、静态审计（已固化为回归门禁）

`scripts/audit.mjs`，10 类检查，退出码非 0 即失败：

```bash
node scripts/audit.mjs          # 只看阻塞项
node scripts/audit.mjs --strict # 连建议项一起列
```

| 检查 | 抓什么 | 现状 |
|---|---|---|
| `args-uninit` | C++ 参数在使用前未初始化 | **0 阻塞**（已负向测试） |
| `resource-pairing` | `setInterval`/监听器 acquire 与 release 配对 | **0 阻塞**（已负向测试） |
| `state-styles` | `stateStyles` 未挂在持有 `onClick` 的节点上 | **0 阻塞** |
| `error-masking` | catch 里既不取 `.message`/`errText` 也没注释 | **0 阻塞**（14 条为带注释的刻意静默，已逐条确认） |
| `napi-drift` | C++ 注册 ↔ `Index.d.ts` ↔ ArkTS 调用三方漂移 | **0 阻塞**，28/28/28 对齐 |
| `rstring` | `$r('app.string.*')` 在 `base` / `zh_CN` 缺键 | **0 阻塞**，195 个键两语言齐全 |
| `build-config` | `compatibleSdkVersion > targetSdkVersion`；产品 `signingConfig ≠ "default"` | **0 阻塞**，6.0.0(20) ≤ 6.1.1(24)，`default` |
| `fmt-abi` | 桥侧 vendored fmt 与引擎构建树的 fmt 版本不一致 | **0 阻塞**，12.1.0 = 12.1.0（已负向测试：改成 90000 立即阻塞） |
| `hardcoded-text` | `.ets` 里的中文硬编码字面量 | **0 阻塞** |
| `napi-status` | 丢弃返回值让用户参数被静默默认（建议项，仅 `get_value_*`/`get_arraybuffer_info` 等读取类调用） | 30 条建议项，**逐条看过，均为误报** |

`napi-status` 的 30 条：25 条是 `napi_get_cb_info`（正常回调下不会失败）；另外 5 条是真正的取值调用，但都在**调用后校验了输出指针**而不是状态码 —— `torrent.cc:249` 的 `idxData != nullptr && idxByteLen % 4 == 0`、`:264` 的 `hashData = nullptr` 预置、`:809` 的显式抛错。这是等价且更稳的写法（同时挡住了"传对了类型但长度不对"的情况），不构成缺陷。

---

## 三、已复核、未发现问题的项

| 项 | 结论 |
|---|---|
| ArkTS 硬编码中文 | 0（非注释） |
| N-API 三方对齐 | 28 注册 = 28 声明 = 28 调用 |
| `$r` 资源覆盖 | 两语言 0 缺键；14 个已定义未使用（module.json5 标签/权限理由） |
| 构建配置不变量 | 两条都满足 |
| `setInterval` / `clearInterval` 配对 | 1:1（`SessionController` 5s 轮询） |
| TSFN `nativeToArktsInit` / `Release` 配对 | 在 `DownloadsPage` 178/202 行成对出现 |
| `FileTreeView` 嵌套点击冲突 | 无 —— 文件行本身没有 `onClick`，`Toggle` 不嵌套在可点容器里 |
| worker 跨 heap 访问单例 | `DownloadsPage` / `AddTorrentPage` 的 `@Concurrent` 都走 `*ByPtr` 静态方法，未触碰 `sessionMap` |

---

## 四、遗留观察（未改，供决策）

### 4.1 `runCurlDownload` 在 worker 里用 `getInstance()` — 潜在陷阱

`AddTorrentPage.ets:41` 的 `@Concurrent` 函数调的是 `NativeBridge.getInstance().curlDownload(...)`，而不是像其他 worker 那样调静态方法。

- **今天不构成缺陷**：`NativeBridge` 的构造函数只调 `getVersion()`，`curlDownload` 也不碰 `sessionMap`，所以 worker 里那份独立单例能正常工作（已真机验证）。
- **风险**：`NativeBridge.ets:232-237` 的注释明确写了"只能在 `@Concurrent` 里用 `*ByPtr` 静态方法"。这里破例了。将来若有人给 `curlDownload` 里加任何 session 相关逻辑，URL 添种会在 worker 里静默抛 `No live session`。
- **为何没改**：这是刚验证通过的关键路径，改动需要重新跑一遍真机 URL 添加。建议下次动这个文件时顺手改成静态方法。

### 4.2 文件树的点击区域

`FileTreeView.buildFileItem` 里文件行（40px 高）**整行不可点**，只有 24×24 的复选框能点。目录行相反 —— 整行可点展开，但没有勾选入口。两类行的交互模型不一致。

若要让整行可点：行加 `onClick` + 复选框加 `.hitTestBehavior(HitTestMode.None)`（OH 的 `ClickEvent` 没有 `stopPropagation`，否则会双触发）。需要真机回归。

### 4.3 未覆盖的运行时边界

本轮做的是**静态**审计 + 已发生故障的修复。以下 8 条边界**没有**自动化探针，仍靠人工：

1. taskpool worker 错误保真（已修，但没有回归测试锁住）
2. N-API 传错参数类型 —— 是抛异常还是 UB？
3. `cacheDir` 写满 / 只读
4. 证书过期后的 URL 添加
5. release 签名 × 真机安装
6. `zh_CN` / `en-US` 切换后的 `$r` 实际渲染
7. 前后台切换 + 保活锁竞争
8. 从旧版本升级（preferences schema 漂移）

要补的话，最小可用集合是 1、2、4 —— 三条都踩过坑，且都能写成 `ohosTest` 用例。

---

## 五、验证状态

| 项 | 状态 |
|---|---|
| 宿主 vitest | **102/102 通过**（新增 settings-JSON 契约 4 条 + LegacyProxyCipher 信封 1 条） |
| debug HAP 构建 | **BUILD SUCCESSFUL** |
| 真机启动（Pura 80 / 4VM0125513000074） | 干净：`NativeBridge v1.0.2` → `DownloadsPage aboutToAppear` → `Session started, id=1`，无应用层报错 |
| 真机 ohosTest 225/225 | **本轮未重跑**（改动仅消息格式化、两处日志、一个死函数，未触及测试断言） |
| 2026-11-08 批次 ohosTest | **225/225 通过**（Pura 90 API24 模拟器，22:10）。首跑在第 213 例 SIGSEGV（#29 fmt ABI 漂移），对齐头文件后全绿 |
| URL 添加端到端 | 本轮修复前已验证通过；`errText` 重构后未重跑 |

---

## 六、结论

- 静态层面：**当前全绿**，6 类低级错误已被 `scripts/audit.mjs` 锁住，可挂 pre-commit。
- 本轮实际修掉 7 个缺陷，其中 6 个是"静默"或"误导"级别 —— 印证了分级口径：**这个项目的风险不在算法，在失败现场的保真度**。
- 最大的未解风险是 §4.3 的运行时边界。它们不是代码 bug，是"没有测试守着，下次改动可能悄悄退化"。

---

## 七、2026-11-08 体系化遍历批次

按 `method.md` 的全集枚举 + I1–I7 遍历得到。逐单元覆盖见 `ledger.md`。

| # | 级别 | 位置 | 缺陷 | 证据 | 处置 |
|---|---|---|---|---|---|
| 10 | **S1** | `transmission.cc` 保存 settings | 代理密码明文写进 `settings.json` | E1：引擎合并顺序为 默认值 → 文件 → 客户端快照 → **实时会话设置最后**，保存前的 strip 被实时值覆盖 | 保存后重写文件，删除 `proxy-url` |
| 11 | **S1** | `TransmissionSession.updateSettings` | 任意设置项实时下发都会把 `download-dir`/`incomplete-dir` 改回 `/storage/...`，新课种子写入不可用目录 | E1：UI 启动时解析沙箱路径但从不持久化 | 实时下发不再携带目录键 |
| 12 | **S1** | `HukProxyCipher.encrypt` | HUKS 失败时退回明文，`PreferencesManager` 把原始密码落盘 | E1 | 改为抛错，写入失败而不是泄露 |
| 13 | **S1** | `ProxyCipher`（legacy） | 把 HUKS 信封原样返回，UI 当密码发给代理 | E1 | 识别前缀后返回 `null` |
| 14 | **S1** | `TransmissionSession` alt-speed | 启用限速后 `alt-speed-time-enabled` 从未发送，引擎调度器默认关闭 → 窗口被忽略、全天限速 | E1 | 随 `alt-speed-enabled` 一起发送 |
| 15 | **S1** | `TransmissionSession` ratio | `JSON.stringify(3.0)` 输出整数，引擎序列化器只接受 real → `ratio-limit` 被静默丢弃 | E1 | `asJsonReal()` 保证 real 编码 |
| 16 | **S1** | `NativeBridge.torrentSetFileWanted` | 全选时发送空索引数组，`tr_torrentSetFileDLs` 遍历空表 = no-op，之前跳过的文件仍不下载 | E1 | 全选发送全部索引 |
| 17 | **S2** | `SettingsResetDialog` | 遮罩 `onClick` 挂在根 Column，卡片点击冒泡 → 点“确认”同时触发取消 | E1 | 遮罩改为 Stack 内同层兄弟 |
| 18 | **S2** | `ConnectivityMonitor.start` | 冷启动即处于非 WiFi/非白名单时，`wasAvailable` 初值 true 且判定只在网络切换时触发 → WiFi-only 永不生效 | E1 | 启动即评估一次 |
| 19 | **S3** | `commons.cc:infoFromFile`、`torrent.cc:TorrentListFilesFromFile` | `tr_ctorNew(nullptr)` 在引擎内部无条件解引用 session → 必崩 | E1 | 改用无会话的 `tr_torrent_metainfo::parse_torrent_file` |
| 20 | **S3** | `torrent.cc:torrentGetFileStat` | 片段索引未钳制，越界读 | E1 | 钳到 `pieceCount-1`；`pieceCount==0` 时返回空 |
| 21 | **S3** | `torrent.cc:torrentSetDnd` | 文件索引未做上界校验，`tr_file_index_t` 回绕 | E1 | 逐索引校验，越界即抛错 |
| 22 | **S3** | `transmission.cc:SessionStop` | `waitSessionIdle` 等 15s 后无论结果都 `tr_sessionClose`，在途 dispatch 使用已释放会话 | E1 | 超时则不关闭、重新登记句柄并抛错 |
| 23 | **S3** | `curl.cc:CurlDownload` | 目的路径校验失败分支漏 `free(caBundle)` | E1 | 补 free |
| 24 | **S1** | `DownloadsPage` 复制循环 | 源 fd 在目标 open 抛错时泄漏（每个失败文件一个） | E1 | try/finally 嵌套 |
| 25 | **S1** | `SessionController.refresh` | `stop()` 后仍可 `reload()`，读已关闭会话抛错 → `updateKeepAlive` 误判“仍在下载” → 重新 acquire 无人释放 | E1 | `_started` 门禁 + 保留上次列表 |
| 26 | **S1** | `SessionController` acquire | `stop()`+`start()` 后旧的 acquire 完成回调清掉新请求的 `acquiring` 标志；停止后完成的 acquire 无人 release | E1 | 身份判定 + 完成后复查 `_started` |
| 27 | **S2** | `ConnectivityMonitor.destroy` | `start()` 在 `createNetConnection` 成功后失败，`isStarted=false` 但连接与 3 个监听器仍在 | E1 | 以 `netConn !== null` 为资源门禁；catch 中 `destroy()` |
| 28 | **S2** | `AddTorrentPage` / `DownloadsPage` 孤儿清理 | 会话未启动时按钮可用，操作静默失败；添加流程无重入锁 | E1 | `isAdding` 门禁 + `isStarted` 门禁 + 提示文案 |
| 29 | **S3** | `cpp/third_party/fmt` vs `libtransmission.a` | 桥侧 vendored fmt 9.0.0，引擎库内是 fmt 12.1.0；首次在桥代码里构造带 fmt 成员的引擎类（`tr_torrent_metainfo`）就堆损坏，随后引擎线程 SIGSEGV | E3：模拟器 ohosTest 第 213 例 `App died`，fault log 栈顶 `tr_torrent_metainfo::~… → fmt::basic_memory_buffer::deallocate` | 用引擎树里的 fmt 12.1.0 头替换；CMakeLists 注明版本必须一致。**修复后 225/225** |

### 被拒的发现

- “tracker announce 绕过代理”：不成立。`announcer-http.cc` 走 `tr_web::FetchOptions`，`web.cc:640` 同样设置 `CURLOPT_PROXY`。**agent 发现必须逐条复核后才可入账。**

### 结论变化

本轮把“状态类”缺陷（会话生命周期、关闭顺序、目录归属、凭据落盘）从 0 覆盖补到全量；它们共同的特征是**编译与单测都看不出来**，只有遍历才暴露。

---

## 八、遗留发现的关闭（2026-11-08，13 条全部结案）

分批执行：B1（D9/D10/D11/D12）→ B2（D1/D5/D4/D6/D7）→ B3（D3/D13）→ B4（D2）→ B5（D8 复核）。

| 编号 | 级别 | 关闭方式 | 证据 |
|---|---|---|---|
| D1 | S1 | 各页面在加载/持久化失败时给出错误面：`SettingsPage`/`ProxyPage`/`DownloadsPage`/`AddTorrentPage` 捕获后提示，`Preferences` getter 仍返回默认值并 hilog | 宿主 `vitest` 覆盖 `Preferences` 失败分支；**设备只冒烟了正常路径，未构造存储失败** |
| D2 | S1 | `DownloadsPage.refreshBlocklist`：缓存超过 7 天 → taskpool 内 `curlDownload`（CA bundle 从 rawfile 拷到 cacheDir）→ 引擎线程 `tr_blocklistSetContent` 解析成 `blocklist.bin` | 设备：日志 `Blocklist rules loaded: 2`；`blocklists/blocklist.bin`（109 B）落盘；再次启动走 `fresh && ruleCount>0` 早退，无下载任务（引擎自己从磁盘恢复）。**未加设置页「立即更新」入口**（需把 live sessionId 穿到 SettingsPage，不值当），URL 变更靠下次启动生效 |
| D3 | S1 | 文件列表解析整体移入 taskpool（`torrentListFilesByPtr` / `torrentGetFileStatByPtr`，主线程只传 BigInt 会话指针） | 设备：文件树渲染 3 个文件的名称/大小/进度/开关；取消勾选一个 DND 后重新进入文件树仍保持 |
| D4 | S2 | `EditSetting` 增加 `minValue`/`maxValue`，越界 toast 且对话框不关闭 | 代码 + 宿主测试；设备上数值路径通过 D8 的 51414→51415 操作间接跑过 |
| D5 | S2 | `applyValue` / `SelectSetting` 先持久化再改显示，写失败回滚并 toast | 同上；`preferences` 宿主测试覆盖写失败 |
| D6 | S2 | `ProxyPage` host/port 走 `validate` 回调，非法格式不落盘 | 代码 + 宿主 `preferences-proxy-cipher` 测试 |
| D7 | S2 | `Preferences` 解密失败置标记，`ProxyPage` 提示重新输入密码 | 同上 |
| D8 | S2 | **E0，未改代码。** 本段在模拟器上真实构造了原判场景 | Peer port 51414→51415 保存后重开对话框，预填 **51415**（跑的正是未修复的旧代码）；Language 由 System default 改 English 后重开，高亮 **English**。结论：`CustomDialogController` 每次 open 会重新求值 builder / 重建 dialog 节点，`aboutToAppear` 重跑，缓存控制器不会陈旧 —— 原判 E0 成立 |
| D9 | S2 | `SessionStop` 把设置快照与保存调度到会话自己的事件线程（`runInTransmissionThread`） | 代码（`transmission.cc:279-319`）；并发窗口靠人为时序构造，**未做设备复现**，正确性按调用序保证 |
| D10 | S2 | `commons` 记录每个 live session 的 config dir，`SessionStart` 拒绝同目录第二次 start | 代码（`commons.cc:278`、`transmission.cc:142`） |
| D11 | S3 | 所有 `napi_create_arraybuffer` 创建失败都判 `napi_status` | 代码（`torrent.cc:587`、`torrent.cc:745`），`napi-status` 审计规则 0 命中 |
| D12 | S2 | `torrentFindByHash` 注明 `-1` 非合法 id，禁止直接喂给 `getTorrent` | `NativeBridge.ets:184` |
| D13 | S2 | `SessionController.sessionId` 仅 `start()` 赋值，页面拿 attach-only id；文件树用 id 而非直接持有会话 | 设备：Downloads → 文件树 → 返回后列表操作正常 |

收尾验证：`node scripts/audit.mjs` **BLOCKING 0**（48 advisory）；宿主 `vitest` **106/106**；`assembleHap` debug **BUILD SUCCESSFUL**。

### 自捕回归

修复 #11（实时下发不再带目录）时，`incomplete-dir` 被一并从 **启动** 路径移除了 —— 它没有 native 参数，只能靠 JSON 下发，结果“未完成目录”设置变成静默失效。收尾复核时发现并修正：启动 JSON `includeDirs=true`，实时下发保持 `false`，并加宿主测试锁住两条路径。**教训：修“某一路径不该带 X”时，必须逐条检查 X 在各调用路径上的既有语义。**
