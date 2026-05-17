#!/usr/bin/env bash
set -euo pipefail

AGENT_LABEL="com.dwmac.agent"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${AGENT_LABEL}.plist"
BIN_PATH="${HOME}/.local/bin/dwmac"
DOMAIN="gui/$(id -u)"

if launchctl print "${DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
    echo "==> Stopping agent"
    launchctl bootout "${DOMAIN}/${AGENT_LABEL}" || true
fi

if [[ -f "${AGENT_PLIST}" ]]; then
    rm -f "${AGENT_PLIST}"
    echo "==> Removed ${AGENT_PLIST}"
fi

if [[ -f "${BIN_PATH}" ]]; then
    rm -f "${BIN_PATH}"
    echo "==> Removed ${BIN_PATH}"
fi

echo "dwmac uninstalled."
echo "Config at ~/.config/dwmac/config.json and log at ~/Library/Logs/dwmac.log were NOT removed."
