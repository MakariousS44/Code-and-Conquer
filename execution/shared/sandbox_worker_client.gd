extends RefCounted

const PROTOCOL_VERSION := 2

var _runtime_assets = preload("res://execution/shared/runtime_assets.gd").new()


func ping() -> Dictionary:
	var result := _run_worker(["--ping"])
	if not result.ok:
		return {"ok": false, "message": "Worker did not start: " + result.message}
	var response := _parse_json_response(result.output)
	if response.is_empty() or response.get("type", "") != "ready" or int(response.get("protocol", -1)) != PROTOCOL_VERSION:
		return {"ok": false, "message": "Worker returned an incompatible ready response."}
	return {"ok": true, "message": "Worker connected successfully."}

func start_cpp_runner(
	run_id: String,
	cleanup_token: String,
	godot_port: int,
	ipc_token: String
) -> Dictionary:
	var worker_path := _worker_path()
	if worker_path.is_empty():
		return {"ok": false, "message": "Unsupported OS or architecture for the sandbox worker."}

	var pid := OS.create_process(
		worker_path,
		[
			"--run-cpp",
			run_id,
			cleanup_token,
			str(godot_port),
			ipc_token
		]
	)

	if pid == -1:
		return {
			"ok": false,
			"message": "Could not start the sandbox worker."
		}

	return {
		"ok": true,
		"pid": pid
	}

func start_python_runner(
	run_id: String,
	cleanup_token: String,
	godot_port: int,
	ipc_token: String
) -> Dictionary:
	var worker_path := _worker_path()
	if worker_path.is_empty():
		return {"ok": false, "message": "Unsupported OS or architecture for the sandbox worker."}

	var pid := OS.create_process(
		worker_path,
		[
			"--run-python",
			run_id,
			cleanup_token,
			str(godot_port),
			ipc_token
		]
	)

	if pid == -1:
		return {
			"ok": false,
			"message": "Could not start the secure Python runner."
		}

	return {
		"ok": true,
		"pid": pid
	}


func prepare_run(run_id: String, cleanup_token: String) -> Dictionary:
	var result := _run_worker(["--prepare-run", run_id, cleanup_token])
	if not result.ok:
		return {"ok": false, "message": result.message}

	var response := _parse_json_response(result.output)
	if response.get("type", "") != "sandbox_ready":
		return {"ok": false, "message": "Worker returned an invalid sandbox response."}

	var run_path := str(response.get("path", ""))
	if run_path.is_empty():
		return {"ok": false, "message": "Worker did not provide a sandbox directory."}

	return {"ok": true, "path": run_path}

func prepare_python_run(run_id: String, cleanup_token: String, python_runtime_path: String) -> Dictionary:
	if python_runtime_path.is_empty():
		return {"ok": false, "message": "The bundled Python runtime is unavailable for this platform."}
	var result := _run_worker(["--prepare-python-run", run_id, cleanup_token, python_runtime_path])

	if not result.ok:
		return {"ok": false, "message": result.message}

	var response := _parse_json_response(result.output)

	if response.get("type", "") != "sandbox_ready":
		return {
			"ok": false,
			"message": "Worker returned an invalid Python sandbox response."
		}

	var run_path := str(response.get("path", ""))

	if run_path.is_empty():
		return {
			"ok": false,
			"message": "Worker did not provide a Python sandbox directory."
		}

	return {"ok": true, "path": run_path}


func create_run_directory(run_id: String, cleanup_token: String) -> Dictionary:
	var result := _run_worker(["--make-run-dir", run_id, cleanup_token])
	if not result.ok:
		return {"ok": false, "message": result.message}
	var response := _parse_json_response(result.output)
	if response.get("type", "") != "run_directory" or str(response.get("path", "")).is_empty():
		return {"ok": false, "message": "Worker returned an invalid run-directory response."}
	return {"ok": true, "path": str(response["path"])}


func delete_run_directory(run_id: String, cleanup_token: String) -> Dictionary:
	var result := _run_worker(["--delete-run-dir", run_id, cleanup_token])
	if not result.ok:
		return {"ok": false, "message": result.message}
	var response := _parse_json_response(result.output)
	if response.get("type", "") != "cleanup_complete":
		return {"ok": false, "message": "Worker returned an invalid cleanup response."}
	return {"ok": true}


func _worker_path() -> String:
	return _runtime_assets.worker_payload_path()


func _run_worker(arguments: Array) -> Dictionary:
	var worker_path := _worker_path()
	if worker_path.is_empty():
		return {"ok": false, "message": "Sandbox worker is unavailable for this OS or architecture."}
	if not FileAccess.file_exists(worker_path):
		return {"ok": false, "message": "Worker executable was not found: " + worker_path}
	var output: Array = []
	var exit_code := OS.execute(worker_path, arguments, output, true)
	var response_text := "" if output.is_empty() else str(output[0]).strip_edges()
	if exit_code != 0:
		return {"ok": false, "message": response_text if not response_text.is_empty() else "Worker exited with code %d." % exit_code}
	return {"ok": true, "output": response_text}


func _parse_json_response(response_text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(response_text) != OK or not (json.data is Dictionary):
		return {}
	return json.data
