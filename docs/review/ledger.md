# 覆盖账 — 2026-11-08

> 矩阵单元格：`C` = 已查、无发现；`N` = 有发现（对应 `report.md` 缺陷编号或标注"遗留"）；
> `—` = 未审。证据等级 E1 = 代码可证，E0 = 推断，E3 = 真机实测。
> 机械可判项（I4/I6 文案/I7 资源配对）由 `scripts/audit.mjs` 全量扫过，等级 E1。

## ArkTS 单元（46）

| 单元 | I1 | I2 | I3 | I4 | I5 | I6 | I7 | 备注 |
|---|---|---|---|---|---|---|---|---|
| bridge/NativeBridge.ets | C | C | **N** | C | C | C | C | DnD 全选发空数组 = no-op（已修）；sessionMap 仅主线程，worker 走 `*ByPtr` |
| components/add/FilePreview.ets | C | C | C | C | C | C | C | 纯展示 |
| components/add/TorrentStatusBanner.ets | C | C | C | C | C | C | C | 纯展示 |
| components/privacy/PrivacyDialog.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/EditSetting.ets | C | C | C | **N** | C | C | C | 遗留 #7 数值无上下界；#11 赋值 fire-and-forget |
| components/settings/SandboxSettingRow.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/SelectSetting.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/SettingsErrorBanner.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/SettingsGroup.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/SettingsLoadingState.ets | C | C | C | C | C | C | C | 纯展示 |
| components/settings/SettingsResetDialog.ets | C | C | C | C | C | C | C | 遮罩冒泡 → 同层 Stack（已修） |
| components/settings/ToggleSetting.ets | C | C | C | C | C | C | C | 纯展示 |
| components/torrent/FileTreeView.ets | C | C | C | C | C | C | C | 行内无 onClick，无嵌套点击冲突 |
| components/torrent/TorrentCard.ets | C | C | C | C | C | C | C | 点击分层与 `stateStyles` 已验证（E3） |
| components/torrent/TorrentContextMenu.ets | C | C | C | C | C | C | C | — |
| components/torrent/TorrentVM.ets | C | C | C | C | C | C | C | `@ObjectLink` 包装，5s 刷新 |
| components/ui/EmptyState.ets | C | C | C | C | C | C | C | 纯展示 |
| components/ui/ProgressBar.ets | C | C | C | C | C | C | C | 纯展示 |
| components/ui/StatChip.ets | C | C | C | C | C | C | C | 纯展示 |
| entryability/EntryAbility.ets | C | C | C | C | C | C | C | 语言覆盖 + 状态栏属性 |
| entrybackupability/EntryBackupAbility.ets | C | C | C | C | C | C | C | 无业务逻辑 |
| models/FileTreeModel.ets | C | C | C | C | C | C | C | 纯数据 |
| models/Preferences.ets | C | C | C | **N** | C | C | C | 遗留 #3 读写失败只写日志，UI 无感 |
| models/SessionConfig.ets | C | C | C | C | C | C | C | 默认值/类型齐全 |
| models/SessionState.ets | C | C | C | C | C | C | C | 枚举 |
| models/TorrentDir.ets | C | C | C | C | C | C | C | 纯数据 |
| models/TorrentFile.ets | C | C | C | C | C | C | C | 纯数据 |
| models/TorrentInfo.ets | C | C | C | C | C | C | C | 纯数据 + fromNativeJson 校验 |
| models/TransmissionSession.ets | C | C | **N** | C | C | C | C | 实时下发覆盖沙箱目录（已修）；alt-speed 调度器；ratio 双精度 |
| pages/AboutPage.ets | C | C | C | C | C | C | C | — |
| pages/AddTorrentPage.ets | C | C | C | C | C | C | C | isAdding 重入锁、dstPath 清理、worker 内 catch |
| pages/DownloadsPage.ets | C | C | **N** | C | C | C | C | 文件复制 fd 泄漏（已修）；退出路径清理 |
| pages/FileTreePage.ets | C | C | **N** | C | C | C | C | 遗留：`loadFiles` 主线程解析，大种子卡 UI（E1） |
| pages/Index.ets | C | C | C | C | C | C | C | 容器页 |
| pages/ProxyPage.ets | C | C | **N** | C | C | C | C | 遗留 #8 host/port 校验缺失 |
| pages/SettingsPage.ets | C | C | C | C | C | C | C | — |
| security/HukProxyCipher.ets | C | C | C | **N** | C | C | C | 加密失败退回明文（已修，改为抛错） |
| security/ProxyCipher.ets | C | C | C | **N** | C | C | C | 旧 cipher 把 HUKS 信封当明文返回（已修） |
| services/ConnectivityMonitor.ets | C | C | **N** | C | **N** | C | C | 冷启动 WiFi-only 迟到判定；start 失败未销毁连接（已修） |
| services/KeepAliveManager.ets | C | C | C | C | C | C | C | 不镜像保活状态，回调驱动重取 |
| services/SessionController.ets | **N** | C | C | C | **N** | C | C | refresh 停止后越界；acquire 竞态身份判定（已修） |
| utils/constants.ets | C | C | C | C | C | C | C | 设计令牌 |
| utils/errors.ets | C | C | C | C | C | C | C | errText 统一错误文本 |
| utils/format.ets | C | C | C | C | C | C | C | 纯函数 |
| utils/i18n.ets | C | C | C | C | C | C | C | 状态串本地化，模型层保持英文 |

## C++ 单元（7）

| 单元 | I1 | I2 | I3 | I4 | I5 | I6 | I7 | 备注 |
|---|---|---|---|---|---|---|---|---|
| cpp/commons.cc | C | C | **N** | C | C | C | C | `tr_ctorNew(nullptr)` 必崩（已修）；wait 加 15s 超时 |
| cpp/commons.h | C | C | C | C | C | C | C | 仅签名/宏 |
| cpp/curl.cc | **N** | C | C | C | C | C | C | 路径校验分支漏 free(caBundle)（已修） |
| cpp/native_to_arkts.cc | C | C | C | C | C | C | C | TSFN 生命周期与 finalize 配对 |
| cpp/napi_init.cpp | C | C | C | C | C | C | C | 注册表与 Index.d.ts 28/28 对齐（机检） |
| cpp/torrent.cc | C | C | **N** | C | C | C | C | 片段索引 OOB、DnD 索引越界、无会话解析（已修） |
| cpp/transmission.cc | C | C | **N** | C | **N** | C | C | proxy-url 凭据落盘（已修）；configDir 空指针；关闭超时不硬 free |
| cpp/third_party/fmt（头文件） | C | C | **N** | C | C | C | C | 桥侧 fmt 9 与引擎库内 fmt 12.1.0 ABI 不一致 → 首次实例化带 fmt 成员的引擎类即堆损坏；已对齐（E3：模拟器 225/225） |

## N-API 导出（28）

| 子模块 | 导出数 | I3 接收侧校验 | 备注 |
|---|---|---|---|
| commons | 3 | C | `infoFromFile` 改为无会话解析，不再依赖 ctor |
| transmission | 7 | C | `sessionStop` 增加 waitSessionIdle 超时保护 |
| torrent | 15 | **N** | `torrentSetDnd` 索引上界、`torrentGetFileStat` 片段钳制（已修） |
| torrent（续） | — | C | `torrentFindByHash` 返回 -1 契约已由上层判负 |
| curl | 1 | C | 目的路径绝对/无 `..` 校验 |
| native_to_arkts | 2 | C | 4 条 TSFN 通道，回调参数按约定校验 |

## 未覆盖（下一轮）

| 单元 | 原因 |
|---|---|
| I2 全量字段→线程表 | 只对 session 句柄、TSFN 回调、taskpool worker 三处做了归属确认；未逐字段建表 |
| 生命周期单元 11 个 `aboutToAppear` | 仅在页面级抽查，未逐个与资源获取配对成表 |
| 45 个持久键 | `PrefKeys` 默认值/类型已查；迁移路径只验证了代理密码一条 |
| N-API 传参类型误用 | 静态审了参数表，未做运行时模糊测试（遗留 4.3 #2） |
