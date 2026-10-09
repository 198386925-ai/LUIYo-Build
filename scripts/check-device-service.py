#!/usr/bin/env python3
"""HTTP regression for additive migration, registration, licensing and UDID replay.
Uses an isolated DB and a disposable test CA. Never connects to a real backend.
"""
import hashlib
import http.client
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.parse
import uuid

root = Path(__file__).resolve().parents[1]
php = shlex.split(os.environ.get('LUIYO_TEST_PHP', 'php'))
with tempfile.TemporaryDirectory(prefix='luiyo-service-test-') as tmp:
    work = Path(tmp)
    shutil.copytree(root / 'server', work / 'server')
    router = work / 'router.php'
    router.write_text("<?php $_SERVER['HTTPS']='on'; return false;\n")
    db_path = work / 'private.sqlite'
    password_hash = subprocess.check_output(php + ['-r', "echo password_hash('test-only-password',PASSWORD_DEFAULT);"], text=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = dict(os.environ, LUIYO_DB_PATH=str(db_path), LUIYO_ADMIN_PASSWORD_HASH=password_hash,
               LUIYO_PUBLIC_BASE_URL='https://devices.example.test/luiyo')
    server_log = open(work / 'http.log', 'w')
    process = subprocess.Popen(php + ['-d', 'session.save_path=' + str(work), '-S', f'127.0.0.1:{port}', '-t', str(work / 'server'), str(router)], env=env, stdout=server_log, stderr=server_log)

    def request(path, payload=None, token=None, method='POST', raw=None, cookie=None, form=None):
        headers = {}
        if token: headers['Authorization'] = 'Bearer ' + token
        if cookie: headers['Cookie'] = cookie
        if payload is not None:
            raw = json.dumps(payload).encode(); headers['content-type'] = 'application/json'
        if form is not None:
            raw = urllib.parse.urlencode(form).encode(); headers['content-type'] = 'application/x-www-form-urlencoded'
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
        connection.request(method, path, body=raw, headers=headers)
        response = connection.getresponse(); data = response.read(); hdr = {key.lower(): value for key, value in response.getheaders()}; code = response.status
        connection.close()
        decoded = json.loads(data) if hdr.get('content-type', '').startswith('application/json') else data
        return code, decoded, hdr

    def api(action, payload=None, token=None): return request('/api.php?action=' + action, payload, token)

    try:
        for _ in range(100):
            try: request('/api.php', method='GET'); break
            except OSError: time.sleep(.03)
        else: raise AssertionError('PHP test server failed to start')
        db = sqlite3.connect(db_path)
        code = 'LUI-ABCDE-FGHJK-LMNPQ-RSTUV'
        legacy_uuid = '11111111-2222-4333-8444-555555555555'
        legacy_token = 'a' * 64
        sha = lambda s: hashlib.sha256(s.encode()).hexdigest()
        now = int(time.time())
        db.execute('INSERT INTO licenses(code_hash,label,max_devices,created_at) VALUES(?,?,?,?)', (sha(code), '历史卡密', 5, now))
        db.execute('INSERT INTO devices(license_id,device_hash,token_hash,created_at,last_seen) VALUES(1,?,?,?,?)', (sha(legacy_uuid), sha(legacy_token), now, now))
        db.commit()
        assert api('check', token=legacy_token)[0] == 200, 'Existing token must survive migration'
        device = str(uuid.uuid4()); secret = 'b' * 64
        registration = {'device_id': device, 'registration_secret': secret, 'page': 'settings', 'model': 'iPhone17,4', 'os_version': '26.2', 'app_version': '1.0.4 (22)'}
        assert api('register', registration)[0] == 200
        assert api('register', registration)[0] == 200
        assert db.execute('SELECT COUNT(*) FROM installations').fetchone()[0] == 1
        assert api('register', dict(registration, registration_secret='c' * 64))[0] == 409
        assert api('heartbeat', {'page': 'settings'}, token='d' * 64)[0] == 401
        assert api('check', token=secret)[0] == 401, 'Presence credential must not activate the app'
        assert api('device-status', token=secret)[1]['udid_status'] == 'not_collected'
        assert db.execute('SELECT COUNT(*) FROM devices').fetchone()[0] == 1, 'Unlicensed registration must not create a license'
        hint='00008130-ABCDEF0123456789'
        assert api('heartbeat', {'signing_udid':hint}, token=secret)[0] == 200
        hinted=api('device-status', token=secret)[1]
        assert hinted['udid_status']=='signing_profile' and hinted['udid']==hint
        assert db.execute('SELECT udid_verified_at FROM installations').fetchone()[0] is None, 'Signing-file hint must never be called verified'
        assert api('heartbeat', {'page': 'rules', 'foreground': 'no'}, token=secret)[0] == 200
        assert db.execute('SELECT foreground,page FROM installations').fetchone() == (0, 'rules')
        assert request('/admin.php?snapshot=1', method='GET')[2]['content-type'].startswith('text/html'), 'Snapshot must require admin login'
        login = request('/admin.php', form={'action': 'login', 'password': 'test-only-password'})
        assert login[0] == 302, (login[0], login[1][:500])
        cookie = login[2]['set-cookie'].split(';')[0]
        snapshot = request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]
        assert snapshot['unlicensed'] == 1 and snapshot['online'] == 0
        assert snapshot['devices'][0]['status'] == '未授权'
        assert api('heartbeat', {'page': 'home'}, token=secret)[0] == 200
        assert request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]['online'] == 1
        db.execute('UPDATE installations SET last_seen=?', (now - 91,)); db.commit()
        assert request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]['online'] == 0
        activate = api('activate', {'device_id': device, 'code': code})
        assert activate[0] == 200
        assert api('check', token=activate[1]['token'])[0] == 200
        snapshot = request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]
        assert snapshot['devices'][0]['status'] == '已授权' and snapshot['unlicensed'] == 0
        db.execute('UPDATE devices SET banned=1 WHERE device_hash=?', (sha(device),)); db.commit()
        assert api('check', token=activate[1]['token'])[0] == 403
        assert api('heartbeat', {'page': 'settings'}, token=secret)[0] == 200
        assert request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]['devices'][0]['status'] == '已封禁'
        assert api('udid-start', token='f' * 64)[0] == 401
        started = api('udid-start', token=secret); assert started[0] == 200
        ticket = urllib.parse.parse_qs(urllib.parse.urlparse(started[1]['profile_url']).query)['ticket'][0]
        downloaded = request('/profile.php?action=download&ticket=' + ticket, method='GET')
        profile = plistlib.loads(downloaded[1]); assert profile['PayloadType'] == 'Profile Service'
        assert profile['PayloadContent']['DeviceAttributes'] == ['UDID']
        assert profile['PayloadContent']['URL'] == 'https://devices.example.test/luiyo/profile.php?action=callback&ticket=' + ticket
        assert request('/profile.php?action=callback&ticket=' + ticket, raw=b'unsigned payload')[0] == 400
        assert api('device-status', token=secret)[1]['udid_status'] == 'not_collected'

        # A self-signed spoof remains rejected with the production trust pin.
        key, cert, content, cms = [work / name for name in ('ca.key', 'ca.pem', 'payload.plist', 'payload.der')]
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=Test Device CA/O=Test Only', '-keyout', str(key), '-out', str(cert), '-days', '1'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        udid = '00008130-0123456789ABCDEF'
        content.write_bytes(plistlib.dumps({'UDID': udid, 'CHALLENGE': ticket}))
        subprocess.run(['openssl', 'cms', '-sign', '-binary', '-nodetach', '-in', str(content), '-signer', str(cert), '-inkey', str(key), '-outform', 'DER', '-out', str(cms)], check=True)
        callback = '/profile.php?action=callback&ticket=' + ticket
        assert request(callback, raw=cms.read_bytes())[0] == 400, 'Self-signed certificate must be rejected'
        assert api('device-status', token=secret)[1]['udid_status'] == 'not_collected'
        # Positive cryptographic/lifecycle test in the temporary server copy only.
        shutil.copyfile(cert, work / 'server/apple-device-ca.pem')
        altered = bytearray(cms.read_bytes()); altered[-1] ^= 1
        assert request(callback, raw=bytes(altered))[0] == 400, 'Tampered CMS must be rejected'
        assert request(callback, raw=cms.read_bytes())[0] == 303
        assert api('device-status', token=secret)[1]['udid'] == udid
        assert request(callback, raw=cms.read_bytes())[0] == 410, 'Completed challenge must not replay'
        started=api('udid-start',token=secret); expired_ticket=urllib.parse.parse_qs(urllib.parse.urlparse(started[1]['profile_url']).query)['ticket'][0]
        db.execute('UPDATE udid_challenges SET expires_at=? WHERE ticket_hash=?',(now-1,sha(expired_ticket)));db.commit()
        assert request('/profile.php?action=download&ticket='+expired_ticket,method='GET')[0]==410, 'Expired challenge must be rejected'
        assert api('check', token=activate[1]['token'])[0] == 403, 'UDID collection must not unban or activate'
        assert api('check', token=legacy_token)[0] == 200
        assert db.execute('SELECT code_hash,label FROM licenses').fetchone() == (sha(code), '历史卡密')
        print('Passed: existing tokens/data, unlicensed registration, credential separation, online/offline, admin session, activation/revocation, profile URL, unsigned/self-signed/tampered rejection, signed callback and replay protection.')
    finally:
        process.terminate(); process.wait(timeout=5); server_log.close()
