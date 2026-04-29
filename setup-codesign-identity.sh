#!/usr/bin/env bash
# Creates a self-signed code-signing identity named "recmeet-dev" in the login
# keychain. Once installed, build-app.sh signs with this stable identity, so
# TCC treats every rebuild as the same app and your Microphone / Screen
# Recording approvals persist across rebuilds.
#
# You only need to run this ONCE per Mac.
set -euo pipefail

NAME="recmeet-dev"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ Identity \"$NAME\" already exists. Nothing to do."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

cat > cert.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

echo "→ Generating RSA key + self-signed certificate"
openssl genrsa -out key.pem 2048 2>/dev/null
openssl req -new -x509 -key key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null
PASS="recmeet"
# macOS Security framework only understands the legacy PKCS12 encryption.
# Newer openssl defaults to AES which causes "MAC verification failed".
openssl pkcs12 -export -out cert.p12 \
    -inkey key.pem -in cert.pem \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1 \
    -password "pass:$PASS" 2>/dev/null

echo "→ Importing into login keychain (you may be asked for your login password)"
security import cert.p12 \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -A

# Allow codesign to use the key without prompting on each build.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -k "" \
    "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

echo
echo "✓ Identity installed. Verify:"
security find-identity -v -p codesigning | grep "$NAME" || {
    echo "✗ Identity not found after import. Check Keychain Access manually."
    exit 1
}
