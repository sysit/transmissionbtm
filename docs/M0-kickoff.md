# M0 — 开工清单：工程脚手架 & 原生编译

**目标：** HarmonyOS 工程可编译。4 个原生库在 OH 工具链下成功构建。N-API 模块骨架能加载。

**预估工时：** 3-5 天

---

## 前置条件检查

- [ ] 安装 DevEco Studio (5.0+)
- [ ] 安装 HarmonyOS SDK (API 12+)
- [ ] 安装 OH NDK (musl toolchain, arm64-v8a)
- [ ] 克隆 transmissionbtc 源码: `~/projects/transmissionbtc`
- [ ] 确认 C++ 构建工具链可用: `cmake`, `make`, `git`

---

## 0. 创建工程骨架

- [ ] 0.1 创建 DevEco Studio 工程 (Empty Ability)
- [ ] 0.2 配置 `build-profile.json5` (target SDK, abiFilters: arm64-v8a)
- [ ] 0.3 配置 `oh-package.json5` (依赖声明)
- [ ] 0.4 配置 `entry/src/main/module.json5` (abilities, permissions)
- [ ] 0.5 空应用部署到模拟器/真机验证

**验证：** DevEco Studio 中 Run → 模拟器上看到 "Hello World"

---

## 1. 原生库编译

### 1.1 OpenSSL
- [ ] 1.1 确认 OH 系统是否已有 OpenSSL (`/system/lib64/libssl.so`)
- [ ] 1.2 若无，交叉编译 OpenSSL → `libssl.a` + `libcrypto.a`
- [ ] 1.3 验证: `aarch64-linux-musl-nm libssl.a | grep SSL_new`

### 1.2 libcurl
- [ ] 1.4 确认 OH 系统是否已有 libcurl
- [ ] 1.5 若无，交叉编译 libcurl → `libcurl.a`
- [ ] 1.6 备选方案评估: 用 `@ohos.net.http` 替代 curl (仅用于 torrent 文件下载)

### 1.3 libevent
- [ ] 1.7 交叉编译 libevent 2.1.12 → `libevent.a`
- [ ] 1.8 验证: 确认 event_base_new() 使用 epoll 后端

### 1.4 libtransmission
- [ ] 1.9 克隆 transmission fork 源码
- [ ] 1.10 Patch: `__android_log_write` → `OH_LOG_Print` (日志适配)
- [ ] 1.11 ~~Patch: `tr_android_*` → `tr_oh_*`~~ **跳过** — v1.0 用沙箱 POSIX I/O，无需文件 I/O 钩子
- [ ] 1.12 交叉编译 libtransmission + 子库 → `libtransmission.a`
- [ ] 1.13 验证: 所有符号可链接

---

## 2. N-API 模块骨架

### 2.1 模块注册
```cpp
// entry/src/main/cpp/napi_init.cpp
#include <napi/native_api.h>

static napi_value GetVersion(napi_env env, napi_callback_info info) {
    napi_value result;
    napi_create_string_utf8(env, "0.1.0", NAPI_AUTO_LENGTH, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "getVersion", nullptr, GetVersion, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "transmissionbtm_napi",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&demoModule);
}
```

- [ ] 2.1 创建 `entry/src/main/cpp/napi_init.cpp`
- [ ] 2.2 配置 `entry/src/main/cpp/CMakeLists.txt`
- [ ] 2.3 ArkTS 侧调用: `import native from 'libtransmissionbtm_napi.so'` → `native.getVersion()`
- [ ] 2.4 验证: 模拟器上看到 "0.1.0"

### 2.2 日志适配
- [ ] 2.5 修改 `stdredirect.cc`: `__android_log_write` → `OH_LOG_Print`
- [ ] 2.6 验证: libtransmission 日志出现在 hilog 中

### 2.3 环境变量适配
- [ ] 2.7 检查 `env.cc` — `setenv`/`unsetenv` 在 OH musl 下是否直接可用
- [ ] 2.8 验证: HTTP_PROXY 等环境变量正确传递

---

## 3. CMake 构建配置骨架

```cmake
cmake_minimum_required(VERSION 3.16)
project(transmissionbtm_napi)

find_library(napi-lib napi ${OHOS_NDK_HOME})

set(OPENSSL_DIR ${CMAKE_SOURCE_DIR}/third_party/openssl)
set(CURL_DIR    ${CMAKE_SOURCE_DIR}/third_party/curl)
set(EVENT_DIR   ${CMAKE_SOURCE_DIR}/third_party/libevent)
set(TR_DIR      ${CMAKE_SOURCE_DIR}/third_party/transmission)

add_library(transmissionbtm_napi SHARED
    napi_init.cpp
    # M1 添加: commons.cc, transmission.cc, torrent.cc, ...
)

target_link_libraries(transmissionbtm_napi
    ${napi-lib}
    ${OPENSSL_DIR}/libssl.a ${OPENSSL_DIR}/libcrypto.a
    ${CURL_DIR}/libcurl.a
    ${EVENT_DIR}/libevent.a
    ${TR_DIR}/libtransmission.a
    hilog_ndk.z
)
```

- [ ] 3.1 创建 CMakeLists.txt
- [ ] 3.2 配置 `build-profile.json5` 中 native 构建参数
- [ ] 3.3 完整构建: `hvigor assembleHap` → 生成 .hap
- [ ] 3.4 验证: .hap 中包含 `libtransmissionbtm_napi.so`

---

## 4. 第三方库目录结构

```
entry/src/main/cpp/
├── CMakeLists.txt
├── napi_init.cpp
├── third_party/
│   ├── openssl/
│   │   ├── libssl.a
│   │   └── libcrypto.a
│   ├── curl/
│   │   └── libcurl.a
│   ├── libevent/
│   │   └── libevent.a
│   └── transmission/
│       └── libtransmission.a
├── commons.cc          # (M1)
├── commons.h
├── transmission.cc     # (M1)
├── torrent.cc          # (M1)
├── curl.cc             # (M1)
├── hash.cc             # (M1)
├── sem.cc              # (M1)
├── env.cc
├── stdredirect.cc
└── native_to_arkts.cc  # (M1)
```

---

## M0 完成标准

- [ ] DevEco Studio 工程可编译
- [ ] 空 ArkUI 页面部署到模拟器/真机
- [ ] 4 个第三方库全部交叉编译成功
- [ ] `libtransmissionbtm_napi.so` 包含在 .hap 中
- [ ] `getVersion()` 可从 ArkTS 调用并返回字符串
- [ ] libtransmission 日志出现在 hilog
- [ ] CMake 构建无警告无错误

---

## 风险与备选

| 风险 | 影响 | 备选方案 |
|------|------|---------|
| OpenSSL 编译失败 | 阻塞所有 | 使用 OH 系统 OpenSSL |
| libcurl 编译失败 | 阻塞 HTTP 下载 | `@ohos.net.http` 替代 |
| libevent 编译失败 | 阻塞事件循环 | OH 原生 epoll, 改 libtransmission 事件后端 |
| transmission fork 不兼容 musl | 阻塞核心 | 回退到上游 transmission 4.0.x + 手动 patch |
| DevEco Studio 版本不兼容 | 阻塞开发 | 检查 API/SDK 版本矩阵 |
