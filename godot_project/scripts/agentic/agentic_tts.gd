## agentic_tts.gd
## Thin text-to-speech wrapper used by Agentic Mode to speak LLM feedback.
##
## Backends, in order of preference:
##   1. Web  : the browser Web Speech API via JavaScriptBridge (HTML5 export).
##   2. Native: Godot's built-in DisplayServer TTS (Windows/macOS/Linux) when
##              the platform reports TTS support.
##   3. None : silently no-ops (text is still shown on the AgenticHUD).
##
## TTS is best-effort and must never block the main thread or error out the sim.
class_name AgenticTTS
extends RefCounted

enum Backend { NONE, NATIVE, WEB }

var backend: Backend = Backend.NONE
var enabled: bool = true
var _voice_id: String = ""

func _init() -> void:
	_detect_backend()

## Detect the best available TTS backend for the current platform/export.
func _detect_backend() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		backend = Backend.WEB
		return
	# DisplayServer.tts_* is only meaningful when the feature is present.
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
		if voices.size() > 0:
			_voice_id = voices[0]
		backend = Backend.NATIVE
		return
	backend = Backend.NONE

## Speak [param text]. Interrupts any in-progress utterance. No-op when disabled
## or when no backend is available.
func speak(text: String) -> void:
	if not enabled or text.strip_edges().is_empty():
		return
	match backend:
		Backend.WEB:
			_speak_web(text)
		Backend.NATIVE:
			_speak_native(text)
		Backend.NONE:
			pass  # text-only feedback handled by the HUD

## Stop any active speech immediately.
func stop() -> void:
	match backend:
		Backend.WEB:
			if Engine.has_singleton("JavaScriptBridge"):
				JavaScriptBridge.eval("window.speechSynthesis && window.speechSynthesis.cancel();", true)
		Backend.NATIVE:
			DisplayServer.tts_stop()
		Backend.NONE:
			pass

func _speak_native(text: String) -> void:
	DisplayServer.tts_stop()
	# utterance id 0; rate 1.0 (normal). Voice may be "" (system default).
	DisplayServer.tts_speak(text, _voice_id, 50, 1.0, 1.0, 0, true)

func _speak_web(text: String) -> void:
	# Use the browser SpeechSynthesis API. JSON-encode the text so quotes and
	# newlines are escaped safely before interpolating into the JS snippet.
	var safe: String = JSON.stringify(text)
	var js: String = (
		"(function(){if(!('speechSynthesis' in window))return;"
		+ "window.speechSynthesis.cancel();"
		+ "var u=new SpeechSynthesisUtterance(%s);u.lang='en-US';"
		+ "window.speechSynthesis.speak(u);})();"
	) % safe
	JavaScriptBridge.eval(js, true)
