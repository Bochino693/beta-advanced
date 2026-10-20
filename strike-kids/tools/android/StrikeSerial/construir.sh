#!/bin/sh
# Monta addons/StrikeSerial/bin/StrikeSerial.aar (plugin Android do Arduino:
# USB serial próprio - CDC, CH340, FTDI e CP210x - sem biblioteca de fora).
# Precisa de: JDK (javac) e internet (Maven Central) na primeira vez.
#   sh tools/android/StrikeSerial/construir.sh
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
RAIZ=$(cd "$AQUI/../../.." && pwd)
CACHE=${CACHE:-$AQUI/../StrikeCamera/.cache}
mkdir -p "$CACHE"
# classes do Android (só para compilar; no aparelho valem as da TV Box)
[ -f "$CACHE/android-all.jar" ] || curl -sSL -o "$CACHE/android-all.jar" \
  https://repo1.maven.org/maven2/org/robolectric/android-all/10-robolectric-5803371/android-all-10-robolectric-5803371.jar
# classes do Godot 4.6.1 (GodotPlugin)
if [ ! -f "$CACHE/godot-classes.jar" ]; then
  curl -sSL -o "$CACHE/godot.aar" https://repo1.maven.org/maven2/org/godotengine/godot/4.6.1.stable/godot-4.6.1.stable.aar
  (cd "$CACHE" && unzip -o -q godot.aar classes.jar && mv classes.jar godot-classes.jar && rm godot.aar)
fi
T=$(mktemp -d)
mkdir -p "$T/classes" "$T/aar"
javac --release 8 -nowarn -encoding UTF-8 -cp "$CACHE/android-all.jar:$CACHE/godot-classes.jar" \
  -d "$T/classes" "$AQUI"/src/com/lazersport/strikeserial/*.java
(cd "$T/classes" && jar cf "$T/aar/classes.jar" .)
cp "$AQUI/AndroidManifest.xml" "$T/aar/AndroidManifest.xml"
# o filtro dos Arduinos (atividade de encaixe: "Usar por padrão")
cp -r "$AQUI/res" "$T/aar/res"
printf 'int xml strike_usb_arduino 0x7f140001\n' > "$T/aar/R.txt"
mkdir -p "$RAIZ/addons/StrikeSerial/bin"
rm -f "$RAIZ/addons/StrikeSerial/bin/StrikeSerial.aar"
(cd "$T/aar" && jar cfM "$RAIZ/addons/StrikeSerial/bin/StrikeSerial.aar" AndroidManifest.xml classes.jar R.txt res)
rm -rf "$T"
echo "ok: addons/StrikeSerial/bin/StrikeSerial.aar"
