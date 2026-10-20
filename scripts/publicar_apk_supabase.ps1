# Script de publicacao automatica do APK no Supabase Storage
param(
  [switch]$Build = $false,
  [string]$ServiceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY
)

$ErrorActionPreference = "Stop"
$ProjectRoot = "$PSScriptRoot\.."
Set-Location -Path $ProjectRoot

$SupabaseUrl = "https://rygxmpwzofgieodvhpcy.supabase.co"
$ApiKey = if ($ServiceRoleKey) { $ServiceRoleKey } else { "sb_publishable_GshamuXeZLHEPF1bch5SgQ_eVXv_ckW" }
$ApkPath = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
$TargetFileName = "OmniLar-arm64-release.apk"

# 1. Compila se solicitado ou se o APK nao existir
if ($Build -or !(Test-Path $ApkPath)) {
  Write-Host "Compilando novo APK Release (--split-per-abi)..." -ForegroundColor Cyan
  flutter build apk --release --split-per-abi --dart-define=SENTRY_DSN=https://12b32d1db8bdf0ed9578cdd02e18d9e4@o4512285777657856.ingest.us.sentry.io/4512285825433600
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha ao compilar o APK."
    exit 1
  }
}

$ApkItem = Get-Item $ApkPath
$SizeMB = [math]::Round($ApkItem.Length / 1MB, 2)
Write-Host "Arquivo encontrado: $ApkPath ($SizeMB MB)" -ForegroundColor Cyan

# 2. Upload para o Supabase Storage
$UploadUrl = "$SupabaseUrl/storage/v1/object/releases/$TargetFileName"
Write-Host "Enviando para o Supabase Storage..." -ForegroundColor Cyan

$Headers = @(
  "-H", "apikey: $ApiKey",
  "-H", "Authorization: Bearer $ApiKey",
  "-H", "x-upsert: true",
  "-H", "Content-Type: application/vnd.android.package-archive"
)

$UploadResult = & curl.exe -s -w "\n%{http_code}" -X POST $UploadUrl @Headers --data-binary "@$ApkPath"
$Lines = $UploadResult -split "\r?\n"
$HttpCode = $Lines[-1]
$ResponseBody = ($Lines[0..($Lines.Length-2)]) -join "`n"

if ($HttpCode -eq "200" -or $HttpCode -eq "201") {
  Write-Host "Upload concluido com sucesso! (HTTP $HttpCode)" -ForegroundColor Green
  Write-Host "URL Publica do APK: $SupabaseUrl/storage/v1/object/public/releases/$TargetFileName" -ForegroundColor Yellow
  Write-Host "Link encurtado no site: https://omnilar.web.app/apk" -ForegroundColor Green
} else {
  Write-Error "Erro no upload (HTTP $HttpCode): $ResponseBody"
  Write-Host "Dica: certifique-se de que a migration 0106 foi executada no Supabase SQL Editor para liberar o upload no bucket 'releases'." -ForegroundColor Yellow
  exit 1
}
