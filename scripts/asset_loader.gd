extends RefCounted
class_name GameAssets
# Ch31 - Aide au chargement des ressources.
# - load_resource() : profite d'un chargement threadé déjà lancé (par le splash) sans conflit :
#   bloque proprement si le chargement est en cours, sinon charge en synchrone (cache inclus).
# - make_looping() : rend un flux audio bouclé, WAV ou OGG, sans muter la ressource en cache.

static func load_resource(path: String) -> Resource:
        var status := ResourceLoader.load_threaded_get_status(path)
        if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED:
                return ResourceLoader.load_threaded_get(path)
        if ResourceLoader.exists(path):
                return load(path)
        return null

static func make_looping(stream: AudioStream) -> AudioStream:
        if stream == null:
                return null
        if stream is AudioStreamWAV:
                var wav: AudioStreamWAV = (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
                wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
                wav.loop_begin = 0
                wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
                return wav
        if stream is AudioStreamOggVorbis:
                var ogg: AudioStreamOggVorbis = (stream as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
                ogg.loop = true
                return ogg
        return stream
