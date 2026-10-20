#!/usr/bin/env bash
# Publica o site do Omni Lar no Firebase Hosting (https://omnilar.web.app).
# Antes, uma vez: firebase login (com a conta dona do projeto omnilar-ef002).
set -euo pipefail
cd "$(dirname "$0")/.."

# Os testes rodam primeiro: não se publica com teste quebrado
flutter analyze --no-fatal-infos
flutter test

flutter build web --release --dart-define=SENTRY_DSN=https://12b32d1db8bdf0ed9578cdd02e18d9e4@o4512285777657856.ingest.us.sentry.io/4512285825433600
firebase deploy --only hosting --project omnilar-ef002

echo "Publicado em https://omnilar.web.app"
