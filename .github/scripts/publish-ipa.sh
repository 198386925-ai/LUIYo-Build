#!/usr/bin/env bash
# Publish the built IPA to the orphan `dist` branch (force-push, single file).
# Called by .github/workflows/build-ipa.yml after a successful build.
# Requires env: GH_TOKEN (contents:write), GITHUB_REPOSITORY, GITHUB_RUN_ID.
set -euo pipefail

IPA=$(ls output/*.ipa | head -1)
echo "publishing $IPA to dist branch"
BUILT_AT=$(date -u +%FT%TZ)

rm -rf /tmp/dist-publish && mkdir -p /tmp/dist-publish
cp "$IPA" /tmp/dist-publish/LUIYo-latest.ipa
printf 'run_id=%s\nbuilt_at=%s\n' "$GITHUB_RUN_ID" "$BUILT_AT" > /tmp/dist-publish/latest-ipa.txt

cd /tmp/dist-publish
git init -q -b dist
git add LUIYo-latest.ipa latest-ipa.txt
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -qm "CI: latest IPA (run $GITHUB_RUN_ID)"
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git push -f -q origin dist
echo "published LUIYo-latest.ipa to dist branch"
