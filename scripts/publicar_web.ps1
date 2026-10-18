# Publica o site do Omni Lar no Firebase Hosting (https://omnilar.web.app).
# Antes, uma vez: firebase login (com a conta dona do projeto omnilar-ef002).
$ErrorActionPreference = "Stop"

Set-Location -Path "$PSScriptRoot\.."

Write-Host "Executando flutter analyze..." -ForegroundColor Cyan
flutter analyze --no-fatal-infos

Write-Host "Executando flutter test..." -ForegroundColor Cyan
flutter test

Write-Host "Gerando build de producao web..." -ForegroundColor Cyan
flutter build web --release

Write-Host "Fazendo deploy no Firebase Hosting..." -ForegroundColor Cyan
firebase deploy --only hosting --project omnilar-ef002

Write-Host "Publicado com sucesso em https://omnilar.web.app" -ForegroundColor Green
