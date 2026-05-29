## agentic_voice.gd
## Speech-to-text helper for voice-first interaction (Phase 5.2).
##
## Backends, in order of preference:
##   1. Web    : the browser SpeechRecognition API via JavaScriptBridge. The
##               recognised text is polled from a JS variable each frame.
##   2. Desktop: a local speech-to-text tool invoked with OS.execute (default:
##               whisper.cpp). The user configures the command + how it captures
##               audio. See docs/agentic_mode.md "Voice setup".
##   3. None   : push-to-talk is unavailable; callers fall back to typed input.
##
## Recognition is best-effort and must never block the main thread. On desktop
## the external tool is run on a worker Thread so the sim keeps rendering.
class_name AgenticVoice
extends RefCounted

enum Backend { NONE, NATIVE, WEB }

signal recognized(text: String)
signal listening_changed(active: bool)

var backend: Backend = Backend.NONE
var listening: bool = false

## Desktop STT command template. {out} is replaced with a temp wav path the
## tool should transcribe; stdout is taken as the recognised text. Users adjust
## this to their installed tool (whisper.cpp, vosk, etc.) in settings.
var desktop_cmd: String = "whisper-cli"
var desktop_args: PackedStringArray = ["-f", "{out}", "-otxt", "-nt"]

var _thread: Thread = null

func _init() -> void:
	_detect_backend()

func _detect_backend() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		backend = Backend.WEB
		_install_web_bridge()
		return
	# Desktop: assume a local STT tool *may* exist; the actual call is guarded.
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		backend = Backend.NATIVE
		return
	backend = Backend.NONE

## Whether voice recognition is usable on this platform/build.
func is_available() -> bool:
	return backend != Backend.NONE

# ---------------------------------------------------------------------------
# Push-to-talk control
# ---------------------------------------------------------------------------
## Begin listening (called on push-to-talk press).
func start_listening() -> void:
	if listening or backend == Backend.NONE:
		return
	listening = true
	listening_changed.emit(true)
	if backend == Backend.WEB:
		JavaScriptBridge.eval("window.__rcfs_voice && window.__rcfs_voice.start();", true)

## Stop listening (called on release). On web the recognised text is read back;
## on desktop transcription of the captured clip begins.
func stop_listening() -> void:
	if not listening:
		return
	listening = false
	listening_changed.emit(false)
	match backend:
		Backend.WEB:
			_finish_web()
		Backend.NATIVE:
			_finish_desktop()
		Backend.NONE:
			pass

# ---------------------------------------------------------------------------
# Web backend
# ---------------------------------------------------------------------------
func _install_web_bridge() -> void:
	# Sets up a tiny SpeechRecognition wrapper that stashes the last transcript
	# on window.__rcfs_voice.result for GDScript to poll.
	var js := """
	(function(){
	  if(window.__rcfs_voice) return;
	  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
	  if(!SR){ window.__rcfs_voice = {start:function(){},result:'',supported:false}; return; }
	  var r = new SR(); r.lang='en-US'; r.interimResults=false; r.maxAlternatives=1;
	  var state = {start:function(){this.result=''; try{r.start();}catch(e){}}, result:'', supported:true};
	  r.onresult=function(e){ state.result = e.results[0][0].transcript; };
	  window.__rcfs_voice = state;
	})();
	"""
	JavaScriptBridge.eval(js, true)

func _finish_web() -> void:
	var text: Variant = JavaScriptBridge.eval("window.__rcfs_voice ? window.__rcfs_voice.result : '';", true)
	var transcript := String(text).strip_edges()
	if transcript != "":
		recognized.emit(transcript)

# ---------------------------------------------------------------------------
# Desktop backend (local STT tool on a worker thread)
# ---------------------------------------------------------------------------
func _finish_desktop() -> void:
	# Audio capture itself requires an external recorder; we transcribe the most
	# recent clip the user's tool produced. The command is fully user-configured
	# so we never assume a specific binary is installed.
	if _thread != null and _thread.is_alive():
		return
	_thread = Thread.new()
	_thread.start(_run_desktop_stt)

func _run_desktop_stt() -> void:
	var out_path := OS.get_user_data_dir().path_join("voice_capture.wav")
	var args: PackedStringArray = []
	for a in desktop_args:
		args.append(a.replace("{out}", out_path))
	var output: Array = []
	var code := OS.execute(desktop_cmd, args, output, true)
	var transcript := ""
	if code == 0 and output.size() > 0:
		transcript = String(output[0]).strip_edges()
	call_deferred("_emit_desktop_result", transcript)

func _emit_desktop_result(transcript: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if transcript != "":
		recognized.emit(transcript)
