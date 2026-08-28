# AppGallery 上架执行手册（AGC Release Playbook）

> 目标：把 `transmissionbtm`（bundle `com.9bt.transmissionbtm`，v1.0.0）发布到华为 AppGallery。
> 当前进度：版本号已升、release 构建与 `.app` 产物已验证、商店图标与文案/隐私政策已备。**剩 AGC 侧流程，其中「生成 release 证书链 + 创建应用 + 上传」需要登录的步骤必须由你本人操作**。

## 一句话时间线

```
今天即可开：ICP备案(7-20天) + 软著(30-60天)   ← 两个最长杆，先启动
拿到 release 证书链后：签发 release .app → 上传 AGC → 提审
```

---

## A. 前置：账户与主体（需要你登录 AppGallery Connect）

**AppGallery Connect 控制台**：https://developer.huawei.com/consumer/cn/ （华为开发者联盟）

1. **注册 / 实名认证**（个人开发者约 1 天；企业开发者需对公验证）
   - **个人 vs 企业**：工具类 app 个人可上架；但部分类目/权限需企业主体。若你已有企业则更稳。
   - 实名认证通过后获得 **开发者账号**。
2. 确认主体名称（用于生成 release 证书的 subject，必须与账号主体一致）。

> 🔴 **此处需要我提醒你登录**：打开 DevEco 或浏览器登录华为开发者账号后告诉我，即可继续生成 release 证书链。

---

## B. 创建应用（AGC 侧，需登录）

1. AGC → 我的项目 → 创建项目（选 HarmonyOS NEXT / 华为应用市场）。
2. 创建应用：bundleName = **`com.9bt.transmissionbtm`**（必须与 AppScope/app.json5 一致）+ 应用名称、类目。
3. 记录 **应用 App ID**（后续签名配置用）。

---

## C. release 签名证书链（关键，需登录 AGC 拿 release 证书）

> **核心区别**：当前用的是 DevEco 自动生成的 **debug** 证书（`~/.ohos/config/default_transmissionbtm__*`，keyAlias=debugKey）。AGC 上架**拒绝 debug 签名**，必须用 **release** 证书链。

分四步：

**C1（本地，无需登录）**：生成密钥对 + CSR
- DevEco → File → Project Structure → Signing Configs → 新建 → **Generate Key and CSR**（或命令行 `keytool`）。
- 填写 **alias**（如 `transmissionbtm_release`）、**密钥口令**、**主题（CN=主体名称，与 AGC 账号主体一致）**，时长 ≥ 25 年。
- 产出：`<alias>.p12` + `<alias>.csr`（本地保存好，口令别丢）。

**C2（AGC，需登录）**：上传 CSR 换取 release 证书
- AGC → 证书管理 → 证书 → 新建证书 → 上传 C1 的 `.csr` → 得到 release `.cer`（每个账号最多 3 个；用掉 1 个即可）。

**C3（AGC，需登录）**：创建 release 描述文件 .p7b
- AGC → 证书管理 → **AppGallery Connect 描述文件** → 新建：选上一部的 `.cer` + 绑定 bundleName `com.9bt.transmissionbtm` + 设备类型 phone/tablet/2in1 + **发布(Release) 证书**（不要选 debug）+ 有效期。
- 下载 `.p7b`。

**C4（本地）**：把 release 链写入 build-profile.json5
- 切换 `signingConfigs[0].material` 指到 release 的 `.cer / .p7b / .p12`，`keyAlias` 改 release alias，口令换成 release 的。
- 重新构建：`./hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon` → 得到 **release 签名**的 `.app`。

---

## D. 构建上传物（本地，release 签名后）

```bash
# 项目级 .app（上传物）
./hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon
# → build/outputs/default/transmissionbtm-default-signed.app   ← 上传这个
```
> 注意：**必须上传 `.app`**，AGC 不收 `.hap`。每次提审 **versionCode 递增**（当前 3，下次 4、5…）。

---

## E. 合规材料（两类 long-pole，尽快启动）

### E1. ICP 备案（大陆上架强需，7–20 天，最先启动）
- 触发点：AGC 提交上架时会引导备案；**需要 release 证书的**：
  - **证书公钥** 与 **证书 MD5 指纹**（从 release `.cer` 提取，AGC 侧可见）。
  - bundleName、应用名称、运营主体。
- 个人开发者走「个人备案」，周期短一些；材料齐后提交。

### E2. 软著（软件著作权，30–60 天）
- 企业开发者**必填**；个人开发者视类目，很多「工具类」也要求。
- 材料：申请表、源代码（前后 30 页+）、说明文档、身份证明。
- 名称可用：**transmissionbtm（HarmonyOS BitTorrent 客户端软件）**。
- 属 long-pole，建议与 ICP 备案并行办理。

---

## F. 商店信息填写（已备好底稿）

| 项 | 位置 |
|----|------|
| 商店文案（名称/简介/描述/关键词/类目/分级） | `docs/store-copy.md` |
| 隐私政策 | **已上线** `https://sysit.github.io/transmissionbtm/privacy-policy.html`（直接用这个 URL 回填 AGC） |
| 1080×1920 截图 ×5 | `docs/store-screenshots/downloads-active.png` 等（已生成，**未入仓**，上架时上传 AGC） |
| 应用图标 1024×1024 | `docs/store-screenshots/app_icon_1024.png`（已生成，**未入仓**） |

**已填字段**：客服邮箱 `21801713@qq.com`、主体名称 `陈锡金`、开源仓库 `https://github.com/sysit/transmissionbtm`、隐私政策 URL（上线完成）。
**剩余待办**：ICP 备案（材料 `docs/icp-filing.md` 已备）、软著、上传 AGC 提审。

---

## G. 风险与注意事项

1. **P2P 下载器类目敏感**——审核重点看是否内置侵权资源。本 app 已确认：无内置种子/tracker/搜索、无账号、无广告、无数据上报。在描述里明确「中立工具、用户自担内容版权」，截图用公版（BBB CC-BY）内容。
2. **GPLv2 义务**：因链接 libtransmission（GPLv2），本应用整体需以 GPLv2 分发，需提供对应源代码（开源仓库 URL）。
3. **未上线 DevEco 无法用 release 试用**：debug 签名 HAP 仅用于本机调试与截图，**不要**把它当上传物。
4. **每次提审 versionCode 必须递增**，否则 AGC 拒绝上传。

---

## H. 需要你介入的动作清单

- [ ] 完成华为开发者注册 / 实名认证
- [ ] 登录 AGC 告知我（我继续 C2/C3 的 CSR→cer→p7b 指引与 D 构建）
- [ ] 确定主体名称（个人/企业）+ 客服邮箱 + 开源仓库 URL
- [ ] 启动 ICP 备案 与 软著 材料准备
