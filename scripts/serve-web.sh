#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../gridstream-web"
npm start
