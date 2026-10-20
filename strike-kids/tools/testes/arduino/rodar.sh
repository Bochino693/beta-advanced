#!/bin/bash
# Compila o firmware do Arduino para as placas e roda o teste no ATmega328P
# simulado (simavr).
#   tools/testes/arduino/rodar.sh [pasta da biblioteca Adafruit_NeoPixel]
# Precisa (Ubuntu): gcc-avr avr-libc arduino-core-avr simavr libsimavr-dev
#   libelf-dev e, para compilar IGUAL à IDE do Arduino, arduino-builder e
#   arduino-ctags (a IDE escreve sozinha as declarações das funções antes da
#   primeira função do .ino: um tipo declarado mais abaixo quebra a
#   compilação na IDE e só aparece compilando por ela).
set -e
AQUI=$(cd "$(dirname "$0")" && pwd)
SKETCH="$AQUI/../../../arduino/strike_kids/strike_kids.ino"
NEO=${1:-$HOME/Arduino/libraries/Adafruit_NeoPixel}
T=$(mktemp -d)
ELF=""
if command -v arduino-builder >/dev/null 2>&1; then
  mkdir -p "$T/libs" "$T/strike_kids"
  cp -r "$NEO" "$T/libs/Adafruit_NeoPixel"
  for alvo in "arduino:avr:nano:cpu=atmega328old 1" "arduino:avr:uno 1" "arduino:avr:mega:cpu=atmega2560 1" "arduino:avr:leonardo 1" "arduino:avr:nano:cpu=atmega328old 0"; do
    set -- $alvo
    rm -rf "$T/build"; mkdir -p "$T/build"
    sed "s/^#define USAR_LEDS [01]/#define USAR_LEDS $2/" "$SKETCH" > "$T/strike_kids/strike_kids.ino"
    echo "== IDE: $1 (LEDs=$2)"
    arduino-builder -compile -logger=human -warnings=all \
      -hardware /usr/share/arduino/hardware -hardware /usr/share/arduino-builder -tools /usr/bin \
      -built-in-libraries /usr/share/arduino/hardware/arduino/avr/libraries -libraries "$T/libs" \
      -fqbn "$1" -build-path "$T/build" "$T/strike_kids/strike_kids.ino" 2>&1 | grep -E "Sketch uses|error|warning: .*strike_kids" || true
    test -f "$T/build/strike_kids.ino.elf"
    if [ "$1" = "arduino:avr:uno" ]; then cp "$T/build/strike_kids.ino.elf" "$T/uno.elf"; ELF="$T/uno.elf"; fi
  done
else
  echo "(sem o arduino-builder: compilando direto, SEM o pré-processamento da IDE)"
  for p in nano mega leonardo; do
    echo "== $p"; "$AQUI/compilar.sh" $p "$T/$p.elf" 1 "$NEO"
  done
  echo "== uno sem LEDs"; "$AQUI/compilar.sh" uno "$T/uno0.elf" 0
  echo "== uno"; "$AQUI/compilar.sh" uno "$T/uno.elf" 1 "$NEO"
  ELF="$T/uno.elf"
fi
gcc -O2 -o "$T/sim" "$AQUI/sim_firmware.c" -lsimavr -lelf
"$T/sim" "$ELF"
rm -rf "$T"
