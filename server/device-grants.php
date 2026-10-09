<?php
declare(strict_types=1);

function luiyo_grant_schema(PDO $db): void {
    $db->exec('CREATE TABLE IF NOT EXISTS device_grants (installation_id INTEGER PRIMARY KEY, license_id INTEGER NOT NULL, granted_at INTEGER NOT NULL, revoked_at INTEGER)');
}

function luiyo_grant_device(PDO $db,string $code): ?string {
    if(!preg_match('/^D-([0-9]{6,9})$/D',strtoupper(trim($code)),$m))return '请输入完整设备码，例如 D-000001';
    $db->exec('BEGIN IMMEDIATE');
    try {
        $q=$db->prepare('SELECT * FROM installations WHERE id=?');$q->execute([(int)$m[1]]);$i=$q->fetch(PDO::FETCH_ASSOC);
        if(!$i){$db->exec('ROLLBACK');return '未找到该设备，请先打开新版 App 联网登记';}
        $q=$db->prepare('SELECT d.*,g.license_id AS grant_license FROM devices d LEFT JOIN device_grants g ON g.installation_id=? WHERE d.device_hash=?');$q->execute([$i['id'],$i['device_hash']]);$d=$q->fetch(PDO::FETCH_ASSOC);
        if($d){
            if($d['banned']){$db->exec('ROLLBACK');return '设备已封禁，请先解除封禁';}
            if((int)($d['grant_license']??0)!==(int)$d['license_id']){$db->exec('ROLLBACK');return '设备已有卡密授权，保留原授权';}
            $license=(int)$d['license_id'];
            $db->prepare('UPDATE licenses SET disabled=0 WHERE id=?')->execute([$license]);
        }else{
            $db->prepare('INSERT INTO licenses(code_hash,label,max_devices,created_at) VALUES(?,?,1,?)')->execute([hash('sha256',random_bytes(32)),'SVIP 3',time()]);
            $license=(int)$db->lastInsertId();
            $db->prepare('INSERT INTO devices(license_id,device_hash,token_hash,created_at,last_seen) VALUES(?,?,?,?,?)')->execute([$license,$i['device_hash'],hash('sha256',random_bytes(32)),time(),time()]);
        }
        $db->prepare('INSERT INTO device_grants VALUES(?,?,?,NULL) ON CONFLICT(installation_id) DO UPDATE SET license_id=excluded.license_id,granted_at=excluded.granted_at,revoked_at=NULL')->execute([$i['id'],$license,time()]);
        $db->exec('COMMIT');return null;
    }catch(Throwable $e){try{$db->exec('ROLLBACK');}catch(Throwable){}throw $e;}
}

function luiyo_revoke_grant(PDO $db,string $code): ?string {
    if(!preg_match('/^D-([0-9]{6,9})$/D',strtoupper(trim($code)),$m))return '设备码格式错误';
    $db->exec('BEGIN IMMEDIATE');
    try {
        $q=$db->prepare('SELECT * FROM device_grants WHERE installation_id=? AND revoked_at IS NULL');$q->execute([(int)$m[1]]);$g=$q->fetch(PDO::FETCH_ASSOC);
        if(!$g){$db->exec('ROLLBACK');return '该设备没有可撤销的设备码授权';}
        $db->prepare('UPDATE licenses SET disabled=1 WHERE id=?')->execute([$g['license_id']]);
        $db->prepare('UPDATE device_grants SET revoked_at=? WHERE installation_id=?')->execute([time(),$m[1]]);
        $db->exec('COMMIT');return null;
    }catch(Throwable $e){try{$db->exec('ROLLBACK');}catch(Throwable){}throw $e;}
}

function luiyo_claim_grant(PDO $db): never {
    $i=luiyo_installation($db);
    $db->exec('BEGIN IMMEDIATE');
    try {
        $q=$db->prepare('SELECT d.id,d.banned,l.disabled,l.expires_at FROM device_grants g JOIN installations i ON i.id=g.installation_id JOIN devices d ON d.device_hash=i.device_hash AND d.license_id=g.license_id JOIN licenses l ON l.id=g.license_id WHERE g.installation_id=? AND g.revoked_at IS NULL');
        $q->execute([$i['id']]);$d=$q->fetch(PDO::FETCH_ASSOC);
        if(!$d){$db->exec('ROLLBACK');luiyo_json(404,['error'=>'no_device_grant']);}
        if($d['banned']||$d['disabled']||($d['expires_at']!==null&&(int)$d['expires_at']<time())){$db->exec('ROLLBACK');luiyo_json(403,['error'=>'access_revoked']);}
        $token=bin2hex(random_bytes(32));
        $db->prepare('UPDATE devices SET token_hash=?,last_seen=? WHERE id=?')->execute([hash('sha256',$token),time(),$d['id']]);
        $db->exec('COMMIT');luiyo_json(200,['token'=>$token,'status'=>'active']);
    }catch(Throwable $e){try{$db->exec('ROLLBACK');}catch(Throwable){}throw $e;}
}
