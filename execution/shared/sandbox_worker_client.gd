extends RefCounted

const DEV_WORKER_PATH := "res://sandbox_worker/bin/sandbox_runner.exe"

func ping() -> Dictionary:
    var worker_path := ProjectSettings.globalize_path(DEV_WORKER_PATH)
    
    if not FileAccess.file_exists(worker_path):
        return {
            "ok": false,
            "message": "Worker executable was not found: " + worker_path
        }

    var output : Array = []
    var exit_code := OS.execute(worker_path, ["--ping"], output, true)
    var response_text := "" if output.is_empty() else str(output[0]).strip_edges()

    if exit_code != 0:
        return {
            "ok": false,
            "message": "Worker returned an unexpected response: " + response_text
        }

    return {
        "ok": true,
        "message": "Woker connected successfully."
    }