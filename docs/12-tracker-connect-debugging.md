# 12 — Tracker 连接失败排查 + 鸿蒙网络权限（组播）调研记录

> 记录时间：2026-08（排障进行中）。本文把针对「种子启动后 tracker 连接失败」的代码层怀疑写成文档，并补充一份关于 **BT 协议是否依赖组播、鸿蒙是否放开** 的联网调研结论，供后续排障使用。
>
> **后续更新：本症状的真正根因是 libtransmission 客户端版本。** M-Team PT 只认 4.1.x（`"mteam只支持4.1.x stable版本"`），而当时的引擎树是 4.2.0-dev（仅把 `version.h` 伪装成 4.1.0），tracker 因而拒绝/不胜任。已改为从**真实的 4.1.0 stable tag** 重建引擎（见 CLAUDE.md「Current Status」与 memory `transmission-410-engine-build`）；该修复后 tracker announce 返回 `res='Success'`。因此本文 3.1/3.2/3.3 的静态 libcurl CA、proxy-url、IPv6 假设**均非本卡点根因**，仅保留作为通用调参/联网排查参考；第 4 节「BT 不需要组播权限」的结论仍然成立。

---

## 1. 症状

- 种子启动后，tracker announce 报 **`Could not connect to tracker`**。
- 该种子为 **M-Team PT**，tracker 主机 `tracker.m-team.cc`，**443 (HTTPS)**。
- 属**连接层失败**（连不上），不是 DHT/PEX，也不是「0 peers」。
- **同一版本桌面 Transmission 能正常下载**，说明该机器到该 tracker 的网络链路是通的。
- 物理真机（`4VM0125513000074`）从 hdc 掉线，当前只剩模拟器 `Pura 90 API24`（`127.0.0.1:5555`）。

---

## 2. 种子启动后的网络处理路径（源码定位）

启动链：

```
ArkTS DownloadsPage.ets
  → TransmissionSession.start(config)            ets/models/TransmissionSession.ets:~
  → buildSettingsJson(config)                     ets/models/TransmissionSession.ets:92
  → bridge.sessionStart(..., settingsJson)         ets/bridge/NativeBridge.ets:60
  → native SessionStart                            cpp/transmission.cc:SessionStart
  → torrentStart → TorrentStartFunc → tr_torrentStart(tor)   cpp/torrent.cc:347
  → libtransmission announcer 向 tracker 发 announce
      （TCP/HTTPS 连接发生在预编译 libtransmission.a 内部）
```

会话参数来源 `buildSettingsJson()` 传递的关键键：
`peer-port`、`speed-limit-*`、`dht-enabled`、`pex-enabled`、`utp-enabled`、`lpd-enabled`、
`peer-limit-*`、`blocklist-*`、`ratio-limit-*`，以及 **`proxy-url`**（仅在 `proxyEnabled` 为真时写入，默认 `false`，带认证会内嵌 `user:pass@`）。

`transmission.cc::SessionStart`：基于 `tr_sessionGetDefaultSettings()` 合并持久化 `settingsJson`，应用到 live 会话；**但其自身不设置任何 proxy/CA/user-agent/超时**，且 `proxy-url` 应用后会**在保存前被剥离**；同时固定 `peer_port_random_on_start=true`、`port_forwarding_enabled=false`。

---

## 3. 我的怀疑（代码层）

### 3.1 主嫌疑：静态 libcurl 的 CA/TLS 是黑盒，app 从未配置 CA bundle

- `CMakeLists.txt:71-76` 静态链接：`curl/libcurl.a` + `openssl/libssl.a` + `libcrypto.a` + `libevent_openssl.a`。
- 代码里**到处 `CURLOPT_SSL_VERIFYPEER=1`**（如 `cpp/torrent.cc:784`），但**整个工程没有 `CURLOPT_CAINFO`、`CURLOPT_CAINFO_BLOB`、`CURLOPT_CAPATH`，也没有 `curl_global_init()`**。
- 也就是说，HTTPS 的 **CA 验证行为完全由那个预编译 `libcurl.a` 的编译期默认 CA 路径决定**。OHOS/OpenHarmony 一般没有标准 `/etc/ssl/certs/ca-certificates.crt`。若该静态 libcurl 的默认 CA 路径在 OHOS 上不存在，HTTPS 的证书校验会失败。
- 这解释了「桌面能连、app 连不上」：桌面 libcurl 用的是系统完整 CA；app 用的是个**不完整的/路径错误的静态 CA**。

> 注意区分报错：libcurl 证书校验失败通常报 `SSL certificate problem: unable to get local issuer certificate`；而「Could not connect to tracker」对应 `CURLE_COULDNT_CONNECT`（DNS 已解析、TCP/TLS 建立失败）。因此 CA 校验失败会体现为「证书错误」，而这里报的是连接失败——二者在 libtransmission 的 announcer 里可能被并行报告，需以 `[PROBE]` 的 `rc` 为准。

### 3.2 次嫌疑：`proxy-url` 被持久化为旧值

- `buildSettingsJson()` 只有在 `proxyEnabled` 为真才写 `proxy-url`（默认关）。
- 但 `transmission.cc` 会把合并进来的 proxy 应用到 **live 会话**（保存前才 strip）。如果设备上之前存过一个坏的/已失效的 proxy 配置，live 会话发出的 announce 会走该 proxy，导致连不上。
- 需确认持久化设置里 `proxy_enabled` 是否为 true（`ProxyPage.ets` / `Preferences.ets` 的 `PROXY_ENABLED`）。

### 3.3 需要核实：静态 libcurl 是否做了 IPv6-优先 / 双栈

- 若 OHOS 侧 DNS 优先返回 IPv6 而到 tracker 的 IPv6 不可达，桌面用 IPv4 能连，app 可能卡在不可达的 IPv6 上。`[PROBE]` 会打印 `ip=`（`CURLINFO_PRIMARY_IP`），可直接看出是否解析到 IPv6。

---

## 4. 组播权限调研结论（联网查询，修正「BT 需要组播权限」的印象）

先说结论：**BT 协议本身不需要组播权限**。tracker announce（TCP/HTTPS）、peer 连接（TCP）、DHT / UDP tracker / uTP（普通单播 UDP）**全是单播，不需要组播或广播**。

组播/广播在 BT 里**只服务于两件事**，且都是可选的：

| 用途 | 协议 | 组播地址:端口 | 备注 |
|------|------|--------------|------|
| **LPD**（Local Peer Discovery，本地资源发现） | UDP 组播 | `239.192.152.143:6771` | 走 `lpd-enabled` 开关 |
| **UPnP / NAT-PMP** 端口映射发现 | SSDP 组播 / 广播 | `239.255.255.250:1900` / `1901` | 走 `miniupnpc`/`libnatpmp` |

（本工程确实静态链接了 `natpmp/libnatpmp.a` 与 `miniupnpc/libminiupnpc.a`，`CMakeLists.txt:64-65`；`buildSettingsJson()` 也传了 `lpd-enabled`。）

### 鸿蒙/OpenHarmony 现状（联网结果）

- **鸿蒙对组播的支持**：`ohos.permission.INTERNET` + `GET_NETWORK_INFO` 覆盖常规单播 UDP/TCP。局域网组播/广播可以走，但社区有反馈在某些场景下 UDP 组播发送报 `Permission denied`，且**不同机型/「应用在后台」「连接 WiFi 还是蜂窝」对允许行为不一致**（[HarmonyOS 鸿蒙Next 对局域网UDP组播或者广播的限制](https://bbs.itying.com/topic/6941f8bb51a371004d535712)、[鸿蒙 Next 中 UDP 通信 Permission denied](https://bbs.itying.com/topic/6835e58a0b6770004fdf8ead)）。
- **组播 API 是否放开**：OpenHarmony 文档有 `+let multicast: socket` / `so_multicast` 相关的 socket 能力说明与 PR（[OpenHarmony docs multicast socket PR](https://gitee.com/openharmony/docs/pulls/33938.diff)、[Unsubscribes message events of UDP socket](https://gitee.com/openharmony/docs/pulls/43742.diff)），说明组播对应到 OHOS socket 层是**逐步开放/补齐**的。
- **「BT 在鸿蒙已被验证可行」——不能当结论**。唯一的所谓证据是 [libtorrent issue #7917](https://github.com/arvidn/libtorrent/issues/7917)，但它只是一个状态为 `closed/completed` 的**提案**，且经过核实：
  - 仅 **1 条评论**（来自 `ghost`，2025-03-28）：『**Ai吧？issue都不愿意手写了……**』——被当成 AI 凑数、整体质疑；
  - **无任何上游合并、无验证、无可复核的测试报告**；
  - 且 **libtorrent 是另一个库**，本 app 用的是 **libtransmission**。用 libtorrent 的提案证明「本 app 在鸿蒙跑 BT 没问题」，逻辑上不成立。
  - 因此「鸿蒙是否对 BT 网络有底层限制」——**目前无证据，属未知**。

### 对本案的意义（修正版）

- **能确证的**：tracker(m-team.cc:443) 连接走 **TCP/HTTPS 单播**，**与组播权限无关**；所以「BT 需要组播、鸿蒙没放开组播」**不是**当前卡点的根因。
- **不能确证的**：是否还存在某种鸿蒙特有的网络/TLS 限制导致该 app 的 BT 网络栈不如桌面正常。**这一条不靠任何第三方提案，必须用 5 节的 `[PROBE]` 实测**来裁决（`control` 通/不通分别对应「app 全局问题」vs「tracker 特有/或鸿蒙侧问题」）。
- 因此主方向仍应回到 **3.1 的静态 libcurl CA/TLS**、**3.2 的 proxy-url**、**3.3 的 IPv6/双栈**，并用 `[PROBE]` 判别；**不要在证据不足时把「鸿蒙不支持」或「鸿蒙没问题」二者之一当成结论**。

---

## 5. 判别手段：app 自带的 `[PROBE]`

代码里已实现一次性探测（`cpp/torrent.cc::HttpProbeOnce` / `HttpProbeFetch`，首个 `torrentStatBrief` 轮询时触发），用**app 自己的 libcurl** 打两个地址（`SSL_VERIFYPEER=1`、UA `transmissionbtm-probe`、CONNECTTIMEOUT 5s / TIMEOUT 8s），并打印 `rc / ip / connect=…s / err='…'`：

```
[PROBE] control  https://example.com/         ← 区分「全 app 网络/CA/沙箱坏了」
[PROBE] tracker  https://tracker.m-team.cc/   ← 裸 host（无 passkey）
```

判读：
- `control` 也失败 ⇒ 是**app 全局网络/CA/沙箱问题**（INTERNET 权限、CA bundle、模拟器网络），**不是 tracker 特有**。
- `control` 通、仅 `tracker` 失败 ⇒ 是**到 m-team 的 TLS/路由/静态 libcurl**问题。
- 看 `ip=` 是否为 IPv6、`err=` 是否为证书/连接错误，进一步收窄 3.1 / 3.3。

---

## 6. 下一步

1. 在**模拟器**上跑一次：构建 HAP → 安装 → 启动 → 抓 hilog 里的 `[PROBE]` 两行（`control` 与 `tracker` 的 `rc/ip/err`）。
2. 依据判读：
   - 若 control 也失败：核对 `module.json5` 网络权限、静态 libcurl 的编译期 CA 路径、以及模拟器当前网络/代理。
   - 若仅 tracker 失败：确认 `proxy-url` 未持久化；检查静态 libcurl 是否 IPv6-优先；必要时给 app 显式 `CURLOPT_CAINFO`（指向系统 CA）或在 buildSettings 里修正。
3. 若排查 LPD/UPnP 相关现象（非本次卡点）时，再针对鸿蒙组播权限做专项。
