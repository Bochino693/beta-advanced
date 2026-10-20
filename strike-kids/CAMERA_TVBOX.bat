@echo off
setlocal
cd /d "%~dp0"
title Strike Kids - Camera da TV Box

rem UM COMANDO SO PARA A CAMERA (igual ao CAMERA_TVBOX do jogo de soco):
rem   1. libera a camera para o jogo (sem janela nenhuma na TV Box);
rem   2. abre o jogo do zero e espera a camera acordar (ela acorda 15 s
rem      depois da abertura e fica ligada);
rem   3. grava CAMERA_RELATORIO.txt com tudo o que o Android enxerga (USB,
rem      cameras, permissoes) e o que o jogo tentou, passo a passo.
rem Com a TV Box na rede, passe o IP:  CAMERA_TVBOX.bat 192.168.0.50
set "PKG=com.lazersport.strikekids"
set "SAIDA=%~dp0CAMERA_RELATORIO.txt"
set "ADB="
for %%D in ("%ANDROID_HOME%" "%ANDROID_SDK_ROOT%" "C:\AndroidSdk" "C:\Android\Sdk" "%LOCALAPPDATA%\Android\Sdk" "%SystemDrive%\StrikeKidsBuild\android-sdk" "%PUBLIC%\StrikeKidsBuild\android-sdk" "%LOCALAPPDATA%\StrikeKidsBuild\android-sdk") do (
  if not defined ADB if exist "%%~D\platform-tools\adb.exe" set "ADB=%%~D\platform-tools\adb.exe"
)
if not defined ADB (
  where adb >nul 2>&1 && set "ADB=adb"
)
if not defined ADB (
  echo ERRO: adb nao encontrado. Rode o GERAR_APK.bat uma vez ^(ele instala o
  echo Android SDK^) ou instale o "platform-tools" do Android.
  pause
  exit /b 1
)
if not "%~1"=="" "%ADB%" connect %~1:5555
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (
  echo ERRO: nenhuma TV Box conectada no ADB.
  echo Ligue a depuracao USB/rede na TV Box ou passe o IP:  CAMERA_TVBOX.bat 192.168.0.50
  pause
  exit /b 1
)

echo [1/4] Liberando a camera para o jogo...
"%ADB%" shell pm grant %PKG% android.permission.CAMERA
"%ADB%" shell appops set %PKG% CAMERA allow

echo [2/4] Abrindo o jogo do zero...
"%ADB%" shell am force-stop %PKG%
"%ADB%" logcat -c
"%ADB%" shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1 >nul 2>&1

echo [3/4] Esperando o jogo abrir e a camera acordar (60 s, nao mexa)...
timeout /t 60 /nobreak >nul

echo [4/4] Gravando o relatorio...
> "%SAIDA%" echo STRIKE KIDS - RELATORIO DA CAMERA
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== APARELHO
"%ADB%" shell getprop ro.product.manufacturer >> "%SAIDA%" 2>&1
"%ADB%" shell getprop ro.product.model >> "%SAIDA%" 2>&1
"%ADB%" shell getprop ro.build.version.release >> "%SAIDA%" 2>&1
"%ADB%" shell getprop ro.board.platform >> "%SAIDA%" 2>&1
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== DISPOSITIVOS DE VIDEO DO SISTEMA
"%ADB%" shell "ls -l /dev/video* 2>&1" >> "%SAIDA%" 2>&1
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== USB
"%ADB%" shell "dumpsys usb | grep -i -E 'vid|pid|class|manufacturer|product|permission|device_name|Device ' | head -80" >> "%SAIDA%" 2>&1
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== SERVICO DE CAMERA DO ANDROID
"%ADB%" shell "dumpsys media.camera | head -150" >> "%SAIDA%" 2>&1
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== PERMISSOES DO JOGO
"%ADB%" shell "dumpsys package %PKG% | grep -i -E 'CAMERA|granted' | head -30" >> "%SAIDA%" 2>&1
>> "%SAIDA%" echo.
>> "%SAIDA%" echo ===== O QUE O JOGO TENTOU (camera: StrikeCamera, Arduino: StrikeSerial)
"%ADB%" logcat -d -v time -s StrikeCamera:* StrikeSerial:* godot:I UVCCamera:* libUVCCamera:* CameraService:W AndroidRuntime:E >> "%SAIDA%" 2>&1

echo.
echo PRONTO. O relatorio esta em:
echo   %SAIDA%
echo Mande esse arquivo (ou uma foto dele) para ajustar a camera.
start "" notepad "%SAIDA%"
pause
exit /b 0
