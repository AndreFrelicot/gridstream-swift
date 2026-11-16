#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../gridstream-web"
npm ci
npx ng build --configuration production
