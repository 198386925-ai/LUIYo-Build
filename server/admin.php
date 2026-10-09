<?php
declare(strict_types=1);
session_name('LUIYO_ADMIN');
session_set_cookie_params(['httponly'=>true,'secure'=>true,'samesite'=>'Strict']);
session_start();
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');
header('Content-Security-Policy: default-src \'none\'; style-src \'unsafe-inline\'; script-src \'self\'; connect-src \'self\'; form-action \'self\'; base-uri \'none\'; frame-ancestors \'none\'');
if (!extension_loaded('pdo_sqlite')) {http_response_code(503);exit('PDO SQLite required');}
if (empty($_SERVER['HTTPS']) || $_SERVER['HTTPS']==='off') {
 if (getenv('LUIYO_TRUST_PROXY_HTTPS')!=='1'||($_SERVER['HTTP_X_FORWARDED_PROTO']??'')!=='https') {http_response_code(403);exit('HTTPS required');}
}
$dbPath=getenv('LUIYO_DB_PATH');
$passwordHash=getenv('LUIYO_ADMIN_PASSWORD_HASH');
// Prefer the server's private password-hash file when PHP-FPM has no password env.
if (!$passwordHash && is_readable('/www/luiyo-private/admin.hash')) {
 $passwordHash=trim((string)file_get_contents('/www/luiyo-private/admin.hash'));
}
if (!$dbPath || !is_file($dbPath)) {http_response_code(503);exit('Database configuration unavailable');}
if (!$passwordHash) {http_response_code(503);exit('Administrator password configuration unavailable');}
$db=new PDO('sqlite:'.$dbPath,null,null,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$db->exec('PRAGMA busy_timeout=5000');
require_once __DIR__.'/device-service.php';
luiyo_device_schema($db);
require_once __DIR__.'/device-grants.php';
luiyo_grant_schema($db);
function e(string $s): string{return htmlspecialchars($s,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');}
function redirectHome(): never {header('Location: admin.php');exit;}
if (isset($_GET['logout'])) {$_SESSION=[];session_destroy();redirectHome();}
$error='';
if ($_SERVER['REQUEST_METHOD']==='POST' && ($_POST['action']??'')==='login') {
 if (password_verify((string)($_POST['password']??''),$passwordHash)) {
  session_regenerate_id(true);$_SESSION['authorized']=true;$_SESSION['csrf']=bin2hex(random_bytes(32));redirectHome();
 }
 sleep(1);$error='管理员密码不正确';
}
if (empty($_SESSION['authorized'])) { ?>
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover"><title>LUIYo 后台登录</title><style>body{touch-action:manipulation;font:16px system-ui;background:#f5f5f7;margin:10vh auto;max-width:360px;padding:20px}form{background:white;border-radius:20px;padding:25px}input,button{font:inherit;width:100%;box-sizing:border-box;padding:12px;margin:10px 0;border-radius:10px;border:1px solid #ddd}button{background:#16181c;color:white}</style><form method="post"><h2>LUIYo 管理后台</h2><p><?= e($error) ?></p><input type="hidden" name="action" value="login"><input type="password" name="password" placeholder="管理员密码" required autocomplete="current-password"><button>登录</button></form></html><?php exit; }
if(($_GET['snapshot']??'')==='1')luiyo_json(200,luiyo_admin_snapshot($db));
$issued=[];$notice='';
$requestedPanel=(string)($_POST['return_panel']??$_GET['panel']??'overview');
if(!in_array($requestedPanel,['overview','codes','devices','licenses'],true))$requestedPanel='overview';
if ($_SERVER['REQUEST_METHOD']==='POST') {
 if (!hash_equals($_SESSION['csrf']??'',(string)($_POST['csrf']??''))) {http_response_code(403);exit('CSRF check failed');}
 $action=(string)($_POST['action']??'');
 if($action==='create')$requestedPanel='codes';
 elseif(in_array($action,['ban','unban','hide_installations','grant_device','revoke_device'],true))$requestedPanel='devices';
 elseif(in_array($action,['delete_license','disable','enable'],true))$requestedPanel='licenses';
 $id=filter_var($_POST['id']??null,FILTER_VALIDATE_INT);
 if ($action==='hide_installations') {
  // Only signed-in administrators with a valid CSRF token can hide entries.
  // The client sends every installation code currently in this displayed group.
  $raw=(string)($_POST['installation_codes']??'');
  $codes=array_unique(array_filter(array_map('trim',explode(',',$raw))));
  if(!$codes || count($codes)>25) $error='设备编号无效';
  else {
   $ids=[];
   foreach($codes as $code) {
    if(!preg_match('/^D-([0-9]{6,9})$/D',$code,$m)) { $ids=[];break; }
    $ids[]=(int)$m[1];
   }
   if(!$ids)$error='设备编号格式错误';
   else {
    try {
     $db->exec('BEGIN IMMEDIATE');
     $insert=$db->prepare('INSERT INTO installations_hidden (installation_id,hidden_at)
       SELECT id,? FROM installations WHERE id=?
       ON CONFLICT(installation_id) DO UPDATE SET hidden_at=excluded.hidden_at');
     $hiddenAt=time();
     foreach($ids as $installationId) $insert->execute([$hiddenAt,$installationId]);
     $db->exec('COMMIT');
     $notice='设备已移出列表；再次启动 APP 并成功上报后将自动显示。原有授权均已保留。';
    }catch(Throwable $e) {
     if($db->inTransaction())$db->rollBack();
     $error='移出失败，请查看服务器日志';
    }
   }
  }
 } elseif(in_array($action,['grant_device','revoke_device'],true)) {
  try {
   $code=(string)($_POST['device_code']??'');
   $problem=$action==='grant_device'?luiyo_grant_device($db,$code):luiyo_revoke_grant($db,$code);
   if($problem)$error=$problem;else $notice=$action==='grant_device'?'设备码授权成功；新版 App 联网后自动领取':'设备码授权已撤销';
  }catch(Throwable $e){$error='操作失败，请查看服务器日志';}
 } elseif ($action==='create') {
  $label=mb_substr(trim((string)($_POST['label']??'')),0,80);
  $max=max(1,min(100,(int)($_POST['max_devices']??1)));
  $days=max(0,min(3650,(int)($_POST['days']??0)));
  $quantity=max(1,min(100,(int)($_POST['quantity']??1)));
  $alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  $insert=$db->prepare('INSERT INTO licenses(code_hash,label,max_devices,expires_at,created_at) VALUES(?,?,?,?,?)');
  $db->beginTransaction();
  try {
   for($n=0;$n<$quantity;$n++){
    $parts=[];
    for($k=0;$k<4;$k++){
     $part='';
     for($i=0;$i<5;$i++)$part.=$alphabet[random_int(0,strlen($alphabet)-1)];
     $parts[]=$part;
    }
    $code='LUI-'.implode('-',$parts);
    $entryLabel=$label===''?'':($quantity===1?$label:mb_substr($label,0,65).' '.($n+1));
    $insert->execute([hash('sha256',$code),$entryLabel,$max,$days?time()+86400*$days:null,time()]);
    $issued[]=$code;
   }
   $db->commit();
   // Keep newly issued plaintext only in the authenticated administrator session.
   // Existing database code hashes cannot be reversed.
   $batch=['at'=>time(),'label'=>$label,'days'=>$days,'max_devices'=>$max,'codes'=>$issued];
   if (!isset($_SESSION['luiyo_recent_batches']) || !is_array($_SESSION['luiyo_recent_batches'])) $_SESSION['luiyo_recent_batches']=[];
   array_unshift($_SESSION['luiyo_recent_batches'],$batch);
   $_SESSION['luiyo_recent_batches']=array_slice($_SESSION['luiyo_recent_batches'],0,12);
   $notice='成功生成 '.$quantity.' 个激活码，请在生成卡密页复制保存。';
  } catch(Throwable $ex) {
   if($db->inTransaction())$db->rollBack();
   $issued=[];$error='生成失败，请重试';
  }
 } elseif ($id && in_array($action,['ban','unban'],true)) {
  $db->prepare('UPDATE devices SET banned=?,ban_reason=? WHERE id=?')
    ->execute([$action==='ban'?1:0,$action==='ban'?mb_substr(trim((string)($_POST['reason']??'管理员封禁')),0,120):'',$id]);
  $notice=$action==='ban'?'已封禁设备':'已解除设备封禁';
 } elseif ($id && $action==='delete_license') {
  $db->beginTransaction();
  try {
   $deviceIds=$db->prepare('SELECT id FROM devices WHERE license_id=?');
   $deviceIds->execute([$id]);$ids=$deviceIds->fetchAll(PDO::FETCH_COLUMN);
   if($ids){$markers=implode(',',array_fill(0,count($ids),'?'));$db->prepare("DELETE FROM events WHERE device_id IN ($markers)")->execute($ids);}
   $db->prepare('DELETE FROM devices WHERE license_id=?')->execute([$id]);
   $db->prepare('DELETE FROM licenses WHERE id=?')->execute([$id]);
   $db->commit();$notice='已删除激活码及关联设备授权';
  } catch(Throwable $ex) {
   if($db->inTransaction())$db->rollBack();
   $error='删除失败，请重试';
  }
 } elseif ($id && in_array($action,['disable','enable'],true)) {
  $db->prepare('UPDATE licenses SET disabled=? WHERE id=?')->execute([$action==='disable'?1:0,$id]);
  $notice=$action==='disable'?'已停用激活码（所有绑定设备将无法使用）':'已启用激活码';
 }
}
$stats=[
 '累计激活设备'=>(int)$db->query('SELECT COUNT(*) FROM devices')->fetchColumn(),
 '今日活跃设备'=>(int)$db->query("SELECT COUNT(*) FROM events WHERE day='".gmdate('Y-m-d')."'")->fetchColumn(),
 '近7日活跃设备'=>(int)$db->query("SELECT COUNT(DISTINCT device_id) FROM events WHERE day>='".gmdate('Y-m-d',time()-6*86400)."'")->fetchColumn(),
 '已封禁设备'=>(int)$db->query('SELECT COUNT(*) FROM devices WHERE banned=1')->fetchColumn(),
 '激活码总数'=>(int)$db->query('SELECT COUNT(*) FROM licenses')->fetchColumn()
];
$devices=$db->query('SELECT d.id,d.created_at,d.last_seen,d.banned,d.ban_reason,i.id AS installation_id,l.label,l.id AS license_id FROM devices d JOIN licenses l ON l.id=d.license_id LEFT JOIN installations i ON i.device_hash=d.device_hash ORDER BY d.last_seen DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
$licenses=$db->query('SELECT l.id,l.code_hash,l.label,l.max_devices,l.expires_at,l.disabled,COUNT(d.id) AS device_count FROM licenses l LEFT JOIN devices d ON d.license_id=l.id GROUP BY l.id ORDER BY l.id DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
$recentPlainByHash=[];foreach(($_SESSION['luiyo_recent_batches']??[]) as $recentBatch){foreach(($recentBatch['codes']??[]) as $recentCode){$recentPlainByHash[hash('sha256',$recentCode)]=$recentCode;}}

?><!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover"><title>LUIYo 用户管理</title>
<style>
:root{color-scheme:light;--blue:#2674ef;--label:#131720;--secondary:#78859b;--line:#e6ebf2;--group:#f3f6fb}*{box-sizing:border-box}html{min-height:100%;-webkit-text-size-adjust:100%;touch-action:manipulation}body{font:13px/1.45 -apple-system,BlinkMacSystemFont,'SF Pro Text','PingFang SC',system-ui,sans-serif;color:var(--label);background:#f5f7fb;margin:0 auto;padding:15px 13px calc(90px + env(safe-area-inset-bottom));max-width:850px}header,section{background:#fff;border:1px solid #ebeff5;border-radius:16px;padding:14px;margin-bottom:11px;box-shadow:0 2px 13px rgba(26,44,80,.025)}header{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;border:0;background:transparent;box-shadow:none;margin-bottom:4px;padding:9px 5px 14px}header h1{font-size:21px;letter-spacing:-.45px;font-weight:750;margin:0 0 6px}header small{display:block;font-size:10.5px;line-height:1.55;color:#8a96a9;max-width:570px}header>a{white-space:nowrap;text-decoration:none;background:#edf4ff;color:var(--blue);border-radius:12px;padding:6px 11px;font-size:12px;font-weight:600}h2{font-size:15px;font-weight:720;margin:1px 0 13px;letter-spacing:-.15px}.between{display:flex;align-items:center;justify-content:space-between;gap:8px}.between h2{margin-bottom:9px}.between small{font-size:10px;color:#929daf}.stats{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.stat{background:var(--group);border-radius:13px;border:1px solid #f2f4f9;padding:12px 13px;min-height:74px;display:flex;flex-direction:column;justify-content:center}.stat small{display:block;font-size:10.5px;color:#677996;margin-bottom:3px}.stat b{font-size:23px;letter-spacing:-.4px;line-height:1.13;color:#1d2634;font-weight:740}a{color:var(--blue)}small{color:#78859b;line-height:1.5}input,select,button,textarea{font:inherit;max-width:100%}input,select,textarea{background:#f6f8fb;border:1px solid #e6ebf2;border-radius:10px;padding:9px 10px;color:#273142;min-height:35px}input:focus,select:focus,textarea:focus{outline:2px solid #bcd7ff;outline-offset:0}button{border:0;border-radius:10px;background:#2878f4;color:white;padding:9px 12px;min-height:34px;font-size:12px;font-weight:600;cursor:pointer;touch-action:manipulation}button.danger,.danger{background:#e95562;color:#fff}form.inline{display:inline-flex;align-items:center;gap:3px;vertical-align:middle}form.inline button{padding:5px 8px;min-height:27px;font-size:11px}form.inline label{white-space:nowrap;font-size:10px}form.inline input[type=checkbox]{min-height:unset;vertical-align:middle;accent-color:var(--blue);margin-right:3px}.notice{color:#167d4e;border-color:#d7eee4;background:#f8fffa}.issued-list{display:block;width:100%;min-height:100px;resize:vertical;font:12px ui-monospace,monospace;border-radius:11px}main[data-panel]{display:none}main[data-panel].active{display:block}main[data-panel] section:last-child{margin-bottom:0}section>form:not(.inline){display:flex;align-items:center;flex-wrap:wrap;gap:7px;margin-bottom:10px}section>form:not(.inline)>input[name=label]{flex:2 1 190px}section>form:not(.inline)>input[type=number]{width:70px}section>form:not(.inline) label{display:flex;gap:5px;align-items:center;font-size:11px}section>form:not(.inline) label input{width:63px}section p{margin:8px 0 10px}table{width:100%;border-collapse:collapse;white-space:nowrap;font-size:11px}td,th{text-align:left;padding:10px 8px;border-bottom:1px solid #ebeff4}th{color:#78859b;font-weight:600;background:#f8fafc}td{color:#3b4658}.scroll{overflow-x:auto;-webkit-overflow-scrolling:touch;margin-top:10px;border:1px solid #eef1f6;border-radius:11px}tr:last-child td{border-bottom:0}#device-overview .stats{grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}#device-overview .stat{padding:9px 8px;min-height:62px}#device-overview .stat b{font-size:19px}#device-overview .stat small{font-size:10px}#device-overview p{display:flex;flex-wrap:wrap;align-items:center;gap:6px}#device-overview #presence-query{flex:1 1 155px;min-width:130px}#device-overview select{max-width:125px}#device-overview p label{font-size:11px}.bottom-nav{position:fixed;inset:auto 0 0;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:0;background:#fff;border-top:1px solid #edf0f4;box-shadow:0 -4px 16px rgba(20,46,80,.035);padding:5px 10px calc(6px + env(safe-area-inset-bottom));z-index:50;max-width:850px;margin:0 auto}.bottom-nav button{background:transparent;color:#8792a7;border:0;border-radius:10px;padding:6px 1px;font-size:10px;font-weight:500;min-height:47px}.bottom-nav button.active{background:transparent;color:var(--blue);font-weight:650}.bottom-nav svg{display:block;margin:0 auto 3px;width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:1.9;stroke-linejoin:round;stroke-linecap:round}.bottom-nav button.active svg{stroke-width:2.3}@media(min-width:650px){body{padding:24px 20px 100px}.stats{grid-template-columns:repeat(5,minmax(0,1fr))}#device-overview .stats{grid-template-columns:repeat(3,minmax(0,1fr))}header h1{font-size:24px}}@media(max-width:360px){body{padding-left:10px;padding-right:10px}.stat{padding:10px}.stat b{font-size:21px}}


/* LUIYo iOS native compact UI: visual-only additions, no authorization changes */
:root{--blue:#2679f6;--label:#161c26;--secondary:#7d8ba1;--line:#e9edf3;--group:#f4f7fb}
body{background:#f4f6fa;max-width:780px;padding:12px 14px calc(90px + env(safe-area-inset-bottom));font-size:13px}
header{padding:6px 2px 10px;margin-bottom:6px}header h1{font-size:22px;font-weight:750;margin-bottom:5px}header small{font-size:10px;max-width:100%}
section{border:1px solid #edf0f5;border-radius:16px;padding:13px 13px;margin:0 0 10px;background:#fff;box-shadow:0 3px 16px rgba(15,38,68,.025)}
section h2{font-size:14px;font-weight:720;margin:1px 0 12px}
.stats{gap:7px}.stat{min-height:69px;padding:11px 12px;position:relative;border-radius:12px;background:#f3f6fb;border:0}.stat small{font-size:10px;padding-right:18px}.stat b{font-size:21px;color:#1b2535}.stat-icon{position:absolute;right:12px;bottom:12px;font-size:16px;font-weight:700;color:#2580ff}
.stat:nth-child(2) .stat-icon{color:#28bb76}.stat:nth-child(4) .stat-icon{color:#f06970}
.screen-title{display:flex;gap:9px;align-items:center;padding:12px 3px 13px}.screen-title h1{font-size:19px;letter-spacing:-.4px;margin:0;font-weight:750}.screen-title small{margin-left:auto;font-size:10px}.title-icon{color:#2175f6;font-size:21px;line-height:1}
body:not([data-current-panel="overview"]) header{display:none}
.info-note{font-size:11px;color:#637c9c;background:#eff5ff;padding:12px;border-radius:12px;line-height:1.65;margin-bottom:14px}
.code-form{display:grid!important;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px!important;align-items:stretch!important;margin-bottom:9px!important}
.code-form .full{grid-column:1/-1}.form-field{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:6px!important;min-width:0;font-size:12px!important;color:#34425a;font-weight:580}
.code-form .form-field input{width:100%!important;min-height:40px!important;font-size:14px;background:#f6f8fb;border:1px solid #e7ebf2}.code-form .form-field small{font-size:10px;color:#7291b6}
.code-form .primary-action{height:43px;font-size:14px;border-radius:11px;background:#2679f6;font-weight:640}
.code-section>small{display:block;font-size:10px;line-height:1.6}
#device-overview .stat{min-height:63px}#device-overview .stats{gap:6px}
#device-overview p{display:grid;grid-template-columns:1fr auto;gap:8px;align-items:center}
#device-overview p>label{grid-column:1/-1;width:100%;display:flex;gap:8px;align-items:center}#device-overview p select{max-width:none;flex:1}
#device-overview #presence-query{min-width:0;width:100%;flex:unset}
#device-overview p button{align-self:stretch}
.scroll{max-width:100%;overflow-x:auto;border:1px solid #edf0f4;border-radius:12px;margin-top:11px}
table{min-width:510px;font-size:11px}th,td{padding:11px 9px}thead{background:#f7f9fc}th{font-size:10px;color:#77869b}td{font-size:11px}
#device-overview .scroll table{min-width:850px}
.license-section table{min-width:495px}.license-section th:last-child,.license-section td:last-child{position:sticky;right:0;background:#fff;box-shadow:-7px 0 10px -10px #a5b0c5;min-width:53px;text-align:center}
.license-section th:last-child{background:#f8fafc}
.state-pill{font-size:10px;font-weight:600;padding:4px 7px;border-radius:7px;white-space:nowrap}.state-pill.on{color:#1b995a;background:#e6f7ed}.state-pill.off{color:#bd5d39;background:#fff0e9}
.action-menu{position:relative;min-width:35px}.action-menu summary{list-style:none;cursor:pointer;border:1px solid #e8edf4;background:#f7f9fc;border-radius:9px;padding:5px 7px;color:#667b9a;font-size:15px;line-height:1}.action-menu summary::-webkit-details-marker{display:none}
.action-menu-inner{position:relative;min-width:170px;display:grid;gap:8px;padding:10px 1px}.action-menu-inner .inline{display:flex;gap:5px;align-items:center;justify-content:space-between;white-space:nowrap}.action-menu-inner button{font-size:11px}.action-menu-inner input[type=checkbox]{flex:0 0 auto}
.bottom-nav{max-width:780px;border-top:1px solid #ecf0f5;box-shadow:none;padding:6px 12px calc(7px + env(safe-area-inset-bottom));background:rgba(255,255,255,.97)}
.bottom-nav button{font-size:10px;min-height:48px;border-radius:10px}.bottom-nav button.active{color:#2778f6;background:#edf5ff}.bottom-nav svg{width:19px;height:19px}
@media(max-width:420px){body{padding-left:11px;padding-right:11px}section{padding:12px}.stat{padding:10px}.stat small{font-size:9.5px}.stat b{font-size:21px}}

/* Exact-reference Apple native minimal UI — responsive structural UI layer. */
:root{--blue:#287bfa;--label:#121824;--group:#f4f7fb;--line:#e9eef5}
html,body{min-height:100%;touch-action:manipulation}
body{background:#f2f5fa;padding:15px 14px calc(84px + env(safe-area-inset-bottom));font-size:13px;max-width:740px}
header{padding:7px 2px 11px;align-items:center;margin:0 0 8px}
header h1{font-size:21px;font-weight:760;letter-spacing:-.45px;margin:0 0 5px;color:#151b27}
header small{max-width:480px;line-height:1.5;font-size:10.5px;color:#8592a8}
header>a{border-radius:11px;font-size:12px;padding:6px 11px;background:#e8f1ff}
section{padding:14px;border:1px solid #edf1f7;border-radius:15px;margin-bottom:10px;box-shadow:0 2px 9px rgba(18,44,78,.025)}
section h2{font-size:14px;letter-spacing:0;margin:0 0 12px;font-weight:720}
.stat{background:#f3f6fb;border:0;border-radius:11px;padding:10px 11px;min-height:68px}
.stat small{color:#7b89a2;font-size:10.5px;margin-bottom:6px}
.stat b{font-size:22px;color:#131a27;font-weight:740}
.stat-icon{right:12px;bottom:11px;color:#2b7cf1;font-size:17px}
.stats{gap:8px}
.dashboard-presence{margin-top:9px}
.dash-section-title{display:flex;align-items:center;justify-content:space-between;gap:10px}
.dash-section-title h2{margin:0 0 12px}
.drilldown{border:0;background:transparent;color:#7b8ba6;padding:0 0 10px;font-size:11px;min-height:0}
.drilldown span{font-size:19px;vertical-align:-1px;color:#8ba4cc}
.dashboard-mini{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}
.dashboard-mini>div{background:#f3f6fb;border-radius:11px;padding:10px 8px;min-width:0;position:relative;min-height:65px}
.dashboard-mini small{display:block;font-size:9.5px;color:#788aa5;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;padding-right:9px}
.dashboard-mini b{display:block;font-size:21px;line-height:1.4;color:#161e2e;margin-top:3px}
.home-mini-icon{position:absolute;right:9px;bottom:11px;font-size:12px;font-weight:700;color:#2882f9}.home-mini-icon.green{color:#26ae75}.home-mini-icon.orange{color:#ea8d32}
.screen-title{padding:8px 3px 15px;gap:8px}.screen-title h1{font-size:21px}.title-icon{font-size:21px}
.info-note{color:#637a9a;background:#f0f5fd;border-radius:11px;padding:12px;font-size:11px;margin-bottom:12px}
.code-form{display:grid!important;grid-template-columns:1fr!important;gap:0!important}
.code-form .form-field,.code-form .full{grid-column:1/-1}
.code-form .form-field{display:flex!important;flex-direction:column;gap:7px!important;margin:0;padding:11px 1px;border-bottom:1px solid #eef1f5;font-size:12px}
.code-form .form-field.full:first-of-type{padding-top:4px}
.code-form .form-field input[name="label"]{height:40px;background:#f6f8fb;border:1px solid #e9edf2}
.code-form .form-field:not(.full){flex-direction:row!important;align-items:center!important;justify-content:space-between}
.code-form .form-field:not(.full)>label{min-width:92px}
.code-form .form-field:not(.full)>small{font-size:10px;white-space:nowrap}
.native-stepper{display:flex;align-items:center;flex:0 0 154px;background:#f5f7fb;border:1px solid #e8edf4;border-radius:10px;overflow:hidden;height:37px}
.native-stepper input{border:0!important;background:transparent!important;min-width:0!important;width:48px!important;flex:1;text-align:center;padding:0!important;min-height:35px!important;font-size:13px!important;-moz-appearance:textfield;appearance:textfield}
.native-stepper input::-webkit-inner-spin-button,.native-stepper input::-webkit-outer-spin-button{-webkit-appearance:none;margin:0}
.native-stepper .step-control{background:#f1f4f9!important;color:#2f7ff6!important;border-radius:0!important;font-size:19px!important;min-width:36px!important;padding:0!important;height:37px!important;min-height:37px!important;font-weight:500}
.native-stepper .step-control:first-child{border-right:1px solid #e7ecf4}.native-stepper .step-control:last-child{border-left:1px solid #e7ecf4}
.code-form .primary-action{width:100%;height:43px;border-radius:10px;margin-top:14px;background:#287dff;font-size:13px}
.code-section>small{display:block;font-size:10px;line-height:1.65;padding:0 2px}
.bottom-nav{padding:6px 13px calc(7px + env(safe-area-inset-bottom));border:1px solid #f0f2f6;border-bottom:0;box-shadow:0 -2px 14px rgba(36,52,78,.03);max-width:740px}
.bottom-nav button{height:49px;min-height:49px;border-radius:12px;font-size:10.5px;padding:5px 1px}
.bottom-nav button.active{background:#eff5ff;color:#287bf7}
.bottom-nav svg{width:19px;height:19px;stroke-width:1.75}
#device-overview .stats{gap:7px}
#device-overview .stat{min-height:61px;padding:9px 7px}
#device-overview .stat b{font-size:19px}
#device-overview p{display:grid;grid-template-columns:minmax(0,1fr) 66px;gap:7px}
#device-overview p label{grid-column:1/-1;display:flex;align-items:center}
#device-overview p label select{flex:1;min-width:0}
#device-overview p>input{grid-column:1;width:100%!important;min-width:0}
#device-overview p>button{grid-column:2}
.scroll{border-radius:12px;overflow-x:auto;max-width:100%}
#device-overview .scroll table{min-width:740px}
.license-section .scroll{border:0;overflow:visible}
.license-section table{min-width:0;border-collapse:separate;border-spacing:0 7px;width:100%}
.license-section thead{display:none}
.license-section tbody{display:grid;gap:8px}
.license-section tr{display:grid;grid-template-columns:1fr auto;position:relative;border:1px solid #edf1f6;border-radius:11px;background:#f9fbfe;padding:9px 11px;gap:5px 10px;min-width:0}
.license-section td{border:0;padding:0!important;display:flex;align-items:center;gap:7px;white-space:normal;min-width:0}
.license-section td::before{content:attr(data-label);color:#8491a6;font-size:10px;min-width:44px;flex:0 0 auto}
.license-section td:nth-child(1){font-weight:650}.license-section td:nth-child(2){grid-column:1}.license-section td:nth-child(3){grid-column:1}.license-section td:nth-child(4){grid-column:1}
.license-section td:nth-child(5){grid-column:2;grid-row:1;font-size:11px;justify-self:end}.license-section td:nth-child(5)::before{display:none}
.license-section td:nth-child(6){grid-column:2;grid-row:2/5;justify-self:end;align-self:center;position:static!important;box-shadow:none!important;background:transparent!important;min-width:0!important}
.license-section td:nth-child(6)::before{display:none}
.license-section .action-menu{min-width:34px;position:relative}
.license-section .action-menu summary{font-size:15px;padding:6px 9px;border-radius:9px}
.license-section .action-menu[open]{z-index:10}
.license-section .action-menu-inner{position:absolute;right:0;top:calc(100% + 7px);background:white;min-width:195px;border-radius:12px;border:1px solid #e7ebf2;box-shadow:0 12px 32px rgba(25,41,75,.16);padding:10px;z-index:10}
.license-section .action-menu-inner form.inline{white-space:normal;justify-content:space-between}
.license-section .action-menu-inner form.inline label{font-size:11px}
#device-overview+section .scroll{border:0;overflow:visible}
#device-overview+section table{min-width:0}
#device-overview+section thead{display:none}
#device-overview+section tbody{display:grid;gap:8px}
#device-overview+section tr{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px 9px;padding:10px;background:#f9fbfe;border:1px solid #e9edf4;border-radius:11px}
#device-overview+section td{border:0;padding:0;min-width:0;white-space:normal;overflow-wrap:anywhere;font-size:11px}
#device-overview+section td::before{content:attr(data-label)'：';display:block;font-size:10px;color:#8290a6;margin-bottom:2px}
#device-overview+section td:last-child{grid-column:1/-1;padding-top:6px;border-top:1px solid #edf1f6;display:block}
#device-overview+section form.inline{display:flex;justify-content:space-between;gap:7px}
#device-overview+section form.inline input[name="reason"]{flex:1;min-width:0}
@media(min-width:650px){.license-section tbody{grid-template-columns:repeat(2,minmax(0,1fr))}#device-overview+section tbody{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:360px){body{padding-left:11px;padding-right:11px}.native-stepper{flex-basis:136px}.stats .stat small{font-size:9.3px}}

/* Build 22 agreed 4-panel compact Apple-style UI — no glass, no colored tab box. */
body{background:#f4f6fa;color:#121a28;padding:12px 13px calc(78px + env(safe-area-inset-bottom));font-size:13px}
main[data-panel]{min-width:0}section{border:1px solid #edf0f5;border-radius:16px;padding:13px;margin-bottom:11px;background:#fff;box-shadow:none}
section h2{font-size:15px;margin:0 0 10px}.screen-title{padding:7px 2px 13px}.screen-title h1{font-size:20px}
.stats .stat{min-height:69px;border:0}.dashboard-presence .dashboard-mini b{min-height:29px}.dashboard-mini>div{padding:10px 8px}
.shortcut-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px}.shortcut-grid button{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:7px;min-height:66px;padding:8px 2px;color:#495a72;background:#f4f7fb;border-radius:12px;font-size:10.5px;font-weight:600}.shortcut-grid button span{display:grid;place-items:center;width:30px;height:30px;background:#e4eeff;border-radius:50%;font-size:20px;color:#287afa}
.bottom-nav button.active{background:transparent!important;box-shadow:none!important;border:0!important;color:#287aff!important}.bottom-nav button{background:transparent!important}.bottom-nav{box-shadow:none;border-top:1px solid #edf0f5;background:#fff}
.code-form{display:flex!important;flex-direction:column!important;gap:0!important;margin:0!important}.code-form .form-field{display:flex!important;flex-direction:row!important;align-items:center!important;justify-content:space-between!important;gap:10px!important;min-height:53px;padding:9px 0!important;margin:0!important;border-bottom:1px solid #eef1f6}.code-form .form-field.full:first-of-type{display:flex!important;flex-direction:column!important;align-items:stretch!important;gap:7px!important;margin-bottom:4px!important}.code-form .form-field label{font-size:12px;font-weight:600}.code-form .form-field input[name=label]{width:100%!important;height:39px!important;min-height:39px!important}.code-form .form-field .native-stepper{width:153px!important;flex:0 0 153px!important;height:36px!important;min-height:36px!important}.native-stepper .step-control{width:39px!important;min-width:39px!important;height:36px!important;min-height:36px!important}.native-stepper input{width:60px!important;min-height:34px!important}.field-hint{font-size:10px;color:#8796af;font-weight:400;margin-left:6px;white-space:nowrap}.code-form .primary-action{height:41px!important;margin-top:12px!important;font-size:13px!important}.info-note{margin-bottom:9px!important;font-size:11px;padding:10px!important}
.generation-history{margin-top:11px}.history-tools{display:flex;align-items:center;gap:7px}.history-tools label{font-size:10.5px;color:#6d7b94;white-space:nowrap}.history-tools input{min-height:0;vertical-align:middle;accent-color:#287aff}.history-tools button{font-size:11px;min-height:28px;padding:6px 8px}.history-batch{border-top:1px solid #edf1f6;padding:10px 0}.batch-title{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:5px;margin:0 0 6px}.batch-title b{font-size:11px}.batch-title small{font-size:10px;color:#8795ab}.history-code{display:flex;align-items:center;gap:8px;border-bottom:1px solid #f0f2f6;padding:9px 1px;min-width:0}.history-code:last-child{border:0}.history-code input{min-height:0;flex:0 0 auto;accent-color:#287aff}.history-code-text{font:600 11.5px/1.5 ui-monospace,SFMono-Regular,monospace;overflow-wrap:anywhere;flex:1;min-width:0}.history-code button{background:#eef4ff;color:#287aff;padding:5px 8px;min-height:28px;white-space:nowrap}.empty-history,.history-warning,.license-disclaimer{font-size:10.5px;color:#7b8ca5;line-height:1.6;margin:7px 0}.history-warning{border-top:1px solid #edf1f6;padding-top:9px}
.legacy-search{display:flex;gap:7px;margin:0 0 9px}.legacy-search input{flex:1;min-width:0;min-height:37px;font-size:12px}.legacy-search button{flex:0 0 auto;background:#edf4ff;color:#267afa;padding:7px 11px}
.license-section .between{margin-bottom:9px}.license-section .between h2{margin:0}.license-section #license-search{width:100%;min-height:37px;font-size:12px;margin-bottom:6px}.license-list{display:grid;gap:8px}.license-item{background:#f8fafd;border:1px solid #e9eef6;border-radius:12px;padding:11px 12px;min-width:0}.license-line{display:flex;align-items:center;justify-content:space-between;gap:10px}.license-line strong{font-size:12.5px}.license-line.subtitle{font-size:11px;color:#65758f;justify-content:flex-start;margin:4px 0 7px}.license-details{display:flex;align-items:center;gap:14px;flex-wrap:wrap;color:#697993;font-size:11px}.license-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:7px}.license-actions .inline{margin:0}.license-actions button.outline-alert{border:1px solid #f4a0a9;border-radius:9px;background:#fff;color:#e2475a;min-height:29px;padding:5px 13px;font-size:11px}.license-actions button:hover{background:#fff3f4}.state-pill{font-size:10px}
@media(max-width:380px){.shortcut-grid{gap:5px}.shortcut-grid button{font-size:9.5px}.code-form .form-field .native-stepper{flex-basis:138px!important;width:138px!important}.license-item{padding:10px}}

.license-code{display:flex;align-items:center;justify-content:space-between;gap:8px;font:600 11px/1.5 ui-monospace,monospace;overflow-wrap:anywhere;margin-top:5px;color:#26497b}.license-code span{flex:1;min-width:0}.license-code button{min-height:25px;padding:4px 9px;background:#edf4ff;color:#277af4;font-size:10.5px}.license-code.unavailable{font:10px/1.5 system-ui;color:#97a1b2}[hidden]{display:none!important}
/* Mobile actions and responsive history controls */
[hidden]{display:none!important}
.license-actions{display:flex!important;gap:8px!important;justify-content:flex-end!important;align-items:center!important;margin-top:7px!important}
.license-actions form{margin:0!important;flex:0 0 auto}.license-actions button{min-width:54px;height:33px;min-height:33px;padding:5px 10px}
.license-item{position:relative;min-height:0!important;padding:11px 12px!important}
.history-code{display:flex;align-items:center;gap:10px;min-width:0;padding:9px 0;border-bottom:1px solid #edf0f5}
.history-code-text{flex:1;min-width:0;overflow-wrap:anywhere;user-select:text;-webkit-user-select:text}
.history-code .copy-code{flex:0 0 auto}
#presence-refresh,.step-control,.copy-code,.bottom-nav button{touch-action:manipulation}
@media(max-width:440px){.license-actions{gap:7px}.license-actions button{min-width:53px}}

/* All registered devices on phone: each actual server row is shown as a readable card. */
.presence-list-count{font-size:11px;color:#657792;margin:10px 2px 5px;font-weight:550}
.license-item{padding:9px 11px!important}
.license-item .license-line:first-child{align-items:center;gap:7px;min-height:31px}
.license-top-right{display:flex;align-items:center;justify-content:flex-end;gap:7px;flex-wrap:nowrap;margin-left:auto}
.license-top-right .state-pill{white-space:nowrap;flex:0 0 auto}
.license-top-right .license-actions{display:flex!important;align-items:center!important;gap:5px!important;margin:0!important;flex:0 0 auto}
.license-top-right .license-actions form{display:inline-flex!important;margin:0!important}
.license-top-right .license-actions button{height:28px!important;min-height:28px!important;min-width:46px!important;padding:4px 7px!important;border-radius:8px!important;font-size:10.5px!important}
.license-item .license-code{margin-top:3px}
.license-item .license-line.subtitle{margin:3px 0 4px}
.license-item .license-details{gap:10px}
@media(max-width:650px){
 #device-overview .presence-scroll{overflow:visible;border:0;margin-top:6px}
 #device-overview .presence-scroll table{display:block;width:100%;min-width:0!important;max-width:100%;border:0}
 #device-overview .presence-scroll thead{display:none}
 #device-overview .presence-scroll tbody{display:grid;gap:8px;width:100%}
 #device-overview .presence-scroll tr{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px 10px;padding:11px;border:1px solid #e6edf7;border-radius:12px;background:#f8fafd;min-width:0}
 #device-overview .presence-scroll td{display:flex;flex-direction:column;align-items:flex-start;gap:3px;min-width:0;padding:0!important;white-space:normal;overflow-wrap:anywhere;border:0;font-size:11px;line-height:1.4}
 #device-overview .presence-scroll td::before{content:attr(data-label);font-size:10px;color:#8290a5;font-weight:500}
 #device-overview .presence-scroll td:nth-child(1){font-weight:700;color:#2859a6}
 #device-overview .presence-scroll td:nth-child(3),#device-overview .presence-scroll td:nth-child(4),#device-overview .presence-scroll td:nth-child(7){grid-column:1/-1}
 #device-overview .presence-scroll tr:has(td[colspan]){display:block}
 #device-overview .presence-scroll td[colspan]::before{display:none}
}
@media(max-width:380px){.license-top-right{gap:4px}.license-top-right .license-actions{gap:3px!important}.license-top-right .license-actions button{min-width:42px!important;padding:4px 6px!important;font-size:10px!important}}
@media(max-width:650px){
 #device-overview .presence-scroll tbody{gap:6px!important}
 #device-overview .presence-scroll tr{padding:8px 10px!important;gap:4px 9px!important;border-radius:11px!important}
 #device-overview .presence-scroll td{gap:1px!important;line-height:1.3!important;font-size:11px!important}
 #device-overview .presence-scroll td::before{font-size:9px!important}
 #device-overview .presence-scroll td button{min-height:28px!important;padding:5px 9px!important}
}
@media(max-width:650px){
 #device-overview .presence-scroll tbody{display:grid!important;gap:6px!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])){
  display:grid!important;grid-template-columns:repeat(12,minmax(0,1fr))!important;
  gap:3px 5px!important;padding:9px 9px!important;background:#fff!important;
  align-items:center!important;min-width:0!important;
 }
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td{
  grid-column:auto!important;min-width:0!important;display:block!important;
  padding:0!important;margin:0!important;border:0!important;
  font-size:11px!important;line-height:1.45!important;
  white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;
 }
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td::before{display:none!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(1){grid-column:span 4!important;color:#2674ef!important;font-weight:700!important;font-size:12px!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(2){grid-column:span 2!important;text-align:center!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(3){grid-column:span 3!important;text-align:center!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(6){grid-column:span 3!important;text-align:right!important;color:#66758d!important;font-size:9px!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(4){grid-column:span 8!important;color:#63718a!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(5){grid-column:span 4!important;color:#63718a!important;text-align:right!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(7){grid-column:span 2!important;text-align:right!important;overflow:visible!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(7) button{min-height:27px!important;padding:5px 7px!important;font-size:10px!important;white-space:nowrap!important}
}

/* Compact device rows: preserve the existing admin theme and navigation. */
.device-grant-section{padding:14px 16px!important}
.device-grant-section h2{margin:0 0 10px!important}
.device-grant-form{display:flex;align-items:center;gap:8px;margin:0 0 7px!important}
.device-grant-form label{flex:0 0 auto}.device-grant-form input{flex:1;min-width:0;margin:0!important}
.device-grant-form button{flex:0 0 auto;margin:0!important;white-space:nowrap;padding:10px!important}
.legacy-devices td[data-label="设备码"]{overflow:visible!important;text-overflow:clip!important;white-space:normal!important;word-break:normal!important;min-width:0}
@media(max-width:650px){
 #device-overview .presence-scroll tr:not(:has(td[colspan])){gap:3px 6px!important;padding:9px!important;min-height:0!important;grid-template-columns:repeat(12,minmax(0,1fr))!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(1){grid-column:span 4!important;grid-row:1!important;overflow:visible!important;white-space:nowrap!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(2){grid-column:span 2!important;grid-row:1!important;text-align:center!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(3){grid-column:span 6!important;grid-row:1!important;text-align:right!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(4){grid-column:span 9!important;grid-row:2!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(5){grid-column:span 3!important;grid-row:2!important;text-align:right!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(6){grid-column:span 9!important;grid-row:3!important;text-align:left!important}
 #device-overview .presence-scroll tr:not(:has(td[colspan])) td:nth-child(7){grid-column:span 3!important;grid-row:3!important;text-align:right!important}
 .device-grant-form{display:grid;grid-template-columns:auto minmax(0,1fr) auto auto;gap:6px}
 .legacy-devices tr{padding:10px!important;gap:7px 10px!important}
}
</style></head><body data-server-panel="<?=e($requestedPanel)?>">
<header><div><h1>LUIYo 用户管理</h1><small>统计按设备计数；每日活跃按 UTC 日期；新版 App 每 30 秒上报；90 秒未上报即显示离线。时间按北京时间显示。</small></div><a href="?logout=1">退出</a></header>
<?php if($notice||$error):?><section class="notice" role="status" id="admin-flash"><?=e($notice?:$error)?></section><?php endif;?>
<main data-panel="overview" class="active"><section><h2>统计总览</h2><div class="stats"><?php foreach($stats as $label=>$num):?><div class="stat"><small><?=e($label)?></small><b><?= $num ?></b><span class="stat-icon" aria-hidden="true"><?= match($label){'累计激活设备'=>'▣','今日活跃设备'=>'●','近7日活跃设备'=>'▥','已封禁设备'=>'⊘', default=>'⚿'} ?></span></div><?php endforeach;?></div></section><section class="dashboard-presence" aria-label="设备与在线用户摘要"><div class="dash-section-title"><h2>设备与在线用户</h2><button type="button" class="drilldown" data-goto="devices" aria-label="进入设备管理">查看全部 <span aria-hidden="true">›</span></button></div><div class="dashboard-mini"><div><small>新版登记设备</small><b id="home-presence-total">—</b><span class="home-mini-icon" aria-hidden="true">▣</span></div><div><small>当前在线</small><b id="home-presence-online">—</b><span class="home-mini-icon green" aria-hidden="true">●</span></div><div><small>未授权设备</small><b id="home-presence-unlicensed">—</b><span class="home-mini-icon orange" aria-hidden="true">!</span></div></div></section><section class="home-shortcuts"><h2>快捷导航</h2><div class="shortcut-grid"><button type="button" data-goto="codes"><span aria-hidden="true">＋</span>生成卡密</button><button type="button" data-goto="devices"><span aria-hidden="true">▤</span>设备管理</button><button type="button" data-goto="licenses"><span aria-hidden="true">⚿</span>卡密管理</button><button type="button" id="dash-refresh"><span aria-hidden="true">↻</span>刷新</button></div></section></main>
<main data-panel="codes"><div class="screen-title"><span class="title-icon" aria-hidden="true">▤</span><h1>生成激活码</h1></div>
<section class="code-section"><div class="info-note">每次可生成 1–100 个，0 天表示永久。新卡密只在当前管理员会话内保留近期记录，请及时复制备份。</div>
<form method="post" action="admin.php?panel=codes" class="code-form"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="action" value="create">
<label class="form-field full"><span>备注</span><input name="label" placeholder="例如：张三" maxlength="80"></label>
<div class="form-field"><label for="max-devices">设备数上限</label><span class="native-stepper"><button type="button" class="step-control" data-for="max-devices" data-dir="-1" aria-label="减少设备数">−</button><input id="max-devices" name="max_devices" type="number" min="1" max="100" value="1" required><button type="button" class="step-control" data-for="max-devices" data-dir="1" aria-label="增加设备数">＋</button></span></div>
<div class="form-field"><label for="valid-days">有效天数 <small class="field-hint">0 为永久</small></label><span class="native-stepper"><button type="button" class="step-control" data-for="valid-days" data-dir="-1" aria-label="减少有效天数">−</button><input id="valid-days" name="days" type="number" min="0" max="3650" value="0" required><button type="button" class="step-control" data-for="valid-days" data-dir="1" aria-label="增加有效天数">＋</button></span></div>
<div class="form-field"><label for="quantity">生成数量</label><span class="native-stepper"><button type="button" class="step-control" data-for="quantity" data-dir="-1" aria-label="减少生成数量">−</button><input id="quantity" name="quantity" type="number" min="1" max="100" value="1" required><button type="button" class="step-control" data-for="quantity" data-dir="1" aria-label="增加数量">＋</button></span></div>
<button class="primary-action full" type="submit">批量生成卡密</button></form></section>
<section class="generation-history"><div class="between"><h2>近期生成记录</h2><div class="history-tools"><label><input id="history-select-all" type="checkbox"> 全选</label><button type="button" id="history-copy-selected">批量复制</button></div></div>
<?php $recentBatches=$_SESSION['luiyo_recent_batches']??[]; if(!$recentBatches): ?><p class="empty-history">暂时没有本次管理员会话内生成的卡密。</p><?php else: ?>
<?php foreach($recentBatches as $batchIndex=>$batch):?><div class="history-batch"><div class="batch-title"><b><?=e(gmdate('Y-m-d H:i',(int)$batch['at']+28800))?></b><small>设备上限 <?=(int)$batch['max_devices']?> · <?= (int)$batch['days']===0?'永久':((int)$batch['days'].' 天')?> · <?=count($batch['codes'])?> 条</small></div>
<?php foreach($batch['codes'] as $code):?><div class="history-code"><input type="checkbox" class="history-select" value="<?=e($code)?>"><span class="history-code-text"><?=e($code)?></span><button type="button" class="copy-code" data-copy="<?=e($code)?>" aria-label="复制该卡密">复制</button></div><?php endforeach;?></div><?php endforeach;?>
<?php endif; ?><p class="history-warning">安全提示：旧卡密数据库只保存不可逆哈希，无法恢复明文。近期记录保存在当前管理员会话中，会话结束后可能丢失；请及时复制到安全位置。</p></section>
</main>
<main data-panel="devices"><div class="screen-title"><span class="title-icon" aria-hidden="true">▣</span><h1>设备与在线用户</h1></div>
<section class="device-grant-section"><h2>设备码授权</h2><form method="post" action="admin.php?panel=devices" class="device-grant-form"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><label for="grant-device-code">设备码</label><input id="grant-device-code" name="device_code" placeholder="D-000001" pattern="D-[0-9]{6,9}" required autocapitalize="characters"><button name="action" value="grant_device">授权 SVIP 3</button><button name="action" value="revoke_device" class="danger">撤销</button></form><small>输入已登记设备的完整编号；新版 App 联网后自动领取，不会覆盖已有卡密授权。</small></section>
<section id="device-overview"><div class="between"><h2>设备与在线用户</h2><small id="presence-update">正在更新…</small></div><div class="stats"><div class="stat"><small>新版登记设备</small><b id="presence-total">—</b></div><div class="stat"><small>当前在线</small><b id="presence-online">—</b></div><div class="stat"><small>未授权设备</small><b id="presence-unlicensed">—</b></div></div><p><label>筛选 <select id="presence-filter"><option value="all">全部设备</option><option value="online">在线设备</option><option value="licensed">已授权</option><option value="unlicensed">未授权</option></select></label><input id="presence-query" placeholder="搜索设备码或备注" aria-label="搜索设备"><button id="presence-refresh" type="button">刷新</button></p><small>未授权可登记设备，首页功能仍需激活。设备码为安装标识。旧版 App 记录在下方授权设备列表保留。列表显示服务器已登记的全部设备；每 10 秒刷新一次。</small><input type="hidden" id="presence-csrf" value="<?=e($_SESSION['csrf'])?>"><div class="presence-list-count" id="presence-list-count" aria-live="polite">正在获取设备列表…</div><div class="scroll presence-scroll"><table><thead><tr><th>设备码</th><th>在线</th><th>授权</th><th>设备 / 版本</th><th>当前页面</th><th>最近使用</th><th>操作</th></tr></thead><tbody id="presence-rows"><tr><td colspan="7">正在载入设备…</td></tr></tbody></table></div></section><section class="legacy-devices"><h2>原有授权设备管理（最近 200 条）</h2><div class="legacy-search"><input type="search" id="legacy-search" placeholder="搜索设备码、卡密备注或时间" aria-label="搜索原有授权设备"><button type="button" id="legacy-search-clear">清空</button></div><div class="scroll"><table><thead><tr><th>设备码</th><th>激活码备注</th><th>最近活跃（北京）</th><th>状态</th><th>操作</th></tr></thead><tbody>
<?php foreach($devices as $d):?><tr><td data-label="设备码"><?= !empty($d['installation_id'])?e('D-'.str_pad((string)$d['installation_id'],6,'0',STR_PAD_LEFT)):e('未登记设备（记录 #'.$d['id'].'）') ?></td><td data-label="卡密备注"><?=e($d['label'])?></td><td data-label="最近活跃"><?=e(gmdate('Y-m-d H:i',(int)$d['last_seen']+28800))?></td><td data-label="状态"><?= $d['banned']?'已封禁':'正常' ?></td><td data-label="操作"><form method="post" action="admin.php?panel=devices" class="inline"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$d['id']?>"><input type="hidden" name="action" value="<?=$d['banned']?'unban':'ban'?>"><?php if(!$d['banned']):?><input name="reason" maxlength="120" placeholder="封禁原因"><?php endif;?><button class="<?=$d['banned']?'':'danger'?>"><?=$d['banned']?'解除封禁':'封禁'?></button></form></td></tr><?php endforeach;?></tbody></table></div></section></main>
<main data-panel="licenses"><div class="screen-title"><span class="title-icon" aria-hidden="true">⚿</span><h1>卡密管理</h1><small>最近 200 条</small></div>
<section class="license-section"><div class="between"><h2>激活码列表</h2><small>点击编号查看授权信息</small></div><input type="search" id="license-search" placeholder="搜索卡密编号或备注" aria-label="搜索卡密记录">
<p class="license-disclaimer">旧卡密仅存哈希，无法显示明文。新生成的卡密请在「生成卡密 → 近期生成记录」中复制。</p>
<div class="license-list"><?php foreach($licenses as $l):?><article class="license-item" data-filter="<?=e(mb_strtolower('#'.$l['id'].' '.$l['label']))?>"><div class="license-line"><strong>卡密 #<?=(int)$l['id']?></strong><div class="license-top-right"><span class="state-pill <?= $l['disabled']?'off':'on' ?>"><?=$l['disabled']?'已停用':'正常'?></span><div class="license-actions"><form method="post" action="admin.php?panel=licenses" class="inline"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$l['id']?>"><input type="hidden" name="action" value="<?=$l['disabled']?'enable':'disable'?>"><button class="outline-alert"><?=$l['disabled']?'启用':'停用'?></button></form>
<form method="post" action="admin.php?panel=licenses" class="inline delete-license-form"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$l['id']?>"><input type="hidden" name="action" value="delete_license"><button type="submit" class="outline-alert">删除</button></form></div></div></div><?php $plainCode=$recentPlainByHash[$l['code_hash']]??null; if($plainCode):?><div class="license-code"> <span><?=e($plainCode)?></span><button type="button" class="copy-code" data-copy="<?=e($plainCode)?>">复制</button></div><?php else: ?><div class="license-code unavailable">历史卡密明文不可恢复</div><?php endif; ?><div class="license-line subtitle">备注：<?=e($l['label']?:'未填写')?></div><div class="license-details"><span>设备 <?=(int)$l['device_count']?> / <?=(int)$l['max_devices']?></span><span>到期 <?= $l['expires_at']?e(gmdate('Y-m-d',(int)$l['expires_at'])):'永久' ?></span></div>
</article><?php endforeach;?></div></section></main>
<nav class="bottom-nav" aria-label="后台页面导航">
<button type="button" class="active" data-nav="overview" aria-current="page"><svg viewBox="0 0 24 24"><path d="M3 11 12 3l9 8v10H3z"/><path d="M9 21v-7h6v7"/></svg>首页</button>
<button type="button" data-nav="codes"><svg viewBox="0 0 24 24"><circle cx="8" cy="15" r="4"/><path d="M11 12 21 2m-5 5 3 3m-6 0 3 3"/></svg>生成卡密</button>
<button type="button" data-nav="devices"><svg viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M8 9h8M8 13h8M8 17h4"/></svg>设备管理</button>
<button type="button" data-nav="licenses"><svg viewBox="0 0 24 24"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/></svg>卡密管理</button>
</nav>
<script src="admin-devices.js?v=1.0.5" defer></script><script src="admin-ui.js?v=1.0.5" defer></script>
</body></html>