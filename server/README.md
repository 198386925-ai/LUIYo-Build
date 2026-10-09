# LUIYo Build24 后台更新

此版删除 UDID 授权模式，仅保留卡密授权。新安装用户输入卡密即可激活，不需要获取 UDID、安装描述文件或先登记设备。授权成功只显示“已授权”。

App 和后台必须一起更新。覆盖 api.php、bootstrap.php、device-service.php、admin.php、admin-devices.js、admin-ui.js、profile.php。保留原有数据库路径、管理员密码、HTTPS 和反向代理配置；不要删除数据库或重新建库。旧卡密、授权令牌、封禁状态、到期时间和设备数量上限继续生效。

后台保留已确认的紧凑布局，删除 UDID 手动授权区、列和筛选。在线状态、未授权登记、卡密生成管理、设备封禁、移出列表以及重新打开 App 后恢复显示均保留。

profile.php 为停用入口（HTTP 410），不会生成描述文件或接受回调。如果另外部署过 https://aistoto.cc.cd/udid/profile.php，请用包内 disable-udid/profile.php 覆盖这个独立入口，停止旧链接。历史数据保留，不再参与授权和列表分组。旧 manual-auth.php 不再被引用。

先备份后台文件和数据库，再覆盖后台代码，最后签名安装 Build24 IPA。IPA 是未签名编译产物，需要自行签名安装。PHP 8.3 或以上，需 PDO SQLite、mbstring；无需 UDID 的 XML/CMS 证书配置。

验证：有效卡密直接激活；已授权用户没有 UDID 入口；后台在线列表正常更新；封禁后下一次授权校验拒绝访问。
