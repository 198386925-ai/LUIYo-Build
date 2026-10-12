#!/usr/bin/env python3
"""Upload the built IPA to catbox and record its URL in latest-ipa.txt on main.

Called by .github/workflows/build-ipa.yml after a successful build.
Requires env: GH_TOKEN (contents:write), GITHUB_REPOSITORY, GITHUB_RUN_ID.
"""
import base64
import datetime
import glob
import json
import os
import subprocess
import sys
import urllib.request
import urllib.error


def main() -> int:
    ipas = sorted(glob.glob("output/*.ipa"))
    if not ipas:
        print("no IPA found in output/", file=sys.stderr)
        return 1
    ipa = ipas[0]
    print("uploading", ipa, flush=True)
    out = subprocess.run(
        ["curl", "-fsSL", "--retry", "3",
         "-F", "reqtype=fileupload",
         "-F", "fileToUpload=@%s" % ipa,
         "https://catbox.moe/user/api.php"],
        capture_output=True, text=True, check=True)
    url = out.stdout.strip()
    if not url.startswith("https://"):
        print("unexpected upload response: %r" % out.stdout, file=sys.stderr)
        return 1
    print("uploaded:", url, flush=True)

    repo = os.environ["GITHUB_REPOSITORY"]
    token = os.environ["GH_TOKEN"]
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    built_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body_text = "url=%s\nrun_id=%s\nbuilt_at=%s\n" % (url, run_id, built_at)

    api = "https://api.github.com/repos/%s/contents/latest-ipa.txt" % repo
    headers = {"Authorization": "Bearer " + token,
               "Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28"}

    def call(url_, data=None, method="GET"):
        req = urllib.request.Request(url_, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req) as resp:
                return resp.status, json.loads(resp.read().decode() or "null")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode() or "null")

    _, cur = call(api + "?ref=main")
    payload = {"message": "CI: update latest IPA link",
               "content": base64.b64encode(body_text.encode()).decode(),
               "branch": "main"}
    if isinstance(cur, dict) and cur.get("sha"):
        payload["sha"] = cur["sha"]
    status, _ = call(api, data=json.dumps(payload).encode(), method="PUT")
    if status not in (200, 201):
        print("update latest-ipa.txt failed: HTTP %s" % status, file=sys.stderr)
        return 1
    print("latest-ipa.txt updated", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
