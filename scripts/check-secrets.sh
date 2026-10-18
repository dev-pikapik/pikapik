#!/bin/bash
# Fails when the code holds a signing key, certificate, provisioning profile, keychain, .env file, private key or access token.
set -euo pipefail
cd "$(dirname "$0")/.."

found=$( {
    git ls-files -- '*.p12' '*.pfx' '*.p8' '*.cer' '*.mobileprovision' '*.provisionprofile' '*.keychain' '*.keychain-db' '.env*' '*/.env*'
    git grep -lI -E -e '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' -e 'gh[pousr]_[A-Za-z0-9]{36,}' -e 'github_pat_[A-Za-z0-9_]{22,}' || true
} | sort -u)
if [ -n "$found" ]; then
    while IFS= read -r file; do
        echo "::error file=$file::$file looks like a secret. Secrets belong in GitHub Actions secrets, never in the code"
    done <<< "$found"
    exit 1
fi
echo "No secrets in the code"
