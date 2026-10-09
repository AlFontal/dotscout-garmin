#!/bin/bash
# Installs the Connect IQ SDK and the devices in manifest.xml on a CI runner, using the
# community connect-iq-sdk-manager CLI (Garmin serves device files only to a signed-in account).
# Needs GARMIN_USERNAME, GARMIN_PASSWORD and CIQ_AGREEMENT_HASH in the environment.
set -euo pipefail
SDK_VERSION="${SDK_VERSION:-9.1.0}"
CLI_VERSION="${CLI_VERSION:-v0.8.4}"
curl -fsSL https://raw.githubusercontent.com/lindell/connect-iq-sdk-manager-cli/v0.8.4/install.sh | sh -s -- -b "$HOME/.local/bin" "$CLI_VERSION"
export PATH="$HOME/.local/bin:$PATH"
connect-iq-sdk-manager agreement accept --acceptance-hash="$CIQ_AGREEMENT_HASH"
connect-iq-sdk-manager login
connect-iq-sdk-manager sdk set "$SDK_VERSION"
connect-iq-sdk-manager device download --manifest=manifest.xml
echo "$(connect-iq-sdk-manager sdk current-path --bin)" >> "$GITHUB_PATH"
