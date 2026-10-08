<?php
declare(strict_types=1);

/**
 * LUIYo activation service. Requires PHP 8.3 + PDO SQLite + HTTPS.
 * Configure LUIYO_ADMIN_PASSWORD_HASH (password_hash output) outside webroot.
 * Data directory MUST be outside document root; see README.
 */
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');
header('Referrer-Policy: no-referrer');
if (!extension_loaded('pdo_sqlite')) { http_response_code(503); exit('SQLite extension unavailable'); }
$dbPath = getenv('LUIYO_DB_PATH');
if (!$dbPath || !str_starts_with($dbPath, '/') || !is_dir(dirname($dbPath))) {
    http_response_code(503); exit('Server not configured: LUIYO_DB_PATH'); 
}
if (empty($_SERVER['HTTPS']) || $_SERVER['HTTPS'] === 'off') {
    if (getenv('LUIYO_TRUST_PROXY_HTTPS') !== '1' || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') !== 'https') {
        http_response_code(403); exit('HTTPS required');
    }
}
$db = new PDO('sqlite:' . $dbPath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$db->exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;');
$db->exec('CREATE TABLE IF NOT EXISTS licenses (
 id INTEGER PRIMARY KEY AUTOINCREMENT, code_hash TEXT NOT NULL UNIQUE,
 label TEXT NOT NULL DEFAULT \'\', max_devices INTEGER NOT NULL DEFAULT 1,
 expires_at INTEGER, disabled INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
$db->exec('CREATE TABLE IF NOT EXISTS devices (
 id INTEGER PRIMARY KEY AUTOINCREMENT, license_id INTEGER NOT NULL,
 device_hash TEXT NOT NULL UNIQUE, token_hash TEXT NOT NULL UNIQUE,
 created_at INTEGER NOT NULL, last_seen INTEGER NOT NULL,
 banned INTEGER NOT NULL DEFAULT 0, ban_reason TEXT NOT NULL DEFAULT \'\',
 FOREIGN KEY(license_id) REFERENCES licenses(id))');
$db->exec('CREATE TABLE IF NOT EXISTS events (
 device_id INTEGER NOT NULL, day TEXT NOT NULL, last_seen INTEGER NOT NULL,
 PRIMARY KEY(device_id,day))');
$db->exec('CREATE TABLE IF NOT EXISTS attempts (ip_hash TEXT PRIMARY KEY, window_start INTEGER NOT NULL, failures INTEGER NOT NULL)');
$db->exec('CREATE INDEX IF NOT EXISTS idx_devices_license ON devices(license_id)');
$db->exec('CREATE INDEX IF NOT EXISTS idx_events_day ON events(day)');
function response(int $status, array $data): never {
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
function body(): array {
    if ((int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 4096) response(413, ['error'=>'request_too_large']);
    $j = json_decode(file_get_contents('php://input'), true);
    if (!is_array($j)) response(400, ['error'=>'invalid_json']);
    return $j;
}
function hashSecret(string $s): string { return hash('sha256', $s); }
function recordDeviceActivity(PDO $db, int $id): void {
    $now=time();
    $db->prepare('UPDATE devices SET last_seen=? WHERE id=?')->execute([$now,$id]);
    $db->prepare('INSERT INTO events(device_id,day,last_seen) VALUES(?,?,?) ON CONFLICT(device_id,day) DO UPDATE SET last_seen=excluded.last_seen')
       ->execute([$id,gmdate('Y-m-d'),$now]);
}
function authenticate(PDO $db): array {
    $auth=$_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/^Bearer ([a-f0-9]{64})$/D',$auth,$m)) response(401,['error'=>'auth_required']);
    $q=$db->prepare('SELECT d.*,l.disabled AS license_disabled,l.expires_at FROM devices d JOIN licenses l ON l.id=d.license_id WHERE d.token_hash=?');
    $q->execute([hashSecret($m[1])]); $d=$q->fetch(PDO::FETCH_ASSOC);
    if (!$d) response(401,['error'=>'invalid_token']);
    if ($d['banned'] || $d['license_disabled']) response(403,['error'=>'access_revoked']);
    if ($d['expires_at'] !== null && (int)$d['expires_at'] < time()) response(403,['error'=>'expired']);
    return $d;
}
$route = trim(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?? '/', '/');
$script = trim($_SERVER['SCRIPT_NAME'] ?? '', '/');
if (str_ends_with($route, basename($script))) $route='';
$route = preg_replace('~^.*?/api\.php/?~', '', $route);
$method=$_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method==='POST' && ($route==='activate' || ($_GET['action'] ?? '')==='activate')) {
    $v=body(); $code=strtoupper(trim((string)($v['code']??'')));
    $device=trim((string)($v['device_id']??''));
    if (!preg_match('/^LUI-[A-Z2-9]{5}(?:-[A-Z2-9]{5}){3}$/D',$code) ||
        !preg_match('/^[a-f0-9-]{36}$/Di',$device)) response(400,['error'=>'invalid_input']);
    $iphash=hashSecret((string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    $q=$db->prepare('SELECT * FROM attempts WHERE ip_hash=?');$q->execute([$iphash]);$a=$q->fetch(PDO::FETCH_ASSOC);
    if ($a && time()-(int)$a['window_start']<3600 && (int)$a['failures']>=12) response(429,['error'=>'try_later']);
    $q=$db->prepare('SELECT * FROM licenses WHERE code_hash=?');$q->execute([hashSecret($code)]);$l=$q->fetch(PDO::FETCH_ASSOC);
    if (!$l || $l['disabled'] || ($l['expires_at']!==null && (int)$l['expires_at']<time())) {
        $db->prepare('INSERT INTO attempts(ip_hash,window_start,failures) VALUES(?,?,1) ON CONFLICT(ip_hash) DO UPDATE SET failures=CASE WHEN ?-window_start>=3600 THEN 1 ELSE failures+1 END,window_start=CASE WHEN ?-window_start>=3600 THEN ? ELSE window_start END')->execute([$iphash,time(),time(),time(),time()]);
        response(403,['error'=>'invalid_or_disabled_code']);
    }
    $deviceHash=hashSecret($device);
    $db->beginTransaction();
    try {
        $q=$db->prepare('SELECT * FROM devices WHERE device_hash=?');$q->execute([$deviceHash]);$d=$q->fetch(PDO::FETCH_ASSOC);
        if ($d) {
            if ((int)$d['license_id'] !== (int)$l['id']) response(409,['error'=>'device_already_registered']);
            if ($d['banned']) response(403,['error'=>'access_revoked']);
        } else {
            $q=$db->prepare('SELECT COUNT(*) FROM devices WHERE license_id=?');$q->execute([$l['id']]);
            if ((int)$q->fetchColumn()>=(int)$l['max_devices']) response(403,['error'=>'device_limit']);
        }
        $token=bin2hex(random_bytes(32));
        if ($d) $db->prepare('UPDATE devices SET token_hash=?,last_seen=? WHERE id=?')->execute([hashSecret($token),time(),$d['id']]);
        else {
            $db->prepare('INSERT INTO devices(license_id,device_hash,token_hash,created_at,last_seen) VALUES(?,?,?,?,?)')
               ->execute([$l['id'],$deviceHash,hashSecret($token),time(),time()]);
            $d=['id'=>(int)$db->lastInsertId()];
        }
        recordDeviceActivity($db,(int)$d['id']);$db->commit();
        response(200,['token'=>$token,'status'=>'active']);
    } catch(Throwable $e) {if($db->inTransaction())$db->rollBack();throw $e;}
}
if ($method==='POST' && ($route==='check' || ($_GET['action']??'')==='check')) {
    $d=authenticate($db);recordDeviceActivity($db,(int)$d['id']);
    response(200,['status'=>'active']);
}
response(404,['error'=>'not_found']);
