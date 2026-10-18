#!/usr/bin/env python3
"""HTTP regression for additive migration, registration, card-key licensing without UDID.
Uses an isolated DB. Never connects to a real backend.
"""
import re
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
        assert db.execute('SELECT COUNT(*) FROM devices').fetchone()[0] == 1
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
        # No registration or UDID is required for card-key activation.
        fresh = str(uuid.uuid4())
        activated = api('activate', {'device_id': fresh, 'code': code})
        assert activated[0] == 200, activated
        assert api('check', token=activated[1]['token'])[0] == 200
        activate = api('activate', {'device_id': device, 'code': code})
        assert activate[0] == 200, activate
        assert api('check', token=activate[1]['token'])[0] == 200
        snapshot = request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]
        assert snapshot['devices'][0]['status'] == '已授权' and snapshot['unlicensed'] == 0
        assert not any('udid' in k for k in snapshot['devices'][0])
        for action in ('udid-start', 'device-status'):
            assert api(action, token=secret)[0] == 410
        assert request('/profile.php?action=download&ticket=old', method='GET')[0] == 410
        assert request('/profile.php?action=callback&ticket=old', raw=b'old')[0] == 410
        page=request('/admin.php?panel=devices', method='GET', cookie=cookie)[1].decode()
        assert 'UDID' not in page and 'manual_grant' not in page
        db.execute('UPDATE licenses SET max_devices=3 WHERE id=1'); db.commit()
        assert api('activate', {'device_id':str(uuid.uuid4()), 'code':code})[1]['error'] == 'device_limit'
        db.execute('UPDATE licenses SET disabled=1 WHERE id=1'); db.commit()
        assert api('check', token=activate[1]['token'])[0] == 403
        assert api('activate', {'device_id':device, 'code':code})[0] == 403
        db.execute('UPDATE licenses SET disabled=0,expires_at=? WHERE id=1',(now-1,));db.commit()
        assert api('check', token=activate[1]['token'])[0] == 403
        assert api('activate', {'device_id':device, 'code':code})[0] == 403
        db.execute('UPDATE licenses SET expires_at=NULL WHERE id=1');db.commit()
        db.execute('UPDATE devices SET banned=1 WHERE device_hash=?', (sha(device),)); db.commit()
        assert api('check', token=activate[1]['token'])[0] == 403
        assert api('activate', {'device_id':device, 'code':code})[0] == 403
        assert api('heartbeat', {'page': 'settings'}, token=secret)[0] == 200
        assert request('/admin.php?snapshot=1', method='GET', cookie=cookie)[1]['devices'][0]['status'] == '已封禁'
        assert api('check', token=legacy_token)[0] == 200
        assert db.execute('SELECT code_hash,label FROM licenses').fetchone() == (sha(code), '历史卡密')
        # Device-code authorization uses authenticated registration, never UDID.
        granted_uuid=str(uuid.uuid4());grant_secret='e'*64
        registration=api('register',{'device_id':granted_uuid,'registration_secret':grant_secret,'model':'iPhone17,4'})
        device_code=registration[1]['device_code']
        assert api('manual-claim',token=grant_secret)[0]==404
        assert api('manual-claim',token='f'*64)[0]==401
        page=request('/admin.php?panel=devices',method='GET',cookie=cookie)[1].decode()
        csrf=re.search(r'name="csrf" value="([a-f0-9]+)"',page)[1]
        assert request('/admin.php',form={'action':'grant_device','device_code':device_code,'csrf':'invalid'},cookie=cookie)[0]==403
        grant_form={'action':'grant_device','device_code':device_code,'csrf':csrf,'return_panel':'devices'}
        assert request('/admin.php',form=grant_form,cookie=cookie)[0]==200
        claimed=api('manual-claim',token=grant_secret);assert claimed[0]==200,claimed
        grant_token=claimed[1]['token']
        assert api('check',token=grant_token)[0]==200
        assert api('check',token=grant_secret)[0]==401
        page=request('/admin.php?panel=devices',method='GET',cookie=cookie)[1].decode()
        assert page.count(device_code)>=1,'Legacy authorized list must display complete installation device code'
        assert 'UDID' not in page
        revoke=dict(grant_form,action='revoke_device')
        assert request('/admin.php',form=revoke,cookie=cookie)[0]==200
        assert api('manual-claim',token=grant_secret)[0]==404
        assert api('check',token=grant_token)[0]==403
        request('/admin.php',form=grant_form,cookie=cookie)
        assert api('manual-claim',token=grant_secret)[0]==200
        db.execute('UPDATE devices SET banned=1 WHERE device_hash=?',(sha(granted_uuid),));db.commit()
        assert api('manual-claim',token=grant_secret)[0]==403
        original_license=db.execute('SELECT license_id FROM devices WHERE device_hash=?',(sha(device),)).fetchone()[0]
        request('/admin.php',form=dict(grant_form,device_code='D-000001'),cookie=cookie)
        assert db.execute('SELECT license_id FROM devices WHERE device_hash=?',(sha(device),)).fetchone()[0]==original_license
        print('Passed: device-code grant/claim/revoke, CSRF, credential separation, full device code, ban enforcement; card-key activation without registration/UDID, existing tokens/data, credential separation, presence, limits/expiry/bans, removed UDID routes and admin UI.')
    finally:
        process.terminate(); process.wait(timeout=5); server_log.close()
