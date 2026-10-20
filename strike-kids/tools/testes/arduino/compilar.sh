#!/bin/bash
# Compila o firmware do Arduino (arduino/strike_kids) direto com o avr-gcc
# (núcleo AVR + bibliotecas + sketch), SEM o pré-processamento da IDE (as
# declarações automáticas das funções): o rodar.sh usa o arduino-builder,
# que faz igual à IDE, quando ele está instalado. Serve para conferir
# que compila em cada placa e para o simulador (simavr).
#   compilar.sh <placa: uno|nano|mega|leonardo> <saida.elf> <USAR_LEDS 0|1> [pasta da Adafruit_NeoPixel]
# Precisa de: gcc-avr, avr-libc, arduino-core-avr (pacotes do Ubuntu).
set -e
PLACA=$1; SAIDA=$2; LEDS=${3:-1}; NEO=$4
AQUI=$(cd "$(dirname "$0")" && pwd)
SKETCH="$AQUI/../../../arduino/strike_kids/strike_kids.ino"
HW=/usr/share/arduino/hardware/arduino/avr
case $PLACA in
  uno)      MCU=atmega328p; VAR=standard; DEF="-DARDUINO_AVR_UNO" ;;
  nano)     MCU=atmega328p; VAR=eightanaloginputs; DEF="-DARDUINO_AVR_NANO" ;;
  mega)     MCU=atmega2560; VAR=mega; DEF="-DARDUINO_AVR_MEGA2560" ;;
  leonardo) MCU=atmega32u4; VAR=leonardo; DEF="-DARDUINO_AVR_LEONARDO -DUSB_VID=0x2341 -DUSB_PID=0x8036 -DUSB_MANUFACTURER='\"Arduino\"' -DUSB_PRODUCT='\"Leonardo\"'" ;;
  *) echo "placa?"; exit 1 ;;
esac
T=$(mktemp -d)
COMUM="-mmcu=$MCU -DF_CPU=16000000L -DARDUINO=10808 -DARDUINO_ARCH_AVR $DEF -I$HW/cores/arduino -I$HW/variants/$VAR -I$HW/libraries/EEPROM/src -Os -g -ffunction-sections -fdata-sections -flto"
INC=""
if [ "$LEDS" = "1" ]; then INC="-I$NEO"; fi
OBJS=""
for f in $HW/cores/arduino/*.c; do eval avr-gcc -c -w -std=gnu11 $COMUM -o "$T/$(basename $f).o" "$f"; OBJS="$OBJS $T/$(basename $f).o"; done
for f in $HW/cores/arduino/*.cpp; do eval avr-g++ -c -w -std=gnu++11 -fpermissive -fno-exceptions -fno-threadsafe-statics $COMUM -o "$T/$(basename $f).o" "$f"; OBJS="$OBJS $T/$(basename $f).o"; done
for f in $HW/cores/arduino/*.S; do [ -f "$f" ] && eval avr-gcc -c -x assembler-with-cpp $COMUM -o "$T/$(basename $f).o" "$f" && OBJS="$OBJS $T/$(basename $f).o"; done
if [ "$LEDS" = "1" ]; then
  eval avr-g++ -c -w -std=gnu++11 -fpermissive -fno-exceptions -fno-threadsafe-statics $COMUM -o "$T/neo.o" "$NEO/Adafruit_NeoPixel.cpp"
  OBJS="$OBJS $T/neo.o"
fi
{ echo '#include <Arduino.h>'; echo '#line 1 "strike_kids.ino"'; sed "s/^#define USAR_LEDS [01]/#define USAR_LEDS $LEDS/" "$SKETCH"; } > "$T/strike_kids.cpp"
eval avr-g++ -c -Wall -Wextra -Wno-unused-parameter -std=gnu++11 -fpermissive -fno-exceptions -fno-threadsafe-statics $COMUM $INC -o "$T/sketch.o" "$T/strike_kids.cpp"
avr-gcc -w -Os -g -flto -fuse-linker-plugin -Wl,--gc-sections -mmcu=$MCU -o "$SAIDA" "$T/sketch.o" $OBJS -lm
avr-size -C --mcu=$MCU "$SAIDA" | grep -E "Program|Data"
rm -rf "$T"
