<?php
declare(strict_types=1);
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
require_once __DIR__.'/device-service.php';
luiyo_device_schema($db);
