# ICP 备案材料（华为 AppGallery 上架）

> 大陆 AppGallery 上架需 ICP 备案素材。以下从 **release 叶子证书**（绑定 `com.9bt.transmissionbtm` 的那张，非 Root）提取，2026-08-28。
> 材料在 `~/.ohos/config/transmissionbtm_release.cer`（内含 Root→DR CA→Release 叶子 3 张；**ICP 取叶子**）。

## 证书公钥（叶子，base64）

```
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEwozDAz7wS3GeJ74txS98zgJmGY4FOxl0RUULDlLXDUfBy/t0lO+FRscLfpQ9b3ZLu0/gBvd1Pa2yF06FDiQk1w==
```

## 证书 MD5 指纹（叶子）

```
72:E6:92:4E:90:50:2F:EF:17:F0:44:F3:F2:51:D7:8B
```

## 证书 SHA-256 指纹（叶子，备用）

```
（用 openssl x509 -in 叶子.pem -fingerprint -sha256 生成；叶子从 transmissionbtm_release.cer 的第 3 张提取）
```

## 其它备案字段

| 项 | 值 |
|----|----|
| bundleName | `com.9bt.transmissionbtm` |
| 应用名称 | transmissionbtm |
| 运营主体 | 陈锡金（个人开发者，真实名，release 证书 CN 一致） |
| 当前版本 | 1.0.0（versionCode 3） |
| 证书叶子 Subject | `CN=陈锡金(1942298321628490625),Release`, OU=1942298321628490625, O=陈锡金, C=CN |
| 证书有效期 | 2026-08-28 22:26:47 ~ 2029-08-28 22:26:47 |
| 签名算法 | SHA384withECDSA |

## 提取命令备忘

```bash
CER=~/.ohos/config/transmissionbtm_release.cer
# 该 .cer 是 3 张链（Root 在[0]，叶子在最后）。openssl x509 -in 整文件只读第一张(Root)，勿直接用于 ICP。
python3 - <<'PY'
import re, subprocess
d=open('/Users/xiphis/.ohos/config/transmissionbtm_release.cer').read()
blocks=re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', d, re.S)
leaf=blocks[-1]
open('/tmp/leaf.pem','w').write(leaf)
for c in ['-fingerprint -md5','-fingerprint -sha256']:
    print(subprocess.run(['openssl','x509','-in','/tmp/leaf.pem','-noout']+c.split(),capture_output=True,text=True).stdout.strip())
PY
```
