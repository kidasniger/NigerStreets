@tool
extends EditorExportPlugin
# Niger Streets — meta-data du plugin Android « UpdateInstaller ».
# Godot génère le manifeste final (src/release/AndroidManifest.xml) à chaque
# export ; le hook ci-dessous ajoute la balise meta-data DANS ce manifeste, donc
# elle arrive toujours dans l'APK. À l'exécution, Godot Android la lit pour
# instancier le GodotPlugin et exposer le singleton « UpdateInstaller » à
# GDScript (installation d'APK dans l'appli : téléchargement → intent système →
# suppression du fichier, comme MusicPro).

const DEFAULT_PACKAGE := "com.godot.game"

func _get_name() -> String:
	return "NigerStreetsManifestExport"

## Package réel du template : relu depuis GodotApp.java (recopié et re-packagé
## par scripts/setup_android_plugin.sh) pour rester en phase avec la classe compilée.
func _plugin_class() -> String:
	var app_java := "res://android/build/src/main/java/com/godot/game/GodotApp.java"
	if FileAccess.file_exists(app_java):
		var txt := FileAccess.get_file_as_string(app_java)
		var idx := txt.find("package ")
		if idx >= 0:
			var end := txt.find(";", idx)
			if end > idx:
				var pkg := txt.substr(idx + 8, end - idx - 8).strip_edges()
				if not pkg.is_empty():
					return pkg + ".UpdateInstaller"
	return DEFAULT_PACKAGE + ".UpdateInstaller"

func _get_android_manifest_application_element_contents(_platform, _debug) -> String:
	return "\n        <meta-data android:name=\"org.godotengine.plugin.v2.UpdateInstaller\" android:value=\"%s\" />\n" % _plugin_class()
