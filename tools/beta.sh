#!/bin/bash
# One-command beta release: bump the patch version (or set VERSION), export a store package,
# and open the upload page so the rest is a single drag and drop. Garmin has no upload API, so
# the upload itself stays manual.
#
#   tools/beta.sh
#   VERSION=1.0.0 tools/beta.sh
#   RELEASE=public tools/beta.sh
#
# The Connect IQ Store never publishes an app first uploaded as a beta, so beta packages are
# built under their own app id (BETA_APP_ID) and the manifest's id stays free for the public
# listing. NO_OPEN=1 skips opening the browser and Finder.
#
# DEVKEY overrides the developer key path. APP_ID (env or git-ignored .beta.env) opens the
# app's own page instead of the developer dashboard.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .beta.env ]; then set -a; . ./.beta.env; set +a; fi
DEVKEY="${DEVKEY:-$HOME/projects/cgm-garmin-datafield/.env/developer_key}"
RELEASE="${RELEASE:-beta}"
BETA_APP_ID="34dc0ea48e0a496bb50dd90bfa30ac3d"
[ -f "$DEVKEY" ] || { echo "Developer key not found: $DEVKEY" >&2; exit 1; }
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Commit or stash your changes first; the version bump is committed on its own." >&2
    exit 1
fi

# Store builds never use the personal overrides: settings come from the phone.
VERSION=$(VERSION="${VERSION:-}" python3 - <<'PY'
import os, re
s = open("manifest.xml").read()
m = re.search(r'(<iq:application\b[^>]*\bversion=")(\d+)\.(\d+)\.(\d+)(")', s)
major, minor, patch = (int(x) for x in m.group(2, 3, 4))
v = os.environ.get("VERSION") or "%d.%d.%d" % (major, minor, patch + 1)
s = s[:m.start()] + m.group(1) + v + m.group(5) + s[m.end():]
open("manifest.xml", "w").write(s)
print(v)
PY
)

git diff --quiet manifest.xml || git commit -q -m "chore: release $VERSION" manifest.xml

mkdir -p dist
if [ "$RELEASE" = "beta" ]; then
    OUT="dist/CgmFace-$VERSION-beta.iq"
    cp manifest.xml manifest.xml.orig
    trap 'mv manifest.xml.orig manifest.xml' EXIT
    sed -i '' "s/<iq:application id=\"[0-9a-f]*\"/<iq:application id=\"$BETA_APP_ID\"/" manifest.xml
    grep -q "id=\"$BETA_APP_ID\"" manifest.xml || { echo "Could not set the beta app id" >&2; exit 1; }
else
    OUT="dist/CgmFace-$VERSION.iq"
fi
monkeyc -e -r -f monkey.jungle -o "$OUT" -y "$DEVKEY" -w

if [ -n "${NO_OPEN:-}" ]; then
    :
elif [ -n "${APP_ID:-}" ]; then
    open "https://apps.garmin.com/developer/$APP_ID/update"
else
    open "https://apps.garmin.com/en-US/developer/upload"
fi
[ -n "${NO_OPEN:-}" ] || open -R "$OUT"

cat <<MSG

Built $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' ')), version $VERSION, $RELEASE.
Next:
  1. Sign in on the page that just opened.
MSG
if [ "$RELEASE" = "beta" ]; then
    echo '  2. First time: Upload an App, drop the .iq, tick "Beta app". Later: open the app and upload a new version.'
    echo '  3. On the phone: Connect IQ app > My Device > Dotscout > Install, then set the URL and token in its settings.'
else
    echo '  2. Open the public app in the developer dashboard and choose Upload New Version (don'"'"'t tick "Beta app").'
    echo "  3. Tag the release so CI attaches it to GitHub: git tag v$VERSION && git push origin v$VERSION"
fi
