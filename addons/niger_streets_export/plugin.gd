@tool
extends EditorPlugin
# Enregistre l'export plugin NigerStreets : il injecte le meta-data du plugin
# Android « UpdateInstaller » dans le manifeste que Godot écrit lui-même à chaque
# export (android/build/src/release/AndroidManifest.xml). Le patch direct du
# template src/main était écrasé par Godot au moment du build gradle — d'où le
# repli navigateur à la place de l'installation dans l'appli (voir update_checker.gd).

var _manifest_plugin := preload("res://addons/niger_streets_export/manifest_export.gd").new()

func _enter_tree() -> void:
	add_export_plugin(_manifest_plugin)
