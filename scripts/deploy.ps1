# Script unificado de deploy do Omni Lar:
# 1. Analisa o codigo
# 2. Compila o APK otimizado Android (--split-per-abi)
# 3. Faz upload do APK para o Supabase Storage
# 4. Compila a versao Web de producao
# 5. Faz deploy no Firebase Hosting
# 6. Copia o APK para a pasta Downloads para conveniencia

$ErrorActionPreference = "Stop"
$ProjectRoot = "$PSScriptRoot\.."
Set-Location -Path $ProjectRoot

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "       OMNI LAR - DEPLOY UNIFICADO (APK + WEB)        " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Analise
Write-Host "[1/5] Executando flutter analyze..." -ForegroundColor Cyan
flutter analyze --no-fatal-infos

# 2. Compilacao do APK
Write-Host "`n[2/5] Compilando APK Release Android (--split-per-abi)..." -ForegroundColor Cyan
flutter build apk --release --split-per-abi

$ApkSource = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if (!(Test-Path $ApkSource)) {
  Write-Error "O APK compilado nao foi encontrado em $ApkSource."
  exit 1
}

$ApkItem = Get-Item $ApkSource
$SizeMB = [math]::Round($ApkItem.Length / 1MB, 2)
Write-Host "APK gerado com sucesso: $SizeMB MB" -ForegroundColor Green

# Copia para Downloads
Copy-Item $ApkSource -Destination "$HOME\Downloads\OmniLar-arm64-release.apk" -Force
Write-Host "Copia salva em: $HOME\Downloads\OmniLar-arm64-release.apk" -ForegroundColor DarkGray

# 3. Upload para Supabase Storage
Write-Host "`n[3/5] Enviando APK para o Supabase Storage..." -ForegroundColor Cyan
$SupabaseUrl = "https://rygxmpwzofgieodvhpcy.supabase.co"
$ApiKey = if ($env:SUPABASE_SERVICE_ROLE_KEY) { $env:SUPABASE_SERVICE_ROLE_KEY } else { "sb_publishable_GshamuXeZLHEPF1bch5SgQ_eVXv_ckW" }
$TargetFileName = "OmniLar-arm64-release.apk"
$UploadUrl = "$SupabaseUrl/storage/v1/object/releases/$TargetFileName"

$Headers = @(
  "-H", "apikey: $ApiKey",
  "-H", "Authorization: Bearer $ApiKey",
  "-H", "x-upsert: true",
  "-H", "Content-Type: application/vnd.android.package-archive"
)

$UploadResult = & curl.exe -s -w "\n%{http_code}" -X POST $UploadUrl @Headers --data-binary "@$ApkSource"
$Lines = $UploadResult -split "\r?\n"
$HttpCode = $Lines[-1]
$ResponseBody = ($Lines[0..($Lines.Length-2)]) -join "`n"

if ($HttpCode -eq "200" -or $HttpCode -eq "201") {
  Write-Host "APK publicado no Supabase Storage! (HTTP $HttpCode)" -ForegroundColor Green
} else {
  Write-Warning "Falha no upload para o Supabase (HTTP $HttpCode): $ResponseBody"
  Write-Warning "Certifique-se de que a migration 0106 foi rodada no Supabase SQL Editor."
}

# 4. Compilacao Web
Write-Host "`n[4/5] Compilando versao Web..." -ForegroundColor Cyan
flutter build web --release

# 5. Deploy Firebase Hosting
Write-Host "`n[5/5] Publicando no Firebase Hosting..." -ForegroundColor Cyan
firebase deploy --only hosting --project omnilar-ef002

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "               DEPLOY CONCLUIDO COM SUCESSO!           " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "Web: https://omnilar.web.app" -ForegroundColor Cyan
Write-Host "Download APK: https://omnilar.web.app/apk" -ForegroundColor Cyan
Write-Host "Supabase Direct: $SupabaseUrl/storage/v1/object/public/releases/$TargetFileName" -ForegroundColor Cyan
Write-Host ""
