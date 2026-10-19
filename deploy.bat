@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\deploy.ps1"
if errorlevel 1 (
    echo.
    echo Ocorreu um erro durante o deploy.
    pause
    exit /b 1
)

echo.
echo Pressione qualquer tecla para sair.
pause >nul
exit /b 0
