#!/bin/bash
# Builds AIUsage.app and zips it for sharing: dist/AIUsage.zip
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
mkdir -p dist && rm -f dist/AIUsage.zip
ditto -c -k --keepParent AIUsage.app dist/AIUsage.zip
echo "Created dist/AIUsage.zip"
