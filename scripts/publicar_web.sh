#!/usr/bin/env bash
# Publica o site do Omni Lar no Firebase Hosting (https://omnilar.web.app).
# Antes, uma vez: firebase login (com a conta dona do projeto omnilar-ef002).
set -euo pipefail
cd "$(dirname "$0")/.."

# Os testes rodam primeiro: não se publica com teste quebrado
flutter analyze --no-fatal-infos
flutter test

flutter build web --release
firebase deploy --only hosting --project omnilar-ef002

echo "Publicado em https://omnilar.web.app"
