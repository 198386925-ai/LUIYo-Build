<?php
declare(strict_types=1);
session_name('LUIYO_ADMIN');
session_set_cookie_params(['httponly'=>true,'secure'=>true,'samesite'=>'Strict']);
session_start();
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');
header('Content-Security-Policy: default-src \'none\'; style-src \'unsafe-inline\'; form-action \'self\'; base-uri \'none\'; frame-ancestors \'none\'');
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
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LUIYo 后台登录</title><style>body{font:16px system-ui;background:#f5f5f7;margin:10vh auto;max-width:360px;padding:20px}form{background:white;border-radius:20px;padding:25px}input,button{font:inherit;width:100%;box-sizing:border-box;padding:12px;margin:10px 0;border-radius:10px;border:1px solid #ddd}button{background:#16181c;color:white}</style><form method="post"><h2>LUIYo 管理后台</h2><p><?= e($error) ?></p><input type="hidden" name="action" value="login"><input type="password" name="password" placeholder="管理员密码" required autocomplete="current-password"><button>登录</button></form></html><?php exit; }
$issued=[];$notice='';
if ($_SERVER['REQUEST_METHOD']==='POST') {
 if (!hash_equals($_SESSION['csrf']??'',(string)($_POST['csrf']??''))) {http_response_code(403);exit('CSRF check failed');}
 $action=(string)($_POST['action']??'');$id=filter_var($_POST['id']??null,FILTER_VALIDATE_INT);
 if ($action==='create') {
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
   $notice='成功生成 '.$quantity.' 个激活码。请立即复制保存，刷新页面后将无法再次查看明文。';
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
$devices=$db->query('SELECT d.id,d.created_at,d.last_seen,d.banned,d.ban_reason,l.label,l.id AS license_id FROM devices d JOIN licenses l ON l.id=d.license_id ORDER BY d.last_seen DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
$licenses=$db->query('SELECT l.id,l.label,l.max_devices,l.expires_at,l.disabled,COUNT(d.id) AS device_count FROM licenses l LEFT JOIN devices d ON d.license_id=l.id GROUP BY l.id ORDER BY l.id DESC LIMIT 200')->fetchAll(PDO::FETCH_ASSOC);
?><!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LUIYo 用户管理</title>
<style>body{font:15px system-ui,-apple-system,sans-serif;background:#f6f7f9;color:#17191d;margin:auto;max-width:1050px;padding:24px}header,section{background:#fff;border:1px solid #e8e8eb;border-radius:18px;padding:20px;margin-bottom:17px}header,.between{display:flex;justify-content:space-between;align-items:center;gap:12px}a{color:#2563eb}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}.stat{background:#f4f5f8;padding:16px;border-radius:14px}.stat b{font-size:27px;display:block}input,button{font:inherit;border:1px solid #ddd;border-radius:9px;padding:9px;margin:3px}button{background:#222;color:white;cursor:pointer}button.danger{background:#aa2233}form.inline{display:inline}table{width:100%;border-collapse:collapse;white-space:nowrap}td,th{border-bottom:1px solid #eee;padding:10px;text-align:left}.scroll{overflow-x:auto}.notice{color:#106a3b}code{background:#f5f5f7;padding:7px;border-radius:6px}.issued-list{width:100%;box-sizing:border-box;min-height:120px;resize:vertical;font:14px ui-monospace,monospace;border:1px solid #cbd5e1;border-radius:12px;padding:14px;background:#f8faff}.license-list{display:grid;gap:12px}.license-card{border:1px solid #e8ebf4;border-radius:15px;padding:16px}.license-card p{color:#667085;margin:8px 0}.actions{display:flex;gap:8px;flex-wrap:wrap}.danger{background:#aa2233}small{color:#6b7280}</style>
<header><div><h1>LUIYo 用户管理</h1><small>统计按设备计数；每日活跃按 UTC 日期；最近 30 分钟有心跳可估算在线（非实时连接数）</small></div><a href="?logout=1">退出</a></header>
<?php if($notice||$error):?><section class="notice"><?=e($notice?:$error)?><?php if($issued):?><p>以下是本次新生成的卡密（仅显示这一次）：</p><textarea class="issued-list" readonly rows="<?=max(4,min(16,count($issued)+1))?>"><?=e(implode("\n",$issued))?></textarea><p><small>长按输入框即可全选复制。请妥善保存，不要公开发送。</small></p><?php endif;?></section><?php endif;?>
<section><h2>统计总览</h2><div class="stats"><?php foreach($stats as $label=>$num):?><div class="stat"><small><?=e($label)?></small><b><?= $num ?></b></div><?php endforeach;?></div></section>
<section><h2>生成激活码</h2><form method="post"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="action" value="create"><input name="label" placeholder="备注（例如：张三）" maxlength="80"><input name="max_devices" type="number" min="1" max="100" value="1" title="允许设备数"><input name="days" type="number" min="0" max="3650" value="0" title="有效天数，0表示永久"><label>生成数量 <input name="quantity" type="number" min="1" max="100" value="1" required></label><button>批量生成卡密</button></form><small>每次可生成 1–100 个；有效天数 0 表示永久。每条激活码使用相同的设备上限和有效天数。由于数据库仅存卡密哈希，历史卡密明文无法恢复；新生成的请立即复制保存。</small></section>
<section><h2>用户设备（最近 200 条）</h2><div class="scroll"><table><thead><tr><th>设备编号</th><th>激活码备注</th><th>最近活跃（UTC）</th><th>状态</th><th>操作</th></tr></thead><tbody>
<?php foreach($devices as $d):?><tr><td>#<?= (int)$d['id'] ?></td><td><?=e($d['label'])?></td><td><?=e(gmdate('Y-m-d H:i',(int)$d['last_seen']))?></td><td><?= $d['banned']?'已封禁':'正常' ?></td><td><form method="post" class="inline"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$d['id']?>"><input type="hidden" name="action" value="<?=$d['banned']?'unban':'ban'?>"><?php if(!$d['banned']):?><input name="reason" maxlength="120" placeholder="封禁原因"><?php endif;?><button class="<?=$d['banned']?'':'danger'?>"><?=$d['banned']?'解除封禁':'封禁'?></button></form></td></tr><?php endforeach;?></tbody></table></div></section>
<section><h2>激活码管理（最近 200 条）</h2><div class="scroll"><table><thead><tr><th>ID</th><th>备注</th><th>设备数/上限</th><th>到期日（UTC）</th><th>状态</th><th>操作</th></tr></thead><tbody><?php foreach($licenses as $l):?><tr><td>#<?= (int)$l['id'] ?></td><td><?=e($l['label'])?></td><td><?=(int)$l['device_count']?> / <?=(int)$l['max_devices']?></td><td><?= $l['expires_at']?e(gmdate('Y-m-d',(int)$l['expires_at'])):'永久' ?></td><td><?=$l['disabled']?'已停用':'正常'?></td><td><form method="post" class="inline"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$l['id']?>"><input type="hidden" name="action" value="<?=$l['disabled']?'enable':'disable'?>"><button class="<?=$l['disabled']?'':'danger'?>"><?=$l['disabled']?'启用':'停用'?></button></form><form method="post" class="inline"><input type="hidden" name="csrf" value="<?=e($_SESSION['csrf'])?>"><input type="hidden" name="id" value="<?=(int)$l['id']?>"><input type="hidden" name="action" value="delete_license"><label><input type="checkbox" required>确认删除</label><button class="danger">删除卡密</button></form></td></tr><?php endforeach;?></tbody></table></div></section></html>
