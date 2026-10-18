<?php
declare(strict_types=1);
// LUIYo Native Admin App API - JSON endpoints for the iOS admin app
// Uses the same session mechanism as admin.php
session_name('LUIYO_ADMIN');
session_set_cookie_params(['httponly'=>true,'secure'=>true,'samesite'=>'Lax']);
session_start();
header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

if (!extension_loaded('pdo_sqlite')) { http_response_code(503); echo json_encode(['error'=>'PDO SQLite required']); exit; }

$dbPath = getenv('LUIYO_DB_PATH');
$passwordHash = getenv('LUIYO_ADMIN_PASSWORD_HASH');
if (!$passwordHash && is_readable('/www/luiyo-private/admin.hash')) {
    $passwordHash = trim((string)file_get_contents('/www/luiyo-private/admin.hash'));
}
if (!$dbPath || !is_file($dbPath)) { http_response_code(503); echo json_encode(['error'=>'Database unavailable']); exit; }
if (!$passwordHash) { http_response_code(503); echo json_encode(['error'=>'Password not configured']); exit; }

$db = new PDO('sqlite:'.$dbPath, null, null, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$db->exec('PRAGMA busy_timeout=5000');
require_once __DIR__.'/device-service.php';
luiyo_device_schema($db);
require_once __DIR__.'/device-grants.php';
luiyo_grant_schema($db);

// Ensure code_plain column exists
try {
    $cols = $db->query("PRAGMA table_info(licenses)")->fetchAll(PDO::FETCH_ASSOC);
    $hasPlain = false;
    foreach ($cols as $c) { if (($c['name']??'')==='code_plain') { $hasPlain=true; break; } }
    if (!$hasPlain) $db->exec("ALTER TABLE licenses ADD COLUMN code_plain TEXT NOT NULL DEFAULT ''");
} catch (Throwable $e) {}

$action = (string)($_POST['action'] ?? $_GET['action'] ?? '');

// Login - no auth required
if ($action === 'login') {
    $pwd = (string)($_POST['password'] ?? '');
    if (password_verify($pwd, $passwordHash)) {
        session_regenerate_id(true);
        $_SESSION['authorized'] = true;
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
        echo json_encode(['ok'=>true, 'csrf'=>$_SESSION['csrf']]);
    } else {
        sleep(1);
        http_response_code(401);
        echo json_encode(['ok'=>false, 'error'=>'密码不正确']);
    }
    exit;
}

// All other actions require auth
if (empty($_SESSION['authorized'])) {
    http_response_code(401);
    echo json_encode(['ok'=>false, 'error'=>'未登录']);
    exit;
}

function api_out($data, $code=200) {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

switch ($action) {
    case 'devices': {
        // simplified snapshot for admin app
        $q = $db->query("SELECT i.id, i.device_hash, i.model, i.os_version, i.app_version, i.created_at,
            d.banned, d.ban_reason, d.last_seen,
            (SELECT COUNT(*) FROM device_grants g WHERE g.installation_id=i.id AND g.revoked_at IS NULL) AS active_grant
            FROM installations i
            LEFT JOIN devices d ON d.device_hash=i.device_hash
            ORDER BY i.id DESC LIMIT 200");
        $rows = $q->fetchAll(PDO::FETCH_ASSOC);
        $snap = [];
        $online = 0; $banned = 0;
        foreach ($rows as $r) {
            $code = 'D-'.str_pad((string)$r['id'], 6, '0', STR_PAD_LEFT);
            $status = $r['banned'] ? '已封禁' : (($r['active_grant']??0)>0 ? '已授权' : '未授权');
            if (($r['status']??'')==='已封禁') $banned++;
            $isOnline = $r['last_seen'] && (time()-(int)$r['last_seen'] < 120);
            if ($isOnline) $online++;
            $snap[] = [
                'id'=>(int)$r['id'],
                'device_code'=>$code,
                'status'=>$status,
                'online'=>$isOnline,
                'model'=>$r['model']??'',
                'os_version'=>$r['os_version']??'',
                'app_version'=>$r['app_version']??'',
                'last_seen'=>(int)($r['last_seen']??0),
                'active_grant'=>(int)($r['active_grant']??0),
                'auth_via'=>($r['active_grant']??0)>0 ? '设备码' : '卡密',
                'banned'=>(bool)$r['banned'],
            ];
        }
        api_out(['ok'=>true,'devices'=>$snap,'stats'=>['online'=>$online,'banned'=>$banned]]);
    }

    case 'device_action': {
        $id = (int)($_POST['id']??0);
        $code = strtoupper(trim((string)($_POST['device_code']??'')));
        $op = (string)($_POST['op']??'');
        $reason = mb_substr(trim((string)($_POST['reason']??'')), 0, 200);
        // Support device_code like D-000001
        if (!$id && preg_match('/^D-([0-9]{6,9})$/', $code, $m)) {
            $id = (int)$m[1];
        }
        if (!$id) api_out(['ok'=>false,'error'=>'无效ID或设备码'], 400);
        // Find device_hash by installation id
        $q = $db->prepare("SELECT device_hash FROM installations WHERE id=?");
        $q->execute([$id]);
        $dh = $q->fetchColumn();
        if (!$dh) api_out(['ok'=>false,'error'=>'设备不存在'], 404);

        if ($op==='ban') {
            $db->prepare("UPDATE devices SET banned=1, ban_reason=? WHERE device_hash=?")->execute([$reason, $dh]);
        } elseif ($op==='unban') {
            $db->prepare("UPDATE devices SET banned=0, ban_reason='' WHERE device_hash=?")->execute([$dh]);
        } elseif ($op==='grant') {
            // Use proper grant (卡密+设备码)
            require_once __DIR__.'/device-grants.php';
            $problem = luiyo_grant_device($db, $code ?: ('D-'.str_pad((string)$id, 6, '0', STR_PAD_LEFT)));
            if ($problem) api_out(['ok'=>false,'error'=>$problem], 400);
        } elseif ($op==='revoke') {
            // 仅撤销设备码授权，不禁用设备
            require_once __DIR__.'/device-grants.php';
            $problem = luiyo_revoke_grant($db, $code ?: ('D-'.str_pad((string)$id, 6, '0', STR_PAD_LEFT)));
            if ($problem) api_out(['ok'=>false,'error'=>$problem], 400);
        } else {
            api_out(['ok'=>false,'error'=>'无效操作'], 400);
        }
        api_out(['ok'=>true]);
    }

    case 'versions': {
        $q = $db->query("SELECT version, blocked, message, note, created_at, updated_at FROM app_versions ORDER BY version DESC");
        $rows = $q->fetchAll(PDO::FETCH_ASSOC);
        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'version'=>$r['version'],
                'blocked'=>(bool)$r['blocked'],
                'message'=>$r['message'],
                'note'=>$r['note'],
            ];
        }
        api_out(['ok'=>true, 'versions'=>$out]);
    }

    case 'version_action': {
        $op = (string)($_POST['op']??'');
        $t = time();
        if ($op==='add' || $op==='block') {
            $ver = trim((string)($_POST['version']??''));
            $note = mb_substr(trim((string)($_POST['reason']??'')), 0, 200);
            $msg = mb_substr(trim((string)($_POST['message']??'请下载正版使用')), 0, 200);
            if (!$ver) api_out(['ok'=>false,'error'=>'版本号不能为空'], 400);
            $blocked = $op==='block' ? 1 : 0;
            $db->prepare("INSERT OR REPLACE INTO app_versions(version, blocked, message, note, created_at, updated_at) VALUES(?,?,?,?,?,?)")
               ->execute([$ver, $blocked, $msg, $note, $t, $t]);
        } elseif ($op==='unblock') {
            $ver = trim((string)($_POST['version']??''));
            $db->prepare("UPDATE app_versions SET blocked=0, updated_at=? WHERE version=?")->execute([$t, $ver]);
        } elseif ($op==='delete') {
            $ver = trim((string)($_POST['version']??''));
            $db->prepare("DELETE FROM app_versions WHERE version=?")->execute([$ver]);
        } else {
            api_out(['ok'=>false,'error'=>'无效操作'], 400);
        }
        api_out(['ok'=>true]);
    }

    default:
        api_out(['ok'=>false,'error'=>'未知操作'], 400);
}
