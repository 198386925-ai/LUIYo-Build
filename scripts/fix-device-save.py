#!/usr/bin/env python3
"""Build-time: inject device_code saving into AppDelegate.swift"""
from pathlib import Path

def main():
    files = list(Path(".").rglob("AppDelegate.swift"))
    files = [f for f in files if "YouYouLUI_iOS" in str(f)]
    if not files:
        print("AppDelegate.swift not found")
        return
    p = files[0]
    s = p.read_text(encoding="utf-8", errors="ignore")
    # Check for our specific patch marker (the write pattern we inject)
    if 'UserDefaults.standard.set(dc, forKey: "youyou.device.code")' in s:
        print("Already patched")
        return
    orig = s
    # Patch 1: token refresh handler
    old1 = '''            if status == 200, let token = body?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()'''
    new1 = '''            if status == 200, let token = body?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                if let dc = body?["device_code"] as? String, !dc.isEmpty {
                    UserDefaults.standard.set(dc, forKey: "youyou.device.code")
                }
                self.allowAccess()'''
    if old1 in s:
        s = s.replace(old1, new1, 1)
        print("Patched handler 1")
    # Patch 2: activate handler
    old2 = '''            if httpCode == 200, let token = data?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()'''
    new2 = '''            if httpCode == 200, let token = data?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                if let dc = data?["device_code"] as? String, !dc.isEmpty {
                    UserDefaults.standard.set(dc, forKey: "youyou.device.code")
                }
                self.allowAccess()'''
    if old2 in s:
        s = s.replace(old2, new2, 1)
        print("Patched handler 2")
    # Patch 3: check handler
    old3 = '''            if code == 200, body?["status"] == "active" {
                self.allowAccess()'''
    new3 = '''            if code == 200, body?["status"] == "active" {
                if let dc = body?["device_code"] as? String, !dc.isEmpty {
                    UserDefaults.standard.set(dc, forKey: "youyou.device.code")
                }
                self.allowAccess()'''
    if old3 in s:
        s = s.replace(old3, new3, 1)
        print("Patched handler 3")
    if s != orig:
        p.write_text(s, encoding="utf-8")
        print(f"WROTE {p}")
    else:
        print("No changes applied - patterns not found")

if __name__ == "__main__":
    main()
