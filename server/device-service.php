<?php
declare(strict_types=1);

// Additive migration only. Legacy devices, licenses, tokens and events stay intact.
function luiyo_device_schema(PDO $db): void {
    $db->exec("CREATE TABLE IF NOT EXISTS installations (
      id INTEGER PRIMARY KEY AUTOINCREMENT, device_hash TEXT NOT NULL UNIQUE,
      credential_hash TEXT NOT NULL, created_at INTEGER NOT NULL, last_seen INTEGER NOT NULL,
      foreground INTEGER NOT NULL DEFAULT 1, page TEXT NOT NULL DEFAULT 'home',
      model TEXT NOT NULL DEFAULT '', os_version TEXT NOT NULL DEFAULT '', app_version TEXT NOT NULL DEFAULT '',
      udid TEXT, udid_verified_at INTEGER, signing_udid TEXT)");
    $columns=$db->query('PRAGMA table_info(installations)')->fetchAll(PDO::FETCH_COLUMN,1);
    if(!in_array('signing_udid',$columns,true))$db->exec('ALTER TABLE installations ADD COLUMN signing_udid TEXT');
    $db->exec('CREATE INDEX IF NOT EXISTS installations_seen ON installations(last_seen)');
    // A device remains on record but disappears from the admin list until its
    // installation sends a fresh authenticated presence event.
    $db->exec('CREATE TABLE IF NOT EXISTS installations_hidden (installation_id INTEGER PRIMARY KEY, hidden_at INTEGER NOT NULL)');
    $db->exec('CREATE TABLE IF NOT EXISTS registration_limits (ip_hash TEXT PRIMARY KEY, started_at INTEGER NOT NULL, count INTEGER NOT NULL)');
}
function luiyo_json(int $code, array $data): never {
    http_response_code($code);header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);exit;
}
function luiyo_input(): array {
    $raw=file_get_contents('php://input',false,null,0,8193);
    if(strlen($raw)>8192)luiyo_json(413,['error'=>'request_too_large']);
    $v=json_decode($raw,true);if(!is_array($v))luiyo_json(400,['error'=>'invalid_json']);return $v;
}
function luiyo_installation(PDO $db): array {
    if(!preg_match('/^Bearer ([a-f0-9]{64})$/D',$_SERVER['HTTP_AUTHORIZATION']??'',$m))luiyo_json(401,['error'=>'registration_required']);
    $q=$db->prepare('SELECT * FROM installations WHERE credential_hash=?');$q->execute([hash('sha256',$m[1])]);
    $d=$q->fetch(PDO::FETCH_ASSOC);if(!$d)luiyo_json(401,['error'=>'invalid_registration']);return $d;
}
function luiyo_presence(PDO $db, int $id, array $v): void {
    $page=in_array($v['page']??'', ['home','rules','settings'],true)?$v['page']:'home';
    $clean=static fn(string $key,int $limit): string=>mb_substr(preg_replace('/[\x00-\x1f\x7f]/u','',(string)($v[$key]??''))??'',0,$limit);
    $provided=is_string($v['signing_udid']??null)?strtoupper($v['signing_udid']):'';
    $provided=preg_match('/^(?:[A-F0-9]{40}|[A-F0-9]{8}-[A-F0-9]{16})$/D',$provided)?$provided:null;
    $db->prepare('UPDATE installations SET last_seen=?,foreground=?,page=?,model=?,os_version=?,app_version=?,signing_udid=? WHERE id=?')
      ->execute([time(),($v['foreground']??'yes')==='no'?0:1,$page,$clean('model',40),$clean('os_version',24),$clean('app_version',40),$provided,$id]);
}
function luiyo_device_routes(PDO $db,string $action,string $method): void {
    if(in_array($action,['udid-start','device-status'],true))luiyo_json(410,['error'=>'udid_mode_removed']);
    if(!in_array($action,['register','heartbeat'],true))return;
    if($method!=='POST')luiyo_json(405,['error'=>'post_required']);
    if($action==='register') {
        $v=luiyo_input();$device=strtolower((string)($v['device_id']??''));$secret=(string)($v['registration_secret']??'');
        if(!preg_match('/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/D',$device)||!preg_match('/^[a-f0-9]{64}$/D',$secret))luiyo_json(400,['error'=>'invalid_input']);
        $db->exec('BEGIN IMMEDIATE');
        try {
            $q=$db->prepare('SELECT * FROM installations WHERE device_hash=?');$q->execute([hash('sha256',$device)]);$d=$q->fetch(PDO::FETCH_ASSOC);
            if($d && !hash_equals($d['credential_hash'],hash('sha256',$secret))) { $db->exec('ROLLBACK');luiyo_json(409,['error'=>'registration_conflict']); }
            if(!$d) {
                $ip=hash('sha256',$_SERVER['REMOTE_ADDR']??'unknown');$q=$db->prepare('SELECT * FROM registration_limits WHERE ip_hash=?');$q->execute([$ip]);$rate=$q->fetch(PDO::FETCH_ASSOC);
                if($rate && time()-(int)$rate['started_at']<3600 && (int)$rate['count']>=50){$db->exec('ROLLBACK');luiyo_json(429,['error'=>'try_later']);}
                $db->prepare('INSERT INTO registration_limits VALUES(?,?,1) ON CONFLICT(ip_hash) DO UPDATE SET count=CASE WHEN ?-started_at>=3600 THEN 1 ELSE count+1 END,started_at=CASE WHEN ?-started_at>=3600 THEN ? ELSE started_at END')->execute([$ip,time(),time(),time(),time()]);
                $db->prepare('INSERT INTO installations(device_hash,credential_hash,created_at,last_seen) VALUES(?,?,?,?)')->execute([hash('sha256',$device),hash('sha256',$secret),time(),time()]);
                $d=['id'=>(int)$db->lastInsertId()];
            }
            luiyo_presence($db,(int)$d['id'],$v);$db->exec('COMMIT');
            luiyo_json(200,['status'=>'registered','device_code'=>'D-'.str_pad((string)$d['id'],6,'0',STR_PAD_LEFT)]);
        }catch(Throwable $e){try{$db->exec('ROLLBACK');}catch(Throwable){}throw $e;}
    }
    $d=luiyo_installation($db);
    if($action==='heartbeat') {
        luiyo_presence($db,(int)$d['id'],luiyo_input());luiyo_json(200,['status'=>'recorded']);
    }
}
function luiyo_admin_snapshot(PDO $db): array {
    $now=time();$rows=$db->query('SELECT i.id,i.created_at,i.last_seen,i.foreground,i.page,i.model,i.os_version,i.app_version,i.udid,i.udid_verified_at,i.signing_udid,
      d.id AS license_device_id,d.banned,l.id AS license_id,l.label,l.disabled,l.expires_at
      FROM installations i LEFT JOIN devices d ON d.device_hash=i.device_hash LEFT JOIN licenses l ON l.id=d.license_id
      LEFT JOIN installations_hidden h ON h.installation_id=i.id
      WHERE h.installation_id IS NULL OR i.last_seen > h.hidden_at
      ORDER BY i.last_seen DESC')->fetchAll(PDO::FETCH_ASSOC);
    foreach($rows as &$r){
        $r['online']=(bool)$r['foreground'] && $now-(int)$r['last_seen']<=90;
        $r['status']=!$r['license_id']?'未授权':($r['banned']?'已封禁':($r['disabled']?'已停用':($r['expires_at']!==null&&(int)$r['expires_at']<$now?'已过期':'已授权')));
        $r['device_code']='D-'.str_pad((string)$r['id'],6,'0',STR_PAD_LEFT);
    }unset($r);

    // Presentation-only grouping for repeated UNLICENSED installations. A signing UDID
    // comes from the app and is NOT a verified Apple identifier, so it must never
    // establish authorization, transfer a license, or merge database records.
    // Only group identical, well-formed signing IDs with the same hardware model.
    // Verified UDIDs and any licensed/banned installation remain separate.
    $visible=[];
    $groupIndex=[];
    foreach($rows as $r) {
        $signing=strtoupper(trim((string)($r['signing_udid']??'')));
        $model=trim((string)($r['model']??''));
        $candidate=($r['status']==='未授权' && !$r['udid_verified_at'] && $model!==''
            && preg_match('/^(?:[A-F0-9]{40}|[A-F0-9]{8}-[A-F0-9]{16})$/D',$signing));
        $key=$candidate ? $model.'|'.$signing : null;
        if($key!==null && isset($groupIndex[$key])) {
            $idx=$groupIndex[$key];
            $visible[$idx]['installation_codes'][]=$r['device_code'];
            $visible[$idx]['installation_count']++;
            $visible[$idx]['online']=$visible[$idx]['online'] || $r['online'];
            continue;
        }
        $r['installation_codes']=[$r['device_code']];
        $r['installation_count']=1;
        $r['group_unverified_signing_udid']=($key!==null);
        if($key!==null)$groupIndex[$key]=count($visible);
        $visible[]=$r;
    }
    foreach($visible as &$r){unset($r['udid'],$r['udid_verified_at'],$r['signing_udid'],$r['group_unverified_signing_udid']);}unset($r);
    $total=count($visible);
    $online=count(array_filter($visible,static fn(array $r):bool=>(bool)$r['online']));
    $unlicensed=count(array_filter($visible,static fn(array $r):bool=>$r['status']==='未授权'));
    return ['devices'=>$visible,'total'=>$total,'online'=>$online,'unlicensed'=>$unlicensed,
        'installation_total'=>count($rows),'server_time'=>$now];
}
