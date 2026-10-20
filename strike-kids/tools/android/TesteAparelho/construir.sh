#!/bin/sh
# Monta o TesteAparelho.apk (app pequeno, sem Godot, Android 4.1+): mostra
# na tela e grava em aparelho.txt se a TV Box roda o Strike Kids (placa de
# vídeo e OpenGL ES 3, Android, 32/64 bits, memória de verdade, USB).
# Precisa de: JDK (javac), o apktool, o dx e o uber-apk-signer (veja as
# variáveis abaixo) e internet (Maven Central) na primeira vez.
#   sh tools/android/TesteAparelho/construir.sh saida.apk
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
SAIDA=${1:-$AQUI/TesteAparelho.apk}
CACHE=${CACHE:-$AQUI/.cache}
APKTOOL=${APKTOOL:-apktool_2.10.0.jar}
DX=${DX:-dalvik-dx-9.0.0_r3.jar}
ASSINADOR=${ASSINADOR:-uber-apk-signer-1.3.0.jar}
CHAVE=${CHAVE:-$AQUI/../strikekids.keystore}
mkdir -p "$CACHE"
[ -f "$CACHE/android-all.jar" ] || curl -sSL -o "$CACHE/android-all.jar" \
  https://repo1.maven.org/maven2/org/robolectric/android-all/10-robolectric-5803371/android-all-10-robolectric-5803371.jar
T=$(mktemp -d)
mkdir -p "$T/classes" "$T/dec"
javac --release 8 -nowarn -encoding UTF-8 -cp "$CACHE/android-all.jar" -d "$T/classes" \
  "$AQUI"/src/com/lazersport/testeaparelho/*.java
java -cp "$DX" com.android.dx.command.Main --dex --min-sdk-version=16 --output="$T/dec/classes.dex" "$T/classes"
cp "$AQUI/AndroidManifest.xml" "$T/dec/"
cp -r "$AQUI/res" "$T/dec/res"
cat > "$T/dec/apktool.yml" <<YML
version: 2.10.0
apkFileName: teste.apk
isFrameworkApk: false
usesFramework:
  ids:
  - 1
  tag: null
sdkInfo:
  minSdkVersion: 16
  targetSdkVersion: 28
packageInfo:
  forcedPackageId: 127
  renameManifestPackage: null
versionInfo:
  versionCode: 1
  versionName: 1.0
resourcesAreCompressed: false
sharedLibrary: false
sparseResources: false
doNotCompress:
- resources.arsc
YML
java -jar "$APKTOOL" b "$T/dec" -o "$T/sem_assinatura.apk"
mkdir -p "$T/assinado"
java -jar "$ASSINADOR" -a "$T/sem_assinatura.apk" -o "$T/assinado" --ks "$CHAVE" --ksAlias strikekids \
  --ksPass strikekids --ksKeyPass strikekids
cp "$T/assinado/sem_assinatura-aligned-signed.apk" "$SAIDA"
rm -rf "$T"
echo "ok: $SAIDA"
