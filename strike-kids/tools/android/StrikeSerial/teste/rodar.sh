#!/bin/sh
# Teste das contas do plugin StrikeSerial no PC (só precisa do JDK).
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
javac -nowarn -encoding UTF-8 -d "$T" "$AQUI/../src/com/lazersport/strikeserial/SerialUtil.java" "$AQUI/TesteSerialUtil.java"
java -cp "$T" TesteSerialUtil
rm -rf "$T"
