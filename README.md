# transmissionbtm

**HarmonyOS BitTorrent 客户端** —— 原生引擎基于上游 [Transmission](https://github.com/transmission/transmission) 的 [libtransmission](https://github.com/transmission/transmission) 4.1.0 stable(**GPLv2**),经 **N-API** 桥接;UI 与业务层用 **ArkTS + ArkUI** 从零实现。

当前版本:**v0.1.1**(HarmonyOS 6.1.1 / API 24,arm64-v8a)

---

## 功能 (Features)

| 类别 | 功能 |
|------|------|
| 种子管理 | Torrent 增删改查;通过 **磁力链接 / `.torrent` 文件 / URL** 添加;**移动存储位置**(relocate) |
| 传输控制 | 下载 / 暂停 / 恢复 / 删除;统计卡 **每 5s 实时刷新**(`TorrentVM` + `@ObjectLink`) |
| 网络策略 | HTTP/HTTPS **代理配置**(可选认证);**WiFi-only 传输门控**(SSID 白名单,`ConnectivityMonitor.isSsidAllowed`);连接状态监控 |
| 文件 | **目录选择器**用于添加种子与"发布文件夹";**Save-to-Files 导出**(树形保留);文件树多选 |
| 后台 | **前台服务 + WakeLock**(资源打开结束,后台持续下载);慢速原生操作(add/relocate)经 **taskpool 后台化**,UI 不阻塞 |
| 界面 | 7 个页面:Index / Downloads / Settings / Proxy / About / AddTorrent / FileTree;暗色工业风设计 token |

> 部分能力(如 Windows/HarmonyOS 下 libtransmission 依赖差异)仍在打磨,完整变更与推迟列表见 [`docs/STATUS.md`](docs/STATUS.md)。

---

## 架构 (Architecture)

```
┌───────────────────────────────────────────────┐
│  ArkTS / ArkUI 应用层    (33 个 .ets 文件)      │  ← 7 页面 + 11 组件 + 模型 + 服务
├───────────────────────────────────────────────┤
│  N-API Bridge (C++, 8 文件 / 35 方法)          │  ← ThreadSafeFunction 事件回调
├───────────────────────────────────────────────┤
│  libtransmission 4.1.0 + 依赖 (C)             │  ← 18 个 .a,OH arm64-v8a 交叉编译
└───────────────────────────────────────────────┘
```

| 层级 | 技术 |
|------|------|
| UI | ArkTS + ArkUI(`@State` / `@Prop` / `@Link` / `@Provide`,V2 状态管理) |
| 原生桥接 | N-API(OpenHarmony NDK,35 方法,singleton `NativeBridge`) |
| BT 引擎 | **libtransmission 4.1.0 stable**(tag `2724011`) |
| 密码学 | OpenSSL 3.0.15 |
| HTTP | libcurl 8.5.0 |
| 事件循环 | libevent 2.1.12 |
| 构建 | Hvigor v6.24.3 + CMake |
| 偏好设置 | `@ohos.data.preferences` |

---

## 安装 (Install)

### 前置条件

- **DevEco Studio**(含内置 hvigor v6.24.3 工具链)与 **HarmonyOS SDK**(API 24 / 6.1.1,含 NDK)
- **Node.js v18.20.1**(hvigor 依赖)
- 一台 **HarmonyOS 6.1.1+** 真机(Pura 80 已验证)或模拟器,已开启 **开发者调试 + USB 调试**

### 一步构建签名 HAP

```bash
# 构建并签名(debug / release 均可;默认 debug)
./hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 产物路径:
#   entry/build/default/outputs/default/entry-default-signed.hap
```

> **签名**:项目使用 DevEco 自动生成的调试证书(`~/.ohos/config/default_transmissionbtm_*.p12`)。真实 `build-profile.json5` 含密钥口令,**不进 git**(已 gitignore);仓库只提交脱敏的 `build-profile.json5.sample`。

### 安装到设备/模拟器

```bash
# 查看设备
hdc list targets

# 安装(覆盖旧版本用 -r)
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap

# 启动
hdc shell aa start -a EntryAbility -b com.9bt.transmissionbtm
```

> 或直接拖入 **DevEco Studio → Run / Project Structure** 安装。

---

## 开发 (Development)

### 仓库结构

```
entry/src/main/
├── ets/                 # ArkTS 应用层
│   ├── pages/           #   Index/Downloads/Settings/Proxy/About/AddTorrent/FileTree
│   ├── components/      #   add/ settings/ torrent/ ui
│   ├── models/          #   Torrent、TorrentFile、Preferences 等
│   ├── services/        #   ConnectivityMonitor、SessionController、WakeLockManager
│   ├── bridge/          #   NativeBridge.ets(singleton,唯一原生入口)
│   └── utils/           #   format、constants(设计 token)
├── cpp/                 # N-API 原生桥(C++,8 文件)
│   ├── napi_init.cpp    #   模块注册
│   ├── commons.*        #   CHECK_STATUS / throwEX / CATCH 宏、线程调度
│   ├── transmission.*  #   会话生命周期
│   ├── torrent.*        #   Torrent CRUD + 统计
│   ├── curl.*           #   libcurl 下载
│   ├── hash.*  sem.*  env.*  native_to_arkts.*
│   └── third_party/     #   18 个交叉编译 .a + 头文件
└── ohosTest/            #   设备端测试(ohosTest)
tests/                   # 宿主端单元测试(vitest)
docs/                    # 里程碑/架构/迁移文档
```

### 构建与调试

```bash
# 反复构建(增量)
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

- 顶层目录的 `hvigorw` 只是 wrapper,委托给 DevEco Studio 内置工具链。
- SDK 版本约束:`compatibleSdkVersion == targetSdkVersion`(均 6.1.1 / API 24)。hvigor 强制 compatible ≤ target,调高 compatible 会报错误 00303015。

### 测试

```bash
# 宿主单元测试(快,无需设备)—— vitest
npx vitest run          # 当前 93/93

# 设备端测试(ohosTest,单元 + 进程内 E2E)
#   注意:`hvigorw test` 会在 GenerateUnitTestResult 卡住,改用下面的方式
./hvigorw assembleHap --mode module -p module=entry@ohosTest --no-daemon
hdc shell aa test -b com.9bt.transmissionbtm -m entry@ohosTest ...
#   当前 231/231(Pura 80)
```

### 关键约定

- 原生调用一律走 `NativeBridge.getInstance()`,**禁止**从组件直接调 `native.*`。
- 跨线程回调 ArkTS 只允许 **ThreadSafeFunction**,Non-main 线程绝不能调 `napi_call_function`。
- N-API 每个调用都检查 `napi_status`(见 `commons.h` 的 `CHECK_STATUS` / `throwEX` / `CATCH`)。
- 组件内 `@State` 保持最小;派生值在 `build()` 内联,勿存多余状态,`build()` 禁止副作用。
- 数据文件/路径视为不可信,写入前校验;hilog 用户串用 `%{private}s`。

### 设计参考

- [`design/tokens.css`](design/tokens.css) — 暗色工业风设计 token
- [`design/demo.html`](design/demo.html) — 浏览器可打开的原型

### 更多文档

| 文档 | 内容 |
|------|------|
| [`docs/STATUS.md`](docs/STATUS.md) | 完整变更日志 + 推迟债务 |
| [`docs/07-development-plan.md`](docs/07-development-plan.md) | 里程碑计划与任务分解(ground truth) |
| [`docs/06-feature-map-and-gap-analysis.md`](docs/06-feature-map-and-gap-analysis.md) | 功能地图 + 差距分析 |
| [`docs/01-native-bridge-and-core-engine.md`](docs/01-native-bridge-and-core-engine.md) | N-API 方法规格、C++ 文件清单 |
