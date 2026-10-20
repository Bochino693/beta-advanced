@echo off
setlocal
cd /d "%~dp0"
title Strike Kids - Gerar APK
rem Gera o APK da TV Box: mostra cada passo nesta janela e guarda o
rem historico em build\android\GERACAO-COMPLETA.log. Opcoes (opcionais):
rem   GERAR_APK.bat -SemCamera      (APK sem a camera USB; mais rapido)
rem   GERAR_APK.bat -Giro -1        (topo do jogo na direita do HDMI)
rem   GERAR_APK.bat -Instalar       (instala na TV Box pelo adb)
if exist "%~dp0project.godot" goto projeto_ok
echo.
echo ERRO: extraia o ZIP inteiro antes e rode o GERAR_APK.bat de dentro
echo da pasta strike-kids (junto do arquivo project.godot).
echo.
pause
exit /b 1
:projeto_ok
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GERAR_APK.ps1" %*
set "RESULTADO=%ERRORLEVEL%"
echo.
if "%RESULTADO%"=="0" goto sucesso
echo ============================================================
echo  NAO FOI POSSIVEL GERAR O APK. Envie o arquivo:
echo  build\android\GERACAO-COMPLETA.log
echo ============================================================
goto fim
:sucesso
echo ============================================================
echo  PRONTO: APK-Pronto\StrikeKids.apk
echo ============================================================
:fim
echo.
pause
exit /b %RESULTADO%
