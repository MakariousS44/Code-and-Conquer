extends RefCounted

const DEV_WORKER_PATH := "res://sandbox_worker/bin/sandbox_runner.exe"
const PROTOCOL_VERSION := 1


func ping() -> Dictionary:
	var result := _run_worker(["--ping"])
	if not result.ok:
		return {"ok": false, "message": "Worker did not start: " + result.message}
	var response := _parse_json_response(result.output)
	if response.is_empty() or response.get("type", "") != "ready" or int(response.get("protocol", -1)) != PROTOCOL_VERSION:
		return {"ok": false, "message": "Worker returned an incompatible ready response."}
	return {"ok": true, "message": "Worker connected successfully."}


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


func _run_worker(arguments: Array) -> Dictionary:
	var worker_path := ProjectSettings.globalize_path(DEV_WORKER_PATH)
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
