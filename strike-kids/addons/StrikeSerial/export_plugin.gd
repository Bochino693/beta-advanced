@tool
extends EditorPlugin

## Leva o plugin Android do Arduino (bin/StrikeSerial.aar) para dentro do
## APK: a USB serial dos 5 sensores, do botão de configuração e da trava.
## Driver próprio (CDC, CH340, FTDI, CP210x): não baixa nada de fora.
## Fonte Java: tools/android/StrikeSerial (sh construir.sh refaz o .aar).
## Precisa do build Gradle (o GERAR_APK.ps1 já liga sozinho).

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = StrikeSerialExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class StrikeSerialExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "StrikeSerial"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["StrikeSerial/bin/StrikeSerial.aar"])
