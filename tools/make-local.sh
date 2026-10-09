#!/bin/bash
# Writes the git-ignored overrides for a personal device build: Nightscout as the data source,
# with the URL and token baked in (sideloaded apps can't be configured from Garmin Connect).
#
#   NIGHTSCOUT_TOKEN=reader-abc123 tools/make-local.sh   (or put both in .env)
#   monkeyc -d fr965 -f "monkey.jungle;local.jungle" -o bin/CgmFace.prg -y /path/to/developer_key
set -euo pipefail
cd "$(dirname "$0")/.."
# Values can also come from a git-ignored .env (NIGHTSCOUT_URL=..., NIGHTSCOUT_TOKEN=...).
if [ -f .env ]; then set -a; . ./.env; set +a; fi
NIGHTSCOUT_URL="${NIGHTSCOUT_URL:?set NIGHTSCOUT_URL (or put it in .env)}"
TOKEN="${NIGHTSCOUT_TOKEN:-}"
mkdir -p resources-local
cat > resources-local/properties.xml <<XML
<resources>
    <properties>
        <property id="DataSource" type="number">1</property>
        <property id="NightscoutUrl" type="string">${NIGHTSCOUT_URL}</property>
        <property id="NightscoutToken" type="string">${TOKEN}</property>
    </properties>
</resources>
XML
echo 'base.resourcePath = $(base.resourcePath);resources-local' > local.jungle
echo "Wrote resources-local/properties.xml and local.jungle${TOKEN:+ (token set)}"
