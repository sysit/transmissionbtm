# AppGallery 商店文案 + 合规材料

> 面向华为 AppGallery（中国大陆）上架文案与合规说明底稿。目标 bundle：`com.9bt.transmissionbtm`。当前版本 `1.0.0`（versionCode 3）。

## 1. 基本信息

| 项 | 值 |
|----|----|
| 应用名称（建议） | transmissionbtm |
| 类目 | 实用工具 → 下载 / 上传工具（P2P 下载） |
| 设备类型 | 手机、平板、车机（phone / tablet / 2in1） |
| 语言 | 简体中文、英文 |
| 版本 | 1.0.0 |
| 软著名称 | transmissionbtm（HarmonyOS BitTorrent 客户端软件） |
| 开源协议 | **GPLv2**（本应用链接上游 [Transmission](https://github.com/transmission/transmission) libtransmission 4.1.0 stable，GPLv2） |

> ⚠️ **上架说明**：P2P 下载器在商店审核中归类敏感。核心合规卖点 = **中立工具**：无内置种子、无内置 tracker、无搜索索引、不提供任何盗版资源；用户自选的种子内容版权由用户自行负责，app 仅作传输与端口对端连接。

## 2. 一句话简介（短描述，≤50 字）

```
基于 Transmission 引擎的开源 HarmonyOS BitTorrent 下载客户端。纯工具，不内置任何资源，支持磁力链、种子文件与 URL 添加。
```

备选（更中性）：
```
一款基于 Transmission 的轻量 BitTorrent 下载器，支持磁力链、种子文件、URL 添加与移动下载位置，纯本地 P2P 传输。
```

## 3. 详细描述（长描述）

```
【一款开源、中立的 BitTorrent 下载客户端】

transmissionbtm 基于上游 Transmission 的 libtransmission 4.1.0 stable（GPLv2）构建，通过 N-API 桥接，UI 与业务层采用 ArkTS + ArkUI 从零实现。

■ 核心功能
• 多种添加方式：磁力链接、.torrent 文件、URL 直接添加
• 完整传输控制：下载 / 暂停 / 恢复 / 删除 / 移动存储位置
• 实时统计：下载 / 上传速度、进度、剩余时间、分享率，每 5 秒刷新
• 文件树：按目录显示文件，多选指定下载，单文件启用优先
• 网络策略：HTTP/HTTPS 代理（可选认证）、WiFi-only 传输门控（SSID 白名单）、连接状态监控
• 后台下载：前台服务 + WakeLock，资源打开结束仍可持续传输
• 目录选择器：添加种子指定下载目录，导出 / 复制文件到本地存储
• 7 页面架构：下载 / 设置 / 代理 / 关于 / 添加 / 文件树 等

■ 中立性承诺
• 不内置任何种子、tracker 或搜索索引，不含任何盗版/侵权资源
• 仅作为 P2P 传输工具，用户自行选择与承担所添加资源的内容版权
• 完全本地运行，不上传任何用户数据

■ 开源
• 基于 GPLv2 开源引擎 Transmission libtransmission 4.1.0
• 不收集个人信息，详见隐私政策
```

## 4. 关键词（AppGallery 关键词，建议 ≤ 4 个）

```
BitTorrent  下载工具  磁力链  BT下载
```

## 5. 权限说明（用于「权限清单」披露）

| 权限 | 用途（facing user） |
|------|---------------------|
| 网络（INTERNET） | BitTorrent P2P 对等传输所需的网络访问 |
| 后台运行（KEEP_BACKGROUND_RUNNING） | 切换到后台后继续下载 |
| 网络状态信息（GET_NETWORK_INFO） | 检测 WiFi / 数据流量，防止移动数据自动下载 |
| WiFi 信息（GET_WIFI_INFO） | 读取当前 WiFi SSID，实现「仅允许白名单 WiFi」传输门控 |

> **无敏感权限**：不使用相机、麦克风、定位、通讯录、短信、剪贴板；无账号体系；无广告 SDK；无数据上报。

## 6. 内容分级 / 内容审核

- 年龄段适用：**3+**（无暴力、无成人、无不良内容；仅工具属性）
- 建议勾选「无不适内容」，所属应用类型：下载工具

## 7. 联系方式（甲方必填）

- 客服邮箱：**21801713@qq.com**
- 主体名称：**陈锡金**（个人开发者实名，release 证书 CN=陈锡金(1942298321628490625) 一致）

## 8. 来源与合规备注

- **隐私政策 URL（已上线）**：https://sysit.github.io/transmissionbtm/privacy-policy.html
- **开源仓库 URL（已确认）**：https://github.com/sysit/transmissionbtm —— GPLv2 下分发需提供源代码
- **软著**：企业上架建议尽早办理（约 60 天）；个人开发者视类目要求
- **ICP 备案**：中国大陆境内 app 上架需 ICP 备案（7–20 天），需 bundleName + 证书公钥 + 证书 MD5 指纹 —— 材料见 `docs/icp-filing.md`（叶子 MD5 `72:E6:92:4E:90:50:2F:EF:17:F0:44:F3:F2:51:D7:8B`）

## 9. 待办（其余上架步骤）

- [ ] 生成 release 证书链（.p12 + .csr → AGC → .cer → .p7b）——**需 AGC 登录**
- [ ] 签发 Release `.app` 并上传 AGC（当前为 debug 签名，AGC 拒绝）
- [ ] 填写并公网托管隐私政策 URL
- [ ] 回填客服邮箱、主体名称、开源仓库 URL
- [ ] 办理 ICP 备案（开始审核最长的阶段）
