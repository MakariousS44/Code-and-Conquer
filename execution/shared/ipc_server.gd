extends RefCounted

var port: int = -1
var _server: TCPServer = null
var _peer: StreamPeerTCP = null
var _buf: String = ""
var _cancelled: bool = false

# Find an open port and start listening. Returns true on success.
func start() -> bool:
	_cancelled = false
	_server = TCPServer.new()
	for p in range(27015, 27115):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	return false

# Block (cooperatively) until the subprocess connects, or until timeout.
func wait_for_connection(tree: SceneTree) -> bool:
	var elapsed := 0.0
	while not _server.is_connection_available():
		if _cancelled:
			return false
		await tree.process_frame
		elapsed += tree.root.get_process_delta_time()
		if elapsed > 5.0:
			return false
	_peer = _server.take_connection()
	return _peer != null

# Read one newline-terminated message from the subprocess.
# Returns "[CANCELLED]" or "[DISCONNECT]" on stop/crash.
func read_line(tree: SceneTree) -> String:
	while not _cancelled:
		if _peer == null:
			return "[DISCONNECT]"
		_peer.poll()
		var status := _peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return "[DISCONNECT]"
		var available := _peer.get_available_bytes()
		if available > 0:
			_buf += _peer.get_utf8_string(available)
		var idx := _buf.find("\n")
		if idx != -1:
			var line := _buf.substr(0, idx).strip_edges()
			_buf = _buf.substr(idx + 1)
			return line
		await tree.process_frame
	return "[CANCELLED]"

func send(text: String) -> void:
	if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_peer.put_data((text + "\n").to_utf8_buffer())

# Unblock any in-progress read_line call.
func cancel() -> void:
	_cancelled = true

func stop() -> void:
	_cancelled = true
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	_buf = ""
