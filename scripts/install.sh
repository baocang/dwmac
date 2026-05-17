#!/usr/bin/env bash
set -euo pipefail

# Build a release binary, install it, and start the LaunchAgent.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/dwmac"
LOG_PATH="${HOME}/Library/Logs/dwmac.log"
AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_LABEL="com.dwmac.agent"
AGENT_PLIST="${AGENT_DIR}/${AGENT_LABEL}.plist"
TEMPLATE="${REPO_ROOT}/LaunchAgent/com.dwmac.agent.plist"

echo "==> Building release binary"
cd "${REPO_ROOT}"
swift build -c release

BUILT_BIN="${REPO_ROOT}/.build/release/dwmac"
if [[ ! -x "${BUILT_BIN}" ]]; then
    echo "ERROR: build did not produce ${BUILT_BIN}" >&2
    exit 1
fi

mkdir -p "${BIN_DIR}" "${AGENT_DIR}" "$(dirname "${LOG_PATH}")"
install -m 0755 "${BUILT_BIN}" "${BIN_PATH}"
echo "==> Installed binary: ${BIN_PATH}"

# Code-sign with a stable identity so TCC's Accessibility grant survives
# every rebuild. Prefer the self-signed "dwmac-signer" cert (created
# during first install). Fall back to ad-hoc if it's missing.
CODESIGN_IDENTITY=$(/usr/bin/security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/"dwmac-signer"/{print $2; exit}')
if [[ -n "${CODESIGN_IDENTITY}" ]]; then
    if /usr/bin/codesign --force --identifier "com.dwmac.agent" --sign "${CODESIGN_IDENTITY}" "${BIN_PATH}"; then
        echo "==> Signed ${BIN_PATH} with identity '${CODESIGN_IDENTITY}'"
    else
        echo "==> WARNING: codesign with identity failed; falling back to ad-hoc"
        /usr/bin/codesign --force --identifier "com.dwmac.agent" --sign - "${BIN_PATH}" || true
    fi
else
    echo "==> 'dwmac-signer' identity not found — ad-hoc signing"
    echo "    (run scripts/install-codesign-identity.sh once to create it)"
    /usr/bin/codesign --force --identifier "com.dwmac.agent" --sign - "${BIN_PATH}" || true
fi

# Render plist by substituting placeholders.
sed -e "s|__BINARY_PATH__|${BIN_PATH}|g" \
    -e "s|__LOG_PATH__|${LOG_PATH}|g" \
    "${TEMPLATE}" > "${AGENT_PLIST}"
echo "==> Wrote LaunchAgent plist: ${AGENT_PLIST}"

# Reload the agent.
DOMAIN="gui/$(id -u)"
if launchctl print "${DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
    echo "==> Unloading existing agent"
    launchctl bootout "${DOMAIN}" "${AGENT_PLIST}" || true
fi
echo "==> Loading agent"
launchctl bootstrap "${DOMAIN}" "${AGENT_PLIST}"
launchctl enable "${DOMAIN}/${AGENT_LABEL}"
launchctl kickstart -k "${DOMAIN}/${AGENT_LABEL}" || true

cat <<EOF

dwmac is installed and started.

If this is the first run, macOS will prompt for Accessibility permission.
Grant it under:
    System Settings → Privacy & Security → Accessibility
    enable the entry for: ${BIN_PATH}

The LaunchAgent retries every 10 seconds until permission is granted.

Logs:    ${LOG_PATH}
Config:  ~/.config/dwmac/config.json

To reload after changing config:
    launchctl kickstart -k ${DOMAIN}/${AGENT_LABEL}

To uninstall:
    ${REPO_ROOT}/scripts/uninstall.sh
EOF
