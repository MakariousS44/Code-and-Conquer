#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <poll.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <utility>
#include <vector>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/prctl.h>
#endif

namespace fs = std::filesystem;

constexpr const char* TOKEN_FILE = ".cleanup-token";
constexpr const char* SOCKET_NAME = "student.sock";
constexpr int PROTOCOL_VERSION = 2;

static pid_t g_child_pid = -1;
static volatile sig_atomic_t g_stop_requested = 0;

static void on_signal(int) {
	g_stop_requested = 1;
	if (g_child_pid > 0) {
		kill(-g_child_pid, SIGKILL);
	}
}

std::string json_escape(const std::string& value) {
    std::string escaped;
    for (unsigned char character : value) {
        switch (character) {
            case '\\': escaped += "\\\\"; break;
            case '"': escaped += "\\\""; break;
            case '\b': escaped += "\\b"; break;
            case '\f': escaped += "\\f"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:
                if (character < 0x20) {
                    std::ostringstream code;
                    code << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(character);
                    escaped += code.str();
                } else {
                    escaped += static_cast<char>(character);
                }
        }
    }
    return escaped;
}

bool is_safe_identifier(const std::string& value) {
    if (value.empty() || value.size() > 128) return false;
    for (unsigned char character : value) {
        if (!(std::isalnum(character) || character == '-' || character == '_')) return false;
    }
    return true;
}

void ensure_real_directory(const fs::path& directory) {
    std::error_code error;
    const auto status = fs::symlink_status(directory, error);
    if (error && error != std::errc::no_such_file_or_directory) throw std::runtime_error("Could not inspect a sandbox directory.");
    if (!error && (fs::is_symlink(status) || !fs::is_directory(status))) throw std::runtime_error("Sandbox directory is unsafe.");
    if (!fs::exists(directory) && !fs::create_directory(directory, error)) throw std::runtime_error("Could not create a sandbox directory.");
    const auto final_status = fs::symlink_status(directory, error);
    if (error || fs::is_symlink(final_status) || !fs::is_directory(final_status)) throw std::runtime_error("Sandbox directory is unsafe.");
}

void make_private(const fs::path& path) {
    std::error_code error;
    fs::permissions(path, fs::perms::owner_all, fs::perm_options::replace, error);
    if (error) throw std::runtime_error("Could not secure sandbox permissions: " + error.message());
}

fs::path ensure_private_root() {
    const fs::path root = fs::path("/tmp") / ("CodeAndConquer-" + std::to_string(static_cast<long long>(getuid()))) / "sandbox-runs";
    ensure_real_directory(root.parent_path());
    make_private(root.parent_path());
    std::error_code error;
    ensure_real_directory(root);
    make_private(root);
    return fs::canonical(root, error);
}

fs::path run_directory_for(const std::string& run_id) {
    if (!is_safe_identifier(run_id)) throw std::runtime_error("Invalid run identifier.");
    return ensure_private_root() / ("run-" + run_id);
}

bool token_matches(const fs::path& run_directory, const std::string& token) {
    std::ifstream input(run_directory / TOKEN_FILE, std::ios::binary);
    std::string stored_token;
    std::getline(input, stored_token);
    return input.good() && stored_token == token;
}

fs::path make_run_directory(const std::string& run_id, const std::string& token) {
    if (!is_safe_identifier(token)) throw std::runtime_error("Invalid cleanup token.");
    const fs::path run_directory = run_directory_for(run_id);
    std::error_code error;
    if (fs::exists(run_directory, error)) {
        if (error || fs::is_symlink(fs::symlink_status(run_directory, error)) || !fs::is_directory(run_directory) || !token_matches(run_directory, token)) {
            throw std::runtime_error("Run directory already exists but is not owned by this request.");
        }
        return run_directory;
    }
    if (!fs::create_directory(run_directory, error) || error) throw std::runtime_error("Could not create the sandbox run directory.");
    make_private(run_directory);
    const fs::path token_file = run_directory / TOKEN_FILE;
    std::ofstream output(token_file, std::ios::binary | std::ios::trunc);
    output << token << '\n';
    output.close();
    if (!output) {
        fs::remove_all(run_directory, error);
        throw std::runtime_error("Could not initialize the sandbox run directory.");
    }
    std::error_code permission_error;
    fs::permissions(token_file, fs::perms::owner_read | fs::perms::owner_write, fs::perm_options::replace, permission_error);
    if (permission_error) throw std::runtime_error("Could not secure the sandbox token file.");
    return run_directory;
}

fs::path find_python_executable(const fs::path& run_directory) {
    const fs::path python_root = run_directory / "python";
    const std::vector<std::string> candidates = {
        "bin/python3",
        "bin/python3.14",
        "bin/python3.13",
        "bin/python3.12",
        "bin/python3.11",
        "bin/python",
        "python3",
        "python"
    };
    for (const auto& candidate : candidates) {
        const fs::path executable = python_root / candidate;
        std::error_code error;
        if (fs::is_regular_file(executable, error) && !error) return executable;
    }
    const fs::path bin = python_root / "bin";
    std::error_code error;
    if (fs::is_directory(bin, error)) {
        for (const auto& entry : fs::directory_iterator(bin, error)) {
            const std::string name = entry.path().filename().string();
            if (name.rfind("python3", 0) == 0 && fs::is_regular_file(entry.path())) return entry.path();
        }
    }
    return {};
}

void copy_python_runtime_to_run(const fs::path& run_directory, const fs::path& runtime_source) {
    std::error_code error;
    if (!fs::is_directory(runtime_source, error)) {
        throw std::runtime_error("Bundled Python runtime was not found: " + runtime_source.string());
    }
    const fs::path runtime_destination = run_directory / "python";
    fs::copy(runtime_source, runtime_destination, fs::copy_options::recursive, error);
    if (error) {
        throw std::runtime_error("Could not copy the Python runtime into the secure run folder. Error: " + error.message());
    }
    if (find_python_executable(run_directory).empty()) {
        throw std::runtime_error("Python was copied, but no python3 executable was found in the secure run folder.");
    }
}

void delete_run_directory(const std::string& run_id, const std::string& token) {
    if (!is_safe_identifier(token)) throw std::runtime_error("Invalid cleanup token.");
    const fs::path root = ensure_private_root();
    const fs::path target = run_directory_for(run_id);
    std::error_code error;
    const auto status = fs::symlink_status(target, error);
    if (error || fs::is_symlink(status) || !fs::is_directory(target) || target.parent_path() != root || !token_matches(target, token)) {
        throw std::runtime_error("Refusing to delete a run directory not owned by this request.");
    }
    fs::remove_all(target, error);
    if (error) throw std::runtime_error("Could not delete the sandbox run directory.");
}

void send_all(int socket_fd, const std::string& text) {
    size_t sent_total = 0;
    while (sent_total < text.size()) {
        const ssize_t sent = send(socket_fd, text.data() + sent_total, text.size() - sent_total, 0);
        if (sent <= 0) {
            if (sent < 0 && errno == EINTR) continue;
            throw std::runtime_error("Could not send a message.");
        }
        sent_total += static_cast<size_t>(sent);
    }
}

std::string receive_line(int socket_fd) {
    std::string result;
    char character = '\0';
    while (result.size() < 8192) {
        const ssize_t received = recv(socket_fd, &character, 1, 0);
        if (received < 0 && errno == EINTR) continue;
        if (received <= 0) {
            throw std::runtime_error("Could not receive a reply.");
        }
        if (character == '\n') return result;
        if (character != '\r') result += character;
    }
    throw std::runtime_error("Reply exceeded the size limit.");
}

std::string receive_message(int socket_fd) {
    std::string result;
    char character = '\0';
    while (result.size() < 8192) {
        const ssize_t received = recv(socket_fd, &character, 1, 0);
        if (received < 0 && errno == EINTR) continue;
        if (received <= 0) {
            if (result.empty()) return "";
            throw std::runtime_error("Student message was truncated.");
        }
        if (character == '\n') return result;
        if (character != '\r') result += character;
    }
    throw std::runtime_error("Student message exceeded the size limit.");
}

int connect_worker_to_godot(int port, const std::string& ipc_token) {
    int socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_fd < 0) throw std::runtime_error("Could not create the Godot IPC socket.");

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<uint16_t>(port));
    address.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(socket_fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        close(socket_fd);
        throw std::runtime_error("Could not connect the worker to Godot IPC.");
    }
    send_all(socket_fd, "[AUTH] " + ipc_token + "\n");
    return socket_fd;
}

struct UnixListener {
    int fd = -1;
    fs::path path;
    ~UnixListener() {
        if (fd >= 0) close(fd);
        if (!path.empty()) {
            std::error_code ignored;
            fs::remove(path, ignored);
        }
    }
};

UnixListener create_unix_listener(const fs::path& run_directory) {
    UnixListener listener;
    listener.path = run_directory / SOCKET_NAME;
    std::error_code error;
    fs::remove(listener.path, error);

    listener.fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener.fd < 0) throw std::runtime_error("Could not create the student Unix socket.");
    fcntl(listener.fd, F_SETFD, FD_CLOEXEC);

    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    const std::string path_string = listener.path.string();
    if (path_string.size() >= sizeof(address.sun_path)) {
        close(listener.fd);
        throw std::runtime_error("Student IPC socket path is too long.");
    }
    std::strncpy(address.sun_path, path_string.c_str(), sizeof(address.sun_path) - 1);

    if (bind(listener.fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        const int bind_error = errno;
        close(listener.fd);
        listener.fd = -1;
        throw std::runtime_error("Could not bind the student Unix socket. Error: " + std::to_string(bind_error));
    }
    if (chmod(listener.path.c_str(), S_IRUSR | S_IWUSR) != 0) {
        close(listener.fd);
        listener.fd = -1;
        throw std::runtime_error("Could not secure the student Unix socket.");
    }
    if (listen(listener.fd, 1) != 0) {
        close(listener.fd);
        listener.fd = -1;
        throw std::runtime_error("Could not listen on the student Unix socket.");
    }
    return listener;
}

int accept_with_timeout(int listener_fd, int timeout_ms) {
    pollfd descriptor{};
    descriptor.fd = listener_fd;
    descriptor.events = POLLIN;
    const int ready = poll(&descriptor, 1, timeout_ms);
    if (ready <= 0) return -1;
    return accept(listener_fd, nullptr, nullptr);
}

std::string find_in_path(const std::string& name) {
    const char* path_env = std::getenv("PATH");
    if (path_env == nullptr) return "";
    std::stringstream stream(path_env);
    std::string directory;
    while (std::getline(stream, directory, ':')) {
        if (directory.empty()) continue;
        const fs::path candidate = fs::path(directory) / name;
        if (access(candidate.c_str(), X_OK) == 0) return candidate.string();
    }
    return "";
}

std::string escape_sbpl_string(const std::string& value) {
    std::string escaped;
    escaped.reserve(value.size());
    for (char character : value) {
        if (character == '\\' || character == '"') escaped += '\\';
        escaped += character;
    }
    return escaped;
}

std::string macos_sandbox_profile(const fs::path& run_directory, const fs::path& executable) {
    const std::string run_path = escape_sbpl_string(run_directory.string());
    const std::string socket_path = escape_sbpl_string((run_directory / SOCKET_NAME).string());
    const std::string executable_path = escape_sbpl_string(executable.string());
    std::error_code canonical_error;
    const fs::path canonical_executable = fs::canonical(executable, canonical_error);
    const std::string canonical_executable_path = canonical_error
        ? ""
        : escape_sbpl_string(canonical_executable.string());

    std::ostringstream profile;
    profile << "(version 1)\n"
            << "(deny default)\n\n"
            << "(allow process-exec (literal \"" << executable_path << "\"))\n";
    if (!canonical_executable_path.empty() && canonical_executable_path != executable_path) {
        profile << "(allow process-exec (literal \"" << canonical_executable_path << "\"))\n";
    }
    profile << "(allow process-info* (target same-sandbox))\n"
            << "(allow signal (target same-sandbox))\n"
            << "(allow sysctl-read)\n"
            << "(allow mach-lookup\n"
            << "  (global-name \"com.apple.system.opendirectoryd.libinfo\")\n"
            << "  (global-name \"com.apple.system.DirectoryService.libinfo_v1\")\n"
            << "  (global-name \"com.apple.bsd.dirhelper\"))\n"
            << "(allow iokit-open (iokit-registry-entry-class \"RootDomainUserClient\"))\n\n"
            << "(allow system-socket (socket-domain AF_UNIX))\n"
            << "(allow network-outbound (literal \"" << socket_path << "\"))\n\n"
            << "(allow file-read* file-write* file-test-existence (subpath \"" << run_path << "\"))\n"
            << "(allow file-read* file-test-existence\n"
            << "  (subpath \"/usr\")\n"
            << "  (subpath \"/bin\")\n"
            << "  (subpath \"/sbin\")\n"
            << "  (subpath \"/System/Library\")\n"
            << "  (subpath \"/System/Volumes/Preboot\")\n"
            << "  (subpath \"/System/iOSSupport\")\n"
            << "  (subpath \"/Library/Apple\")\n"
            << "  (subpath \"/private/etc\")\n"
            << "  (subpath \"/etc\")\n"
            << "  (subpath \"/private/var/db/dyld\")\n"
            << "  (subpath \"/private/var/db/timezone\")\n"
            << "  (subpath \"/var/db/dyld\")\n"
            << "  (subpath \"/var/db/timezone\")\n"
            << "  (subpath \"/opt/homebrew\")\n"
            << "  (subpath \"/opt/local\")\n"
            << "  (subpath \"/usr/local\")\n"
            << "  (subpath \"/System/Volumes/Data/Library/Apple\")\n"
            << "  (subpath \"/System/Volumes/Data/private/etc\")\n"
            << "  (subpath \"/System/Volumes/Data/private/var/db/dyld\")\n"
            << "  (subpath \"/System/Volumes/Data/private/var/db/timezone\")\n"
            << "  (subpath \"/System/Volumes/Data/opt/homebrew\")\n"
            << "  (subpath \"/System/Volumes/Data/opt/local\")\n"
            << "  (subpath \"/System/Volumes/Data/usr/local\"))\n"
            << "(allow file-map-executable\n"
            << "  (subpath \"" << run_path << "\")\n"
            << "  (subpath \"/usr\")\n"
            << "  (subpath \"/bin\")\n"
            << "  (subpath \"/sbin\")\n"
            << "  (subpath \"/System/Library\")\n"
            << "  (subpath \"/System/Volumes/Preboot\")\n"
            << "  (subpath \"/System/iOSSupport\")\n"
            << "  (subpath \"/Library/Apple\")\n"
            << "  (subpath \"/opt/homebrew\")\n"
            << "  (subpath \"/opt/local\")\n"
            << "  (subpath \"/usr/local\")\n"
            << "  (subpath \"/System/Volumes/Data/Library/Apple\")\n"
            << "  (subpath \"/System/Volumes/Data/opt/homebrew\")\n"
            << "  (subpath \"/System/Volumes/Data/opt/local\")\n"
            << "  (subpath \"/System/Volumes/Data/usr/local\"))\n"
            << "(allow file-read* file-test-existence\n"
            << "  (literal \"/dev/null\")\n"
            << "  (literal \"/dev/zero\")\n"
            << "  (literal \"/dev/urandom\")\n"
            << "  (literal \"/dev/random\"))\n"
            << "(allow file-write-data\n"
            << "  (literal \"/dev/null\")\n"
            << "  (literal \"/dev/zero\"))\n"
            << "(allow file-read-metadata file-test-existence)\n";
    return profile.str();
}

std::string sandbox_prefix_description() {
#if defined(__linux__)
    const std::string bwrap = find_in_path("bwrap");
    if (!bwrap.empty()) return "bwrap";
    const std::string firejail = find_in_path("firejail");
    if (!firejail.empty()) return "firejail";
#elif defined(__APPLE__)
    const std::string sandbox_exec = find_in_path("sandbox-exec");
    if (!sandbox_exec.empty()) return "sandbox-exec";
#endif
    return "";
}

std::pair<std::string, std::vector<std::string>> launch_command(
    const fs::path& executable,
    const std::vector<std::string>& arguments,
    const fs::path& run_directory
) {
    const std::string tool = sandbox_prefix_description();
    std::vector<std::string> wrapped;

#if defined(__linux__)
    const std::string run_path = run_directory.string();
    if (tool == "bwrap") {
        wrapped = {
            "--die-with-parent",
            "--unshare-net",
            "--ro-bind", "/", "/",
            "--bind", run_path, run_path,
            "--chdir", run_path,
            "--"
        };
    } else if (tool == "firejail") {
        wrapped = {
            "--quiet",
            "--net=none",
            "--read-only",
            "--whitelist", run_path,
            "--chdir=" + run_path
        };
    }
#elif defined(__APPLE__)
    if (tool == "sandbox-exec") {
        const fs::path profile = run_directory / "sandbox.profile";
        {
            std::ofstream output(profile, std::ios::trunc);
            output << macos_sandbox_profile(run_directory, executable);
            output.close();
            if (!output) throw std::runtime_error("Could not write the macOS sandbox profile.");
        }
        wrapped = {"-f", profile.string()};
    }
#endif

    if (wrapped.empty()) {
        return {executable.string(), arguments};
    }

    const std::string wrapper = find_in_path(tool);
    std::vector<std::string> final_arguments = wrapped;
    final_arguments.push_back(executable.string());
    final_arguments.insert(final_arguments.end(), arguments.begin(), arguments.end());
    return {wrapper, final_arguments};
}

void apply_resource_limits() {
    rlimit cpu_limit{};
    cpu_limit.rlim_cur = 30;
    cpu_limit.rlim_max = 30;
    setrlimit(RLIMIT_CPU, &cpu_limit);

#ifdef RLIMIT_AS
    rlimit memory_limit{};
    memory_limit.rlim_cur = 512ULL * 1024 * 1024;
    memory_limit.rlim_max = 512ULL * 1024 * 1024;
    setrlimit(RLIMIT_AS, &memory_limit);
#endif

    rlimit file_limit{};
    file_limit.rlim_cur = 64;
    file_limit.rlim_max = 64;
    setrlimit(RLIMIT_NOFILE, &file_limit);

#ifdef RLIMIT_NPROC
    rlimit process_limit{};
    process_limit.rlim_cur = 32;
    process_limit.rlim_max = 32;
    setrlimit(RLIMIT_NPROC, &process_limit);
#endif

    rlimit core_limit{};
    core_limit.rlim_cur = 0;
    core_limit.rlim_max = 0;
    setrlimit(RLIMIT_CORE, &core_limit);
}

pid_t launch_process(
    const std::string& command,
    const std::vector<std::string>& arguments,
    const fs::path& run_directory
) {
    const pid_t pid = fork();
    if (pid < 0) throw std::runtime_error("Could not fork the student process.");
    if (pid == 0) {
        setpgid(0, 0);
        if (chdir(run_directory.c_str()) != 0) _exit(126);
        umask(077);

        const std::string run_path = run_directory.string();
        setenv("TMPDIR", run_path.c_str(), 1);
        setenv("TMP", run_path.c_str(), 1);
        setenv("TEMP", run_path.c_str(), 1);

        const int dev_null = open("/dev/null", O_RDONLY);
        if (dev_null >= 0) {
            dup2(dev_null, STDIN_FILENO);
            if (dev_null > STDERR_FILENO) close(dev_null);
        }
        const int stdout_log = open("stdout.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (stdout_log >= 0) {
            dup2(stdout_log, STDOUT_FILENO);
            if (stdout_log > STDERR_FILENO) close(stdout_log);
        }
        const int stderr_log = open("stderr.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (stderr_log >= 0) {
            dup2(stderr_log, STDERR_FILENO);
            if (stderr_log > STDERR_FILENO) close(stderr_log);
        }

        apply_resource_limits();
#ifdef __linux__
        prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
#endif

        std::vector<std::string> storage = arguments;
        storage.insert(storage.begin(), command);
        std::vector<char*> argv;
        argv.reserve(storage.size() + 1);
        for (std::string& value : storage) argv.push_back(value.data());
        argv.push_back(nullptr);

        execvp(command.c_str(), argv.data());
        _exit(127);
    }
    setpgid(pid, pid);
    return pid;
}

void terminate_child(pid_t pid) {
    if (pid <= 0) return;
    kill(-pid, SIGTERM);
    for (int attempt = 0; attempt < 20; ++attempt) {
        int status = 0;
        const pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) {
            g_child_pid = -1;
            return;
        }
        usleep(50000);
    }
    kill(-pid, SIGKILL);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    g_child_pid = -1;
}

int run_student(bool is_python, const std::string& run_id, const std::string& cleanup_token, int godot_port, const std::string& ipc_token) {
    const fs::path run_directory = run_directory_for(run_id);
    if (!token_matches(run_directory, cleanup_token)) {
        throw std::runtime_error("Run directory is not owned by this request.");
    }
    if (godot_port < 1 || godot_port > 65535) throw std::runtime_error("Godot IPC port is invalid.");
    if (ipc_token.empty()) throw std::runtime_error("Godot IPC token is missing.");

    fs::path executable;
    std::vector<std::string> arguments;
    if (is_python) {
        executable = find_python_executable(run_directory);
        if (executable.empty()) throw std::runtime_error("Private Python executable was not found in the run directory.");
        if (!fs::is_regular_file(run_directory / "student_program.py")) throw std::runtime_error("Student Python script was not found in the run directory.");
        arguments = {"-I", "student_program.py"};
    } else {
        executable = run_directory / "student_program";
        if (!fs::is_regular_file(executable)) throw std::runtime_error("Student executable was not found in the run directory.");
        std::error_code permission_error;
        fs::permissions(
            executable,
            fs::perms::owner_exe | fs::perms::group_exe | fs::perms::others_exe,
            fs::perm_options::add,
            permission_error
        );
        if (permission_error) throw std::runtime_error("Could not mark the student executable as runnable: " + permission_error.message());
    }

    UnixListener listener = create_unix_listener(run_directory);
    const auto launch = launch_command(executable, arguments, run_directory);
    const pid_t child_pid = launch_process(launch.first, launch.second, run_directory);
    g_child_pid = child_pid;

    int student_fd = -1;
    int godot_fd = -1;
    try {
        student_fd = accept_with_timeout(listener.fd, 10000);
        if (student_fd < 0) throw std::runtime_error("Student program could not connect to the IPC socket.");

        godot_fd = connect_worker_to_godot(godot_port, ipc_token);

        while (!g_stop_requested) {
            const std::string message = receive_message(student_fd);
            if (message.empty()) break;
            send_all(godot_fd, message + "\n");

            const bool needs_reply = message.rfind("[CMD]", 0) == 0 || message.rfind("[QUERY]", 0) == 0;
            if (needs_reply) {
                const std::string godot_reply = receive_line(godot_fd);
                send_all(student_fd, godot_reply + "\n");
            }
            if (message.rfind("[DONE]", 0) == 0) break;
        }
    } catch (...) {
        if (student_fd >= 0) close(student_fd);
        if (godot_fd >= 0) close(godot_fd);
        terminate_child(child_pid);
        throw;
    }

    if (student_fd >= 0) close(student_fd);
    if (godot_fd >= 0) close(godot_fd);
    terminate_child(child_pid);
    return 0;
}

int main(int argc, char* argv[]) {
    struct sigaction action {};
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, nullptr);
    sigaction(SIGINT, &action, nullptr);
    sigaction(SIGHUP, &action, nullptr);

    try {
        if (argc == 2 && std::string(argv[1]) == "--ping") {
            std::cout << "{\"type\":\"ready\",\"protocol\":" << PROTOCOL_VERSION << "}" << std::endl;
            return 0;
        }
        if (argc == 4 && std::string(argv[1]) == "--prepare-run") {
            const fs::path path = make_run_directory(argv[2], argv[3]);
            std::cout << "{\"type\":\"sandbox_ready\",\"path\":\"" << json_escape(path.string()) << "\"}" << std::endl;
            return 0;
        }
        if (argc == 5 && std::string(argv[1]) == "--prepare-python-run") {
            const fs::path path = make_run_directory(argv[2], argv[3]);
            try {
                copy_python_runtime_to_run(path, fs::path(argv[4]));
            } catch (...) {
                std::error_code ignored;
                fs::remove_all(path, ignored);
                throw;
            }
            std::cout << "{\"type\":\"sandbox_ready\",\"path\":\"" << json_escape(path.string()) << "\"}" << std::endl;
            return 0;
        }
        if (argc == 4 && std::string(argv[1]) == "--delete-run-dir") {
            delete_run_directory(argv[2], argv[3]);
            std::cout << "{\"type\":\"cleanup_complete\"}" << std::endl;
            return 0;
        }
        if (argc == 6 && (std::string(argv[1]) == "--run-cpp" || std::string(argv[1]) == "--run-python")) {
            return run_student(std::string(argv[1]) == "--run-python", argv[2], argv[3], std::stoi(argv[4]), argv[5]);
        }
        if (argc == 4 && std::string(argv[1]) == "--make-run-dir") {
            const fs::path path = make_run_directory(argv[2], argv[3]);
            std::cout << "{\"type\":\"run_directory\",\"path\":\"" << json_escape(path.string()) << "\"}" << std::endl;
            return 0;
        }
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }

    std::cerr << "Usage: sandbox_runner --ping | --prepare-run <run-id> <token> | --prepare-python-run <run-id> <token> <runtime-source> | --delete-run-dir <run-id> <token> | --run-cpp <run-id> <token> <godot-port> <ipc-token> | --run-python <run-id> <token> <godot-port> <ipc-token>" << std::endl;
    return 1;
}
