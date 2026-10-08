# LUIYo 用户管理后台部署

当前阶段：**后台源码已提交；尚未部署，APP 尚未连接此 API**。不要把这当作已上线的封禁系统。

## 环境

PHP 8.3 + `pdo_sqlite` + HTTPS。部署 `server/api.php`、`server/admin.php` 到网站专用目录，例如 `https://你的域名/luiyo/`。两份 PHP 文件放在可访问目录，**数据库放网站根目录之外**。禁止把任何密码或数据库文件提交至 GitHub。

在 PHP-FPM 池或服务器环境中设置：

- `LUIYO_DB_PATH=/var/lib/luiyo/users.sqlite`（父目录预先创建、PHP 用户可写，不能被公网访问）。
- `LUIYO_ADMIN_PASSWORD_HASH=<使用 PHP password_hash 生成的 ARGON2ID 或 BCRYPT 哈希>`，示例命令：`php -r 'echo password_hash(readline("Password: "), PASSWORD_ARGON2ID), PHP_EOL;'`。
- 只有在受信任的 HTTPS 反向代理下，才可使用 `LUIYO_TRUST_PROXY_HTTPS=1`；代理必须清除并重设传入的 `X-Forwarded-Proto`，否则不要使用此设置。

先通过 HTTPS 请求 `api.php` 初始化表，再访问 `admin.php` 登录。首次请求 `api.php` 返回 404 JSON 是正常的，表仍会初始化。

## 管理操作

管理员生成 `LUI-XXXXX-XXXXX-XXXXX-XXXXX` 激活码，设置备注、最大设备数和有效天数。激活码**只在生成时展示一次**。后台只存储哈希，不可找回明文。可单独封禁或解封设备，也可停用整枚激活码（影响所有使用该码的设备）。设备列表显示最近 200 台；统计为全库。

## APP 通信协议（待接入）

### 1. 激活

`POST https://你的域名/luiyo/api.php?action=activate`

请求 JSON:

```json
{"code":"LUI-AAAAA-BBBBB-CCCCC-DDDDD","device_id":"随机 UUID"}
```

返回 HTTP 200：

```json
{"token":"64位十六进制的随机会话令牌","status":"active"}
```

真实激活码应由管理后台生成；上面的只是格式示例。服务器按激活码限制绑定设备数量，一个设备只能绑定一个激活码。保存 token 于 iOS Keychain；不得在 HTML、localStorage、日志或共享偏好中保存 token。

### 2. 心跳与权限验证

`POST https://你的域名/luiyo/api.php?action=check`

HTTP Header: `Authorization: Bearer <token>`

HTTP 200: `{"status":"active"}`；401 表示 token 无效；403 表示封禁/到期/已停用。APP 必须**在进入主要功能前验证**，使用期间按一定周期（例如 5 分钟）重新验证；收到拒绝后立即封锁主要功能并提示用户。考虑离线时如何处理：要求严格封禁时应使用 fail-closed，服务器不可达则暂时不能使用，但也会影响网络不稳定的合法用户。

## 安全、隐私与上线前核对

- 使用 HTTPS、私有数据库路径、单独的后台口令、系统备份；管理页不要挂在现有公开后台无保护的位置。
- 公开仓库**不能**存放管理员密码、数据库文件、真实激活码或 token。
- 统计依据为**激活设备数**而非 App Store 精确安装人数；今日、近七日活跃按 UTC 日期去重。一个人可以有多台设备。
- `device_id` 是客户端持有的随机标识，不是硬件 ID，可能被清除、复制或篡改；**无法保证禁止绕过封禁**。要实现“封禁一个人”，应配合登录账号、二次验证、购买记录或其他合法的账号归属手段。
- 激活接口包含按 IP 限制错误尝试；生产环境仍建议用服务器级限流/WAF，避免攻击与滥用。
- 默认不采集 IP 明文、硬件序列号、联系人、手机号、精确位置；激活接口仅临时保存 IP SHA-256 用于限制试错，需告知用户。
- 上线前需做 PHP lint、端到端测试、数据库目录权限检查与 APP 真机测试；当前尚未完成。
