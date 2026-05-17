#!/usr/bin/env bash
set -euo pipefail

# One-time setup: create a self-signed code-signing identity called
# "dwmac-signer" in the login keychain. Every future build signed with it
# produces the SAME designated requirement, so macOS keeps the
# Accessibility grant across rebuilds.
#
# Requires sudo for marking the certificate as trusted.

CERT_NAME="dwmac-signer"
KEY_PATH="/tmp/${CERT_NAME}.key"
CRT_PATH="/tmp/${CERT_NAME}.crt"
P12_PATH="/tmp/${CERT_NAME}.p12"
P12_PASS="${CERT_NAME}"

if /usr/bin/security find-identity -p codesigning -v 2>/dev/null | grep -q "${CERT_NAME}"; then
    echo "Identity '${CERT_NAME}' already present."
    exit 0
fi

echo "==> Generating private key + self-signed certificate"
openssl req -x509 -newkey rsa:2048 -keyout "${KEY_PATH}" -out "${CRT_PATH}" \
    -days 36500 -nodes \
    -subj "/CN=${CERT_NAME}/O=dwmac/OU=local" \
    -addext "basicConstraints = critical,CA:false" \
    -addext "keyUsage = critical,digitalSignature" \
    -addext "extendedKeyUsage = critical,codeSigning"

echo "==> Bundling into PKCS#12 (legacy algo for macOS compat)"
openssl pkcs12 -export -legacy \
    -inkey "${KEY_PATH}" -in "${CRT_PATH}" \
    -out "${P12_PATH}" -passout "pass:${P12_PASS}" \
    -name "${CERT_NAME}"

echo "==> Importing into login keychain"
/usr/bin/security import "${P12_PATH}" \
    -k "${HOME}/Library/Keychains/login.keychain-db" \
    -P "${P12_PASS}" \
    -T /usr/bin/codesign \
    -A

echo "==> Marking certificate as trusted for code signing (sudo required)"
sudo /usr/bin/security add-trusted-cert -d -r trustRoot \
    -p codeSign \
    -k /Library/Keychains/System.keychain \
    "${CRT_PATH}"

# Clean up the temporary files; the cert + key now live in the keychain.
rm -f "${KEY_PATH}" "${CRT_PATH}" "${P12_PATH}"

echo "==> Done. Identity created:"
/usr/bin/security find-identity -p codesigning -v 2>&1 | grep "${CERT_NAME}"
echo
echo "Now run scripts/install.sh to rebuild + re-sign + start dwmac."
