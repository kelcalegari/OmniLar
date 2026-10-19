@echo off
setlocal
cd /d "%~dp0"

echo =======================================================
echo          OMNI LAR - PUBLICADOR DE APK RELEASE
echo =======================================================
echo.
echo Escolha uma opcao:
echo   [1] Apenas subir o APK atual para o Supabase (mais rapido)
echo   [2] Compilar novo APK e subir para o Supabase
echo   [3] Compilar APK, subir para o Supabase e publicar Web no Firebase
echo.
set /p opt="Digite a opcao [1, 2 ou 3] (padrao 1): "
if "%opt%"=="" set opt=1

if "%opt%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\publicar_apk_supabase.ps1"
) else if "%opt%"=="2" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\publicar_apk_supabase.ps1" -Build
) else if "%opt%"=="3" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\publicar_apk_supabase.ps1" -Build
    if errorlevel 1 goto erro
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\publicar_web.ps1"
) else (
    echo Opcao invalida.
    goto fim
)

:fim
echo.
echo Concluido! Pressione qualquer tecla para sair.
pause >nul
exit /b 0

:erro
echo.
echo Ocorreu um erro durante a execucao.
pause >nul
exit /b 1
