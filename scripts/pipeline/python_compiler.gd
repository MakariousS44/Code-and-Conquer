## PythonCompiler.gd
## Wraps, executes, and captures output from player-written Python code.
## Uses the system Python interpreter (works on Linux and Windows).
##
## Usage:
##   var compiler := python_compiler.new()
##   var result   := compiler.run(player_code)
##   print(result.stdout)   # captured print() output
##   print(result.stderr)   # error message if any
##   print(result.success)  # bool

class_name python_compiler


class RunResult:
	var success:   bool   ## True if the code exited with code 0 and no errors
	var stdout:    String ## Everything printed to stdout
	var stderr:    String ## Exception / syntax error message
	var exit_code: int    ## Raw process exit code

	func _init(ok: bool, out: String, err: String, code: int) -> void:
		success   = ok
		stdout    = out
		stderr    = err
		exit_code = code


## Set this before calling run() to inject game API functions
## (e.g. move_forward(), turn_left()) into the player's environment.
var api_source: String = ""

## Indentation used when wrapping the player's code inside a function.
const INDENT := "    "



## Execute player_code using the system Python interpreter.
## Returns a RunResult.
func run(player_code: String) -> RunResult:
	var python := _find_python()
	if python.is_empty():
		return RunResult.new(
			false, "",
			"RuntimeError: No Python interpreter found on this system.\n"
			+ "Please install Python 3 and make sure it is on your PATH.",
			-1)

	var script   := _wrap(player_code)
	var tmp_path := OS.get_temp_dir().path_join("_player_code.py")

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return RunResult.new(
			false, "",
			"RuntimeError: Could not write file: " + tmp_path + "\nError: " + str(FileAccess.get_open_error()),
			-1)
	file.store_string(script)
	file.close()

	var stdout_lines: Array = []
	var exit_code := OS.execute(python, [tmp_path], stdout_lines, true)

	var raw_output := ""
	if stdout_lines.size() > 0:
		raw_output = stdout_lines[0]

	return _parse_output(raw_output, exit_code)


## Try common Python executable names and return the first that works.
## Tries python3 first (Linux/macOS), then python (Windows).
func _find_python() -> String:
	var candidates: Array = ["python3", "python"]
	for candidate in candidates:
		var out: Array = []
		var code := OS.execute(candidate, ["--version"], out, true)
		if code == 0:
			return candidate
	return ""


# Code Wrapping

func _wrap(player_code: String) -> String:
	var escaped := player_code.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')

	return """\
import sys, traceback

# Game API injected by Godot
{api}

class _Capture:
    def __init__(self): self._buf = []
    def write(self, s): self._buf.append(s)
    def flush(self): pass
    def getvalue(self): return ''.join(self._buf)

_stdout_cap = _Capture()
_stderr_cap = _Capture()
sys.stdout  = _stdout_cap
sys.stderr  = _stderr_cap

_player_source = \"\"\"{player_code}\"\"\"

try:
    _compiled = compile(_player_source, '<player_code>', 'exec')
    exec(_compiled)
except SyntaxError as _e:
    sys.stderr.write("SyntaxError: {msg} (line {line})\\n".format(
        msg  = _e.msg,
        line = _e.lineno
    ))
except Exception as _e:
    tb = traceback.extract_tb(sys.exc_info()[2])
    player_frames = [f for f in tb if f.filename == '<player_code>']
    if player_frames:
        frame = player_frames[-1]
        sys.stderr.write("{error}: {msg} (line {line})\\n".format(
            error = type(_e).__name__,
            msg   = str(_e),
            line  = frame.lineno
        ))
    else:
        sys.stderr.write("{error}: {msg}\\n".format(
            error = type(_e).__name__,
            msg   = str(_e)
        ))

sys.stdout = sys.__stdout__
sys.stderr = sys.__stderr__
print(_stdout_cap.getvalue(), end='')
print('__STDERR_START__')
print(_stderr_cap.getvalue(), end='')
""".format({
		"api":         api_source if not api_source.is_empty() else "pass  # no API",
		"player_code": escaped,
	})


# Output parsing

## Split the combined process output on the sentinel line
## to recover separate stdout and stderr strings.
func _parse_output(raw: String, exit_code: int) -> RunResult:
	const SENTINEL := "__STDERR_START__"
	var parts := raw.split(SENTINEL, true, 1)

	var stdout_text := parts[0] if parts.size() > 0 else ""
	var stderr_text := parts[1].lstrip("\n") if parts.size() > 1 else ""

	# Strip \r\n so Windows line endings don't cause a false error
	stderr_text = stderr_text.strip_edges()
	stdout_text = stdout_text.replace("\r\n", "\n").strip_edges()

	var ok := exit_code == 0 and stderr_text.is_empty()
	return RunResult.new(ok, stdout_text, stderr_text, exit_code)
