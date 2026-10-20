@tool
extends EditorPlugin

## Leva o plugin Android da câmera (bin/StrikeCamera.aar) para dentro do APK,
## com a libuvc (AndroidUSBCamera, a mesma do jogo de soco) para abrir a
## webcam direto pelo USB nas TV Box que não a publicam no Android.
## Fonte Java: tools/android/StrikeCamera (sh construir.sh refaz o .aar).
## Precisa do build Gradle (o GERAR_APK.ps1 já liga sozinho). Com a variável
## de ambiente STRIKE_SEM_UVC=1 o APK sai sem a libuvc (o GERAR_APK tenta
## assim se o JitPack falhar: câmera do sistema e Camera2 continuam).

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = StrikeCameraExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class StrikeCameraExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "StrikeCamera"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["StrikeCamera/bin/StrikeCamera.aar"])

	func _sem_uvc() -> bool:
		return OS.get_environment("STRIKE_SEM_UVC") == "1"

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if _sem_uvc():
			return PackedStringArray()
		return PackedStringArray(["com.github.jiangdongguo.AndroidUSBCamera:libuvc:3.2.7"])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if _sem_uvc():
			return PackedStringArray()
		return PackedStringArray(["https://jitpack.io"])
