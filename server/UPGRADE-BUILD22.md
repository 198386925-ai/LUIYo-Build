# 原有后台升级到 Build 22

原有卡密、备注、设备上限、到期时间、授权令牌、封禁记录，以及生成卡密和卡密管理功能全部保留。本次只新增设备登记、在线状态和 UDID 信息表。仓库提交和 IPA 打包不会自动覆盖线上服务器。

## 升级步骤

1. 备份原后台目录和数据库。SQLite 使用 WAL 时须使用在线备份，或暂停服务后同时备份数据库及 `-wal`、`-shm` 文件。
2. 覆盖原 `/luiyo/` 目录中的 `api.php`、`admin.php`，并加入 `bootstrap.php`、`device-service.php`、`profile.php`、`udid-verifier.php`、`admin-devices.js`、`apple-device-ca.pem`。
3. 不要覆盖或删除原数据库、管理密码文件及 PHP-FPM 配置。`LUIYO_DB_PATH`、`LUIYO_ADMIN_PASSWORD_HASH` 和私有 `admin.hash` 路径保持原值。
4. PHP 8.3 需要 `pdo_sqlite`、`mbstring`、`dom`、`openssl` 扩展，以及有效 HTTPS。
5. 在原 PHP-FPM 配置新增下列项，然后重载 PHP-FPM：

   ```ini
   env[LUIYO_PUBLIC_BASE_URL] = https://mistoto.cc.cd/luiyo
   ```

   使用其他域名时替换成实际地址，末尾不要加 `api.php`。
6. 用原管理员密码登录原 `admin.php`。设备列表每 15 秒更新，不会整页刷新或丢失刚生成的卡密。
7. 签名安装新版 IPA，打开后观察“设备与在线用户”。未授权也会登记。旧版 App 的授权记录在下方保留，不能补出此前未采集的 UDID。

此更新包不含数据库、管理密码、用户记录或私钥。IPA 未签名，签名文件读取须签名安装后才能验证。

## UDID 显示

| 来源 | 后台显示 | 是否需要用户点击 |
|---|---|---|
| 签名描述文件只含一个唯一设备号码 | 签名文件提供（未校验） | 否 |
| 描述文件有多个设备或没有设备列表 | 未获取 | 不要求，手动获取可选 |
| 用户完成设备识别描述文件流程且签名通过 | 描述文件已校验 | 获取时点一次 |

已授权设备不会因没有 UDID 被取消授权。本次不将旧授权改为强制 UDID 绑定。签名文件的设备列表是允许安装的名单，不能当作当前硬件证明；描述文件流程关联发起流程的安装记录，也不等同 App Attest 的 App/硬件证明。

## 设备与在线状态

新版 App 自动登记安装编号、机型、系统版本、App 版本及当前页面（首页、规则、设置），前台每 30 秒发送心跳。超过 90 秒未收到心跳即视为离线。这是心跳估计，不是即时连接人数。登记凭证与授权令牌分开，不能激活 App、解除封禁或使用首页功能。旧卡密验证方式不变。

## 可选描述文件

仅请求 UDID，不请求 IMEI、序列号、照片或通讯录；不安装 MDM、VPN 或根证书。链接有效 10 分钟，完成后不能重放；重新发起会使旧链接失效。

`apple-device-ca.pem` 是 Apple 官方 OTA 文档公布的设备 CA 公钥证书：
https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/iPhoneOTAConfiguration/profile-service/profile-service.html

服务校验 CMS 内容签名、固定设备 CA 签名及一次性 Challenge。按 Apple 对该协议的说明，设备身份证书日期不作为有效性判断。未知设备 CA 代次会拒绝并保持“未获取”，需要核实 Apple 可信证书后再更新。任意自签名或普通 XML 上传不能成为“已校验”。

不同 iOS 版本的描述文件安装及回调仍需真机确认；后台回归覆盖无授权登记、旧数据保留、管理员登录、伪造/篡改拒绝、过期和重放。

## 回退及数据

- 原 `activate` / `check` 接口格式保持兼容。先验证原卡密、旧令牌和封禁功能，再验证新版登记。
- 未配置 `LUIYO_PUBLIC_BASE_URL` 时，仅影响手动描述文件获取，原授权和登记仍可使用。
- 回退时恢复旧代码即可，旧表格式未改变，新增表可保留，旧 App 不需要重输卡密。
- 设备信息仅登录后的管理员可见。按实际需要制定保存期限；删除卡密不会自动抹去登记设备。
- 本更新未启用自动模拟器验证，由签名安装后的真机检查交互。
