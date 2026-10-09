<?php
declare(strict_types=1);
require_once __DIR__.'/bootstrap.php';
require_once __DIR__.'/udid-verifier.php';
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
function profile_page(string $title,string $message,int $code=200,?string $download=null): never {
    http_response_code($code);header('Content-Type: text/html; charset=utf-8');
    $escape=static fn(string $s)=>htmlspecialchars($s,ENT_QUOTES|ENT_SUBSTITUTE,'UTF-8');
    echo '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LUIYo 设备信息</title><style>body{font:16px system-ui;background:#f6f7fa;color:#1c2330;max-width:540px;margin:12vh auto;padding:24px;line-height:1.7}main{background:white;padding:25px;border-radius:24px}a{display:block;border-radius:14px;padding:12px;background:#4869eb;color:white;text-decoration:none;text-align:center}small{color:#7a8392}</style><main><h2>'.$escape($title).'</h2><p>'.$escape($message).'</p>';
    if($download)echo '<a href="'.$escape($download).'">下载设备识别描述文件</a><p><small>随后打开系统设置，进入“已下载描述文件”并确认安装。完成后返回 LUIYo 查看状态；此操作不激活卡密。</small></p>';
    echo '</main></html>';exit;
}
$action=(string)($_GET['action']??'welcome');
if($action==='done')profile_page('设备信息已获取','请返回 LUIYo。设备 UDID 会显示在设置页；后台也能查看。此步骤没有更改卡密授权状态。');
$ticket=(string)($_GET['ticket']??'');
if(!preg_match('/^[a-f0-9]{64}$/D',$ticket))profile_page('链接无效','请返回 LUIYo，重新点击“获取设备 UDID”。',400);
$q=$db->prepare('SELECT * FROM udid_challenges WHERE ticket_hash=?');$q->execute([hash('sha256',$ticket)]);$challenge=$q->fetch(PDO::FETCH_ASSOC);
if(!$challenge || $challenge['used_at']!==null || (int)$challenge['expires_at']<time())profile_page('链接已失效','链接有效期为 10 分钟，且只能使用一次。请返回 LUIYo 重新获取。',410);
$base=luiyo_public_base();if(!$base)profile_page('服务尚未配置','管理员需要配置设备识别服务地址。',503);
if($action==='welcome' && ($_SERVER['REQUEST_METHOD']??'GET')==='GET')profile_page('获取设备 UDID','此可选操作会把当前设备的 UDID 发送到 LUIYo 管理后台。只用于设备识别；不会安装管理权限、VPN 或根证书，也不会读取照片和通讯录。',200,'profile.php?action=download&ticket='.$ticket);
if($action==='download' && ($_SERVER['REQUEST_METHOD']??'GET')==='GET') {
    $escape=static fn(string $s)=>htmlspecialchars($s,ENT_XML1|ENT_QUOTES,'UTF-8');
    header('Content-Type: application/x-apple-aspen-config');header('Content-Disposition: attachment; filename="LUIYo-Device.mobileconfig"');
    $uuid=bin2hex(random_bytes(16));$uuid=substr($uuid,0,8).'-'.substr($uuid,8,4).'-'.substr($uuid,12,4).'-'.substr($uuid,16,4).'-'.substr($uuid,20);
    echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>PayloadType</key><string>Profile Service</string><key>PayloadVersion</key><integer>1</integer><key>PayloadIdentifier</key><string>com.luiyo.device-identification</string><key>PayloadUUID</key><string>'.$uuid.'</string><key>PayloadDisplayName</key><string>LUIYo 设备识别</string><key>PayloadDescription</key><string>仅获取设备 UDID，不包含设备管理、VPN 或证书安装。</string><key>PayloadOrganization</key><string>LUIYo</string><key>PayloadContent</key><dict><key>URL</key><string>'.$escape($base.'/profile.php?action=callback&ticket='.$ticket).'</string><key>DeviceAttributes</key><array><string>UDID</string></array><key>Challenge</key><string>'.$ticket.'</string></dict></dict></plist>';exit;
}
if($action==='callback' && ($_SERVER['REQUEST_METHOD']??'GET')==='POST') {
    try {
        $raw=file_get_contents('php://input',false,null,0,65537);$payload=luiyo_verify_device_payload($raw);
        if(!hash_equals($ticket,$payload['challenge']))throw new RuntimeException('challenge_mismatch');
        $db->exec('BEGIN IMMEDIATE');
        $q=$db->prepare('UPDATE udid_challenges SET used_at=? WHERE ticket_hash=? AND used_at IS NULL AND expires_at>=?');$q->execute([time(),hash('sha256',$ticket),time()]);
        if($q->rowCount()!==1)throw new RuntimeException('challenge_expired');
        $q=$db->prepare('SELECT udid FROM installations WHERE id=?');$q->execute([$challenge['installation_id']]);$previous=$q->fetchColumn();
        if($previous && !hash_equals($previous,$payload['udid']))throw new RuntimeException('device_mismatch');
        $db->prepare('UPDATE installations SET udid=?,udid_verified_at=? WHERE id=?')->execute([$payload['udid'],time(),$challenge['installation_id']]);
        $db->exec('COMMIT');
        header('Location: '.$base.'/profile.php?action=done',true,303);exit;
    }catch(Throwable $e){try{$db->exec('ROLLBACK');}catch(Throwable){}profile_page('设备信息未通过验证','请返回 LUIYo 重新获取；若仍失败，请联系管理员检查设备证书兼容性。',400);}
}
profile_page('请求不支持','请从 LUIYo 设置页发起获取。',405);
