@echo off
title GuildVoiceManager {{VERSION}} - Mise a jour
color 0E

:: --- Verification des droits admin ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ================================================
    echo    GuildVoiceManager {{VERSION}} - Mise a jour
    echo    Par Anthony aka NIXshade
    echo  ================================================
    echo.
    echo  Ce script necessite les droits administrateur
    echo  pour eviter que Windows Defender bloque
    echo  la mise a jour.
    echo.
    echo  Une fenetre va s'ouvrir pour demander
    echo  l'autorisation. Clique sur "Oui".
    echo.
    echo  Discord sera ferme automatiquement.
    echo.
    pause
    taskkill /f /im Discord.exe >nul 2>&1
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: --- Deja admin, on lance ---
echo.
echo  ================================================
echo    GuildVoiceManager {{VERSION}} - Mise a jour
echo    Par Anthony aka NIXshade
echo  ================================================
echo.
echo  Droits administrateur : OK
echo.

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0install.ps1"

echo.
echo  Appuie sur une touche pour fermer...
pause >nul
