extends RefCounted

# Add all new commands here — both C++ and Python update automatically

# Command functions, alters player state
const COMMANDS := [
	{ "name": "move",        "cmd": "MOVE"        },
	{ "name": "turn_left",   "cmd": "TURN_LEFT"   },
	{ "name": "pick_object", "cmd": "PICK_OBJECT" },
	{ "name": "put_object",  "cmd": "PUT_OBJECT"  },
]

# Sensor functions, returns bool
const SENSORS := [
	{ "name": "front_is_clear",  "query": "FRONT_IS_CLEAR"  },
	{ "name": "right_is_clear",  "query": "RIGHT_IS_CLEAR"  },
	{ "name": "left_is_clear",   "query": "LEFT_IS_CLEAR"   },
	{ "name": "wall_in_front",   "query": "WALL_IN_FRONT"   },
	{ "name": "wall_on_right",   "query": "WALL_ON_RIGHT"   },
	{ "name": "wall_on_left",    "query": "WALL_ON_LEFT"    },
	{ "name": "at_goal",         "query": "AT_GOAL"         },
	{ "name": "object_here",     "query": "OBJECT_HERE"     },
	{ "name": "carries_object",  "query": "CARRIES_OBJECT"  },
	{ "name": "is_facing_north", "query": "IS_FACING_NORTH" },
	{ "name": "is_facing_east", "query": "IS_FACING_EAST" },
	{ "name": "is_facing_west", "query": "IS_FACING_WEST" },
]

## Socket bootstrap + a synthesized 'robot' module containing all commands and sensors.
func get_python_bootstrap(port: int) -> String:
	var lines := [
		"import socket as _socket, sys, traceback, types",
		"",
		"_sock = _socket.create_connection(('127.0.0.1', %d))" % port,
		"_sock_file = _sock.makefile('rwb', buffering=1)",
		"",
		"def _robot_send(msg):",
		"    _sock_file.write((msg + '\\n').encode())",
		"    _sock_file.flush()",
		"",
		"def _robot_recv():",
		"    return _sock_file.readline().decode().strip()",
		"",
		"# Route student print() through the socket to the output panel",
		"class _SockStdout:",
		"    def write(self, s):",
		"        for _line in s.splitlines():",
		"            if _line:",
		"                _robot_send('[PRINT] ' + _line)",
		"    def flush(self): pass",
		"sys.stdout = _SockStdout()",
		"",
		"# Build the 'robot' module dynamically and register it so student code",
		"_robot_mod = types.ModuleType('robot')",
		"_robot_exports = []",
		"",
		"def _mk_cmd(_cmd):",
		"    def _fn():",
		"        _f = traceback.extract_stack()[-2]",
		"        _robot_send('[CMD] ' + _cmd + ' [LINE] ' + str(_f.lineno))",
		"        _robot_recv()",
		"    return _fn",
		"",
		"def _mk_sensor(_query):",
		"    def _fn():",
		"        _f = traceback.extract_stack()[-2]",
		"        _robot_send('[QUERY] ' + _query + ' [LINE] ' + str(_f.lineno))",
		"        return _robot_recv() == 'true'",
		"    return _fn",
		"",
	]
	# Commands: send [CMD], wait for Godot's OK before continuing
	for cmd in COMMANDS:
		lines.append("setattr(_robot_mod, '%s', _mk_cmd('%s'))" % [cmd.name, cmd.cmd])
		lines.append("_robot_exports.append('%s')" % cmd.name)
	for sensor in SENSORS:
		lines.append("setattr(_robot_mod, '%s', _mk_sensor('%s'))" % [sensor.name, sensor.query])
		lines.append("_robot_exports.append('%s')" % sensor.name)
	lines.append("_robot_mod.__all__ = _robot_exports")
	lines.append("sys.modules['robot'] = _robot_mod")
	lines.append("")
	return "\n".join(lines)


## Error-catching wrapper around the student's code. Always sends [DONE].
func get_python_runner(student_code: String) -> String:
	var escaped := student_code.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
	return "\n".join([
		"_player_src = \"\"\"" + escaped + "\"\"\"",
		"try:",
		"    exec(compile(_player_src, '<player_code>', 'exec'))",
		"except SyntaxError as _e:",
		"    _robot_send('[ERROR] SyntaxError: ' + str(_e.msg) + ' (line ' + str(_e.lineno) + ')')",
		"except Exception as _e:",
		"    _tb = traceback.extract_tb(sys.exc_info()[2])",
		"    _pf = [f for f in _tb if f.filename == '<player_code>']",
		"    if _pf:",
		"        _robot_send('[ERROR] ' + type(_e).__name__ + ': ' + str(_e) + ' (line ' + str(_pf[-1].lineno) + ')')",
		"    else:",
		"        _robot_send('[ERROR] ' + type(_e).__name__ + ': ' + str(_e))",
		"finally:",
		"    _robot_send('[DONE]')",
		"    _sock.close()",
	])


## robot.hpp — forward declarations for all commands and sensors
func get_cpp_header() -> String:
	var lines := ["#pragma once", "#include <string>", ""]
	for cmd in COMMANDS:
		lines.append("void %s(int __src_line = 0);" % cmd.name)
	lines.append("")
	for sensor in SENSORS:
		lines.append("bool %s(int __src_line = 0);" % sensor.name)
	return "\n".join(lines)


## robot_runtime.cpp — cross-platform socket bootstrap + all implementations.
## Port is baked in at generation time so no runtime argument is needed.
func get_cpp_source(port: int) -> String:
	var lines := [
		"#include \"robot.hpp\"",
		"#include <string>",
		"#include <cstdint>",
		"",
		"#ifdef _WIN32",
		"#  ifndef _WIN32_WINNT",
		"#    define _WIN32_WINNT 0x0601",
		"#  endif",
		"#  define WIN32_LEAN_AND_MEAN",
		"#  include <winsock2.h>",
		"#  include <ws2tcpip.h>",
		"   typedef SOCKET __sock_t;",
		"#  define __sock_close(s) closesocket(s)",
		"#else",
		"#  include <sys/socket.h>",
		"#  include <arpa/inet.h>",
		"#  include <unistd.h>",
		"   typedef int __sock_t;",
		"#  define __sock_close(s) close(s)",
		"#endif",
		"",
		"static __sock_t __robot_sock;",
		"static std::string __robot_buf;",
		"",
		"static void __robot_connect() {",
		"#ifdef _WIN32",
		"    WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa);",
		"#endif",
		"    __robot_sock = socket(AF_INET, SOCK_STREAM, 0);",
		"    struct sockaddr_in addr{};",
		"    addr.sin_family      = AF_INET;",
		"    addr.sin_port        = htons(%d);" % port,
		"    addr.sin_addr.s_addr = inet_addr(\"127.0.0.1\");",
		"    connect(__robot_sock, (struct sockaddr*)&addr, sizeof(addr));",
		"}",
		"",
		"static void __robot_send(const std::string& msg) {",
		"    std::string line = msg + \"\\n\";",
		"    send(__robot_sock, line.c_str(), (int)line.size(), 0);",
		"}",
		"",
		"static std::string __robot_recv() {",
		"    while (true) {",
		"        auto pos = __robot_buf.find('\\n');",
		"        if (pos != std::string::npos) {",
		"            std::string line = __robot_buf.substr(0, pos);",
		"            __robot_buf = __robot_buf.substr(pos + 1);",
		"            if (!line.empty() && line.back() == '\\r') line.pop_back();",
		"            return line;",
		"        }",
		"        char tmp[256];",
		"        int n = recv(__robot_sock, tmp, sizeof(tmp), 0);",
		"        if (n <= 0) return \"\";",
		"        __robot_buf.append(tmp, n);",
		"    }",
		"}",
		"",
		"struct __RobotLifetime {",
		"    __RobotLifetime()  { __robot_connect(); }",
		"    ~__RobotLifetime() { __robot_send(\"[DONE]\"); __sock_close(__robot_sock); }",
		"} __robot_lifetime;",
		"",
	]
	for cmd in COMMANDS:
		lines.append("void %s(int __src_line) {" % cmd.name)
		lines.append("    __robot_send(\"[CMD] %s [LINE] \" + std::to_string(__src_line));" % cmd.cmd)
		lines.append("    __robot_recv();")
		lines.append("}")
		lines.append("")
	for sensor in SENSORS:
		lines.append("bool %s(int __src_line) {" % sensor.name)
		lines.append("    __robot_send(\"[QUERY] %s [LINE] \" + std::to_string(__src_line));" % sensor.query)
		lines.append("    return __robot_recv() == \"true\";")
		lines.append("}")
		lines.append("")
	return "\n".join(lines)


## Preprocessor macros so the student writes move() and __LINE__ is injected automatically
func get_cpp_macros() -> String:
	var lines := []
	for cmd in COMMANDS:
		lines.append("#define %s() %s(__LINE__)" % [cmd.name, cmd.name])
	for sensor in SENSORS:
		lines.append("#define %s() %s(__LINE__)" % [sensor.name, sensor.name])
	return "\n".join(lines)
