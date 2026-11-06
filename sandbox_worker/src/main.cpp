#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <processthreadsapi.h>
#include <userenv.h>
#include <aclapi.h>
#include <sddl.h>
#include <objbase.h>
#endif

#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>
#include <array>


namespace fs = std::filesystem;

#ifdef _WIN32
constexpr wchar_t APP_CONTAINER_NAME[] = L"CodeAndConquer.StudentSandbox";
constexpr wchar_t APP_CONTAINER_DISPLAY_NAME[] = L"Code and Conquer Student Sandbox";

PSID get_or_create_appcontainer_sid() {
    PSID sid = nullptr;

    HRESULT result = CreateAppContainerProfile(
        APP_CONTAINER_NAME,
        APP_CONTAINER_DISPLAY_NAME,
        L"Runs student programs with restricted access.",
        nullptr,
        0,
        &sid
    );

    if (result == HRESULT_FROM_WIN32(ERROR_ALREADY_EXISTS)) {
        result = DeriveAppContainerSidFromAppContainerName(
            APP_CONTAINER_NAME,
            &sid
        );
    }

    if (FAILED(result) || sid == nullptr) {
        throw std::runtime_error(
            "Could not create or open the AppContainer profile. HRESULT: "
            + std::to_string(static_cast<unsigned long>(result))
        );
    }

    return sid;
}

fs::path get_appcontainer_local_data_path() {
    PSID sid = get_or_create_appcontainer_sid();

    LPWSTR sid_text = nullptr;
    if (!ConvertSidToStringSidW(sid, &sid_text)) {
        FreeSid(sid);
        throw std::runtime_error("Could not convert the AppContainer SID.");
    }

    PWSTR appcontainer_path = nullptr;
    const HRESULT result = GetAppContainerFolderPath(
        sid_text,
        &appcontainer_path
    );

    LocalFree(sid_text);
    FreeSid(sid);

    if (FAILED(result) || appcontainer_path == nullptr) {
        throw std::runtime_error("Could not find the AppContainer data folder.");
    }

    fs::path result_path(appcontainer_path);
    CoTaskMemFree(appcontainer_path);

    return result_path;
}

#endif

#ifdef _WIN32
void grant_run_directory_access(const std::filesystem::path& run_dir, PSID appcontainer_sid) {
    EXPLICIT_ACCESSW entry{};
    entry.grfAccessPermissions =
        FILE_GENERIC_READ |
        FILE_GENERIC_WRITE |
        FILE_GENERIC_EXECUTE |
        DELETE;
    entry.grfAccessMode = GRANT_ACCESS;
    entry.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
    entry.Trustee.TrusteeForm = TRUSTEE_IS_SID;
    entry.Trustee.ptstrName = static_cast<LPWSTR>(appcontainer_sid);

    PSECURITY_DESCRIPTOR security_descriptor = nullptr;
    PACL existing_dacl = nullptr;

    DWORD result = GetNamedSecurityInfoW(
        const_cast<LPWSTR>(run_dir.c_str()),
        SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION,
        nullptr,
        nullptr,
        &existing_dacl,
        nullptr,
        &security_descriptor
    );

    if (result != ERROR_SUCCESS) {
        throw std::runtime_error("Could not read the sandbox directory ACL.");
    }

    PACL updated_dacl = nullptr;
    result = SetEntriesInAclW(1, &entry, existing_dacl, &updated_dacl);

    if (security_descriptor != nullptr) {
        LocalFree(security_descriptor);
    }

    if (result != ERROR_SUCCESS) {
        throw std::runtime_error("Could not build the sandbox directory ACL.");
    }

    const DWORD security_result = SetNamedSecurityInfoW(
        const_cast<LPWSTR>(run_dir.c_str()),
        SE_FILE_OBJECT,
        DACL_SECURITY_INFORMATION,
        nullptr,
        nullptr,
        updated_dacl,
        nullptr
    );

    LocalFree(updated_dacl);

    if (security_result != ERROR_SUCCESS) {
        throw std::runtime_error("Could not secure the sandbox run directory.");
    }
}
#endif

namespace fs = std::filesystem;
constexpr const char* TOKEN_FILE = ".cleanup-token";

#ifdef _WIN32
HANDLE create_student_job() {
    HANDLE job = CreateJobObjectW(nullptr, nullptr);

    if (job == nullptr) {
        throw std::runtime_error(
            "Could not create the student job. Windows error: "
            + std::to_string(GetLastError())
        );
    }

    constexpr SIZE_T STUDENT_MEMORY_LIMIT = 
        static_cast<SIZE_T>(512) * 1024 * 1024; 
    constexpr LONGLONG STUDENT_CPU_TIME_LIMIT =
    30LL * 10'000'000;
    
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | 
        JOB_OBJECT_LIMIT_PROCESS_MEMORY |
        JOB_OBJECT_LIMIT_ACTIVE_PROCESS |
        JOB_OBJECT_LIMIT_PROCESS_TIME;
    
    limits.ProcessMemoryLimit = STUDENT_MEMORY_LIMIT;
    limits.BasicLimitInformation.ActiveProcessLimit = 1;
    limits.BasicLimitInformation.PerProcessUserTimeLimit.QuadPart =
        STUDENT_CPU_TIME_LIMIT;

    if (!SetInformationJobObject(
        job,
        JobObjectExtendedLimitInformation,
        &limits,
        sizeof(limits)
    )) {
        const DWORD error = GetLastError();
        CloseHandle(job);

        throw std::runtime_error(
            "Could not configure the student job. Windows error: "
            + std::to_string(error)
        );
    }

    return job;
}

DWORD launch_cpp_in_appcontainer(
    const fs::path& executable_path,
    const fs::path& working_directory,
    HANDLE student_job = nullptr,
    const std::wstring& extra_arguments = L""
) {
    PSID appcontainer_sid = get_or_create_appcontainer_sid();

    SECURITY_CAPABILITIES capabilities{};
    capabilities.AppContainerSid = appcontainer_sid;
    capabilities.Capabilities = nullptr;
    capabilities.CapabilityCount = 0; // No network or other capabilities.
    capabilities.Reserved = 0;

    SIZE_T attribute_list_size = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &attribute_list_size);

    auto attribute_list = static_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(
        HeapAlloc(GetProcessHeap(), 0, attribute_list_size)
    );

    if (attribute_list == nullptr) {
        FreeSid(appcontainer_sid);
        throw std::runtime_error("Could not allocate AppContainer attributes.");
    }

    if (!InitializeProcThreadAttributeList(
        attribute_list, 1, 0, &attribute_list_size
    )) {
        HeapFree(GetProcessHeap(), 0, attribute_list);
        FreeSid(appcontainer_sid);
        throw std::runtime_error("Could not initialize AppContainer attributes.");
    }

    if (!UpdateProcThreadAttribute(
        attribute_list,
        0,
        PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
        &capabilities,
        sizeof(capabilities),
        nullptr,
        nullptr
    )) {
        DeleteProcThreadAttributeList(attribute_list);
        HeapFree(GetProcessHeap(), 0, attribute_list);
        FreeSid(appcontainer_sid);
        throw std::runtime_error("Could not apply AppContainer security settings.");
    }

    STARTUPINFOEXW startup_info{};
    startup_info.StartupInfo.cb = sizeof(startup_info);
    startup_info.lpAttributeList = attribute_list;

    PROCESS_INFORMATION process_info{};

    std::wstring command_line =
        L"\"" + executable_path.wstring() + L"\"" + extra_arguments;
    
    std::vector<wchar_t> mutable_command_line(
        command_line.begin(), command_line.end()
    );
    mutable_command_line.push_back(L'\0');

    const BOOL started = CreateProcessW(
        nullptr,
        mutable_command_line.data(),
        nullptr,
        nullptr,
        FALSE, // Do not leak game/worker handles to student code.
        EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW | CREATE_SUSPENDED,
        nullptr,
        working_directory.c_str(),
        &startup_info.StartupInfo,
        &process_info
    );

    const DWORD process_error = started ? ERROR_SUCCESS : GetLastError();

    DeleteProcThreadAttributeList(attribute_list);
    HeapFree(GetProcessHeap(), 0, attribute_list);
    FreeSid(appcontainer_sid);

    if (!started) {
    throw std::runtime_error(
        "Could not start AppContainer executable: "
        + executable_path.string()
        + " | working directory: "
        + working_directory.string()
        + " | Windows error: "
        + std::to_string(process_error)
    );
}

    if (student_job != nullptr && !AssignProcessToJobObject(
        student_job,
        process_info.hProcess
    )) {
        const DWORD error = GetLastError();

        TerminateProcess(process_info.hProcess, 1);
        CloseHandle(process_info.hThread);
        CloseHandle(process_info.hProcess);

        throw std::runtime_error(
            "Could not add the student program to its job. Windows error: "
            + std::to_string(error)
        );
    }

    if (ResumeThread(process_info.hThread) == static_cast<DWORD>(-1)) {
        const DWORD error = GetLastError();

        TerminateProcess(process_info.hProcess, 1);
        CloseHandle(process_info.hThread);
        CloseHandle(process_info.hProcess);

        throw std::runtime_error(
            "Could not start the student program. Windows error: "
            + std::to_string(error)
        );
    }

    const DWORD pid = process_info.dwProcessId;
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);

    return pid;
}
#endif

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

fs::path run_root() {
#ifdef _WIN32
    return get_appcontainer_local_data_path() / "sandbox-runs";
#endif
    return fs::temp_directory_path() / "CodeAndConquer" / "sandbox-runs";
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

fs::path ensure_private_root() {
    const fs::path root = run_root();
    // LOCALAPPDATA is private to the current Windows account. Check the app
    // directory separately so a pre-created CodeAndConquer symlink is rejected.
    ensure_real_directory(root.parent_path());
    std::error_code error;
    ensure_real_directory(root);
#ifndef _WIN32
    fs::permissions(root, fs::perms::owner_all, fs::perm_options::replace, error);
    if (error) throw std::runtime_error("Could not secure sandbox run root permissions.");
#endif
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
        return run_directory; // Idempotent retry after a lost response.
    }
    if (!fs::create_directory(run_directory, error) || error) throw std::runtime_error("Could not create the sandbox run directory.");
    std::ofstream token_file(run_directory / TOKEN_FILE, std::ios::binary | std::ios::trunc);
    token_file << token << '\n';
    token_file.close();
    if (!token_file) {
        fs::remove_all(run_directory, error);
        throw std::runtime_error("Could not initialize the sandbox run directory.");
    }
        
#ifdef _WIN32
    PSID sandbox_sid = get_or_create_appcontainer_sid();
    try {
        grant_run_directory_access(run_directory, sandbox_sid);
    } catch (...) {
        FreeSid(sandbox_sid);
        throw;
    }
    FreeSid(sandbox_sid);
#endif

    return run_directory;
}

void copy_python_runtime_to_run(const fs::path& run_directory, const fs::path& runtime_source) {
    if (!fs::is_directory(runtime_source)) {
        throw std::runtime_error(
            "Sandbox Python runtime was not found: "
            + runtime_source.string()
        );
    }

    const fs::path runtime_destination =
        run_directory / "python";

    if (!fs::is_regular_file(runtime_source / "python.exe")) {
        throw std::runtime_error(
            "Sandbox Python runtime was not found: "
            + runtime_source.string()
        );
    }

    std::error_code error;

    fs::copy(
        runtime_source,
        runtime_destination,
        fs::copy_options::recursive,
        error
    );

    if (error) {
        throw std::runtime_error(
            "Could not copy the Python runtime into the secure run folder. Error: "
            + error.message()
        );
    }

    if (!fs::is_regular_file(runtime_destination / "python.exe")) {
        throw std::runtime_error(
            "Python was copied, but python.exe is missing from the secure run folder."
        );
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

#ifdef _WIN32
std::wstring get_current_user_sid_text() {
    HANDLE token = nullptr;

    if (!OpenProcessToken(
        GetCurrentProcess(),
        TOKEN_QUERY,
        &token
    )) {
        throw std::runtime_error("Could not open the worker process token.");
    }

    DWORD size = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &size);

    std::vector<BYTE> buffer(size);

    if (!GetTokenInformation(
        token,
        TokenUser,
        buffer.data(),
        size,
        &size
    )) {
        CloseHandle(token);
        throw std::runtime_error("Could not read the worker user SID.");
    }

    const auto* token_user =
        reinterpret_cast<const TOKEN_USER*>(buffer.data());

    LPWSTR sid_text = nullptr;
    if (!ConvertSidToStringSidW(token_user->User.Sid, &sid_text)) {
        CloseHandle(token);
        throw std::runtime_error("Could not convert the worker user SID.");
    }

    std::wstring result(sid_text);

    LocalFree(sid_text);
    CloseHandle(token);

    return result;
}
#endif

#ifdef _WIN32
HANDLE create_student_pipe(
    const std::string& run_id,
    PSID appcontainer_sid
) {
    const std::wstring pipe_name =
        L"\\\\.\\pipe\\CodeAndConquer-"
        + std::wstring(run_id.begin(), run_id.end());

    LPWSTR appcontainer_sid_text = nullptr;
    if (!ConvertSidToStringSidW(
        appcontainer_sid,
        &appcontainer_sid_text
    )) {
        throw std::runtime_error("Could not convert the AppContainer SID.");
    }

    // Allow this AppContainer SID to read/write the pipe.
    // Label the pipe Low Integrity so the Low-Integrity AppContainer may write.
    const std::wstring user_sid_text = get_current_user_sid_text();

    const std::wstring sddl =
        L"D:(A;;GRGW;;;"
        + user_sid_text
        + L")(A;;GRGW;;;"
        + std::wstring(appcontainer_sid_text)
        + L")S:(ML;;NW;;;LW)";

    PSECURITY_DESCRIPTOR security_descriptor = nullptr;
    const BOOL descriptor_ok =
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(),
            SDDL_REVISION_1,
            &security_descriptor,
            nullptr
        );

    LocalFree(appcontainer_sid_text);

    if (!descriptor_ok) {
        throw std::runtime_error(
            "Could not create the named-pipe security descriptor. Windows error: "
            + std::to_string(GetLastError())
        );
    }

    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.lpSecurityDescriptor = security_descriptor;
    attributes.bInheritHandle = FALSE;

    HANDLE pipe = CreateNamedPipeW(
        pipe_name.c_str(),
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE |
        PIPE_READMODE_MESSAGE |
        PIPE_WAIT |
        PIPE_REJECT_REMOTE_CLIENTS,
        1,
        8192,
        8192,
        0,
        &attributes
    );

    const DWORD error_code =
        pipe == INVALID_HANDLE_VALUE ? GetLastError() : ERROR_SUCCESS;

    LocalFree(security_descriptor);

    if (pipe == INVALID_HANDLE_VALUE) {
        throw std::runtime_error(
            "Could not create the student named pipe. Windows error: "
            + std::to_string(error_code)
        );
    }

    return pipe;
}
#endif

#ifdef _WIN32
SOCKET connect_worker_to_godot(
    int port,
    const std::string& ipc_token
) {
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        throw std::runtime_error("Could not start Windows socket support.");
    }

    SOCKET socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    if (socket_handle == INVALID_SOCKET) {
        WSACleanup();
        throw std::runtime_error("Could not create the Godot IPC socket.");
    }

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<u_short>(port));
    address.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(
        socket_handle,
        reinterpret_cast<sockaddr*>(&address),
        sizeof(address)
    ) == SOCKET_ERROR) {
        closesocket(socket_handle);
        WSACleanup();
        throw std::runtime_error(
            "Could not connect the worker to Godot IPC. Windows error: "
            + std::to_string(WSAGetLastError())
        );
    }

    const std::string auth_message =
        "[AUTH] " + ipc_token + "\n";

    const int sent = send(
        socket_handle,
        auth_message.c_str(),
        static_cast<int>(auth_message.size()),
        0
    );

    if (sent != static_cast<int>(auth_message.size())) {
        closesocket(socket_handle);
        WSACleanup();
        throw std::runtime_error(
            "Could not authenticate the worker with Godot IPC."
        );
    }

    return socket_handle;
}
#endif


#ifdef _WIN32
void send_all(SOCKET socket_handle, const std::string& text) {
    size_t sent_total = 0;

    while (sent_total < text.size()) {
        const int sent = send(
            socket_handle,
            text.data() + sent_total,
            static_cast<int>(text.size() - sent_total),
            0
        );

        if (sent <= 0) {
            throw std::runtime_error(
                "Could not send a message to Godot. Windows error: "
                + std::to_string(WSAGetLastError())
            );
        }

        sent_total += static_cast<size_t>(sent);
    }
}

std::string receive_line(SOCKET socket_handle) {
    std::string result;
    char character = '\0';

    while (result.size() < 8192) {
        const int received = recv(socket_handle, &character, 1, 0);

        if (received <= 0) {
            throw std::runtime_error(
                "Could not receive a reply from Godot. Windows error: "
                + std::to_string(WSAGetLastError())
            );
        }

        if (character == '\n') {
            return result;
        }

        if (character != '\r') {
            result += character;
        }
    }

    throw std::runtime_error("Godot IPC reply exceeded the size limit.");
}
#endif

int main(int argc, char* argv[]) {
    if (argc == 2 && std::string(argv[1]) == "--ping") {
        std::cout << R"({"type":"ready","protocol":2})" << std::endl;
        return 0;
    }
    if (argc == 4 && std::string(argv[1]) == "--prepare-run") {
        try {
            const fs::path path = make_run_directory(argv[2], argv[3]);

            std::cout
                << R"({"type":"sandbox_ready","path":")"
                << json_escape(path.string())
                << R"("})"
                << std::endl;

            return 0;
        } catch (const std::exception& error) {
            std::cerr << error.what() << std::endl;
            return 1;
        }
    }

    if (argc == 5 && std::string(argv[1]) == "--prepare-python-run") {
        try {
            const fs::path path = make_run_directory(argv[2], argv[3]);

            try {
                copy_python_runtime_to_run(path, fs::path(argv[4]));
            } catch (...) {
                std::error_code error;
                fs::remove_all(path, error);
                throw;
            }

            std::cout
                << R"({"type":"sandbox_ready","path":")"
                << json_escape(path.string())
                << R"("})"
                << std::endl;

            return 0;
        } catch (const std::exception& error) {
            std::cerr << error.what() << std::endl;
            return 1;
        }
    }

    if (argc == 4 && std::string(argv[1]) == "--delete-run-dir") {
        try {
            delete_run_directory(argv[2], argv[3]);
            std::cout << R"({"type":"cleanup_complete"})" << std::endl;
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << std::endl; return 1; }
    }

    if (argc == 4 && std::string(argv[1]) == "--launch-cpp") {
    try {
        const std::string run_id = argv[2];
        const std::string token = argv[3];

        const fs::path run_directory = run_directory_for(run_id);

        if (!token_matches(run_directory, token)) {
            throw std::runtime_error("Run directory is not owned by this request.");
        }

        const fs::path executable = run_directory / "student_program.exe";

        if (!fs::is_regular_file(executable)) {
            throw std::runtime_error("Student executable was not found in the run directory.");
        }

        const DWORD pid = launch_cpp_in_appcontainer(
            executable,
            run_directory
        );

        std::cout
            << R"({"type":"started","pid":)"
            << pid
            << "}"
            << std::endl;

        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
        }
    }


    if (argc == 6 && (std::string(argv[1]) == "--run-cpp" || std::string(argv[1]) == "--run-python")) {
    try {
        const std::string run_id = argv[2];
        const std::string cleanup_token = argv[3];
        const int godot_port = std::stoi(argv[4]);
        const std::string ipc_token = argv[5];
        const bool is_python = std::string(argv[1]) == "--run-python";

        const fs::path run_directory = run_directory_for(run_id);

        if (!token_matches(run_directory, cleanup_token)) {
            throw std::runtime_error("Run directory is not owned by this request.");
        }

        if (godot_port < 1 || godot_port > 65535) {
            throw std::runtime_error("Godot IPC port is invalid.");
        }

        if (ipc_token.empty()) {
            throw std::runtime_error("Godot IPC token is missing.");
        }

        const fs::path executable = is_python
            ? run_directory / "python" / "python.exe"
            : run_directory / "student_program.exe";

        if (!fs::is_regular_file(executable)) {
            throw std::runtime_error(
                is_python
                    ? "Private Python executable was not found in the run directory."
                    : "Student executable was not found in the run directory."
            );
        }

        if (
            is_python
            && !fs::is_regular_file(run_directory / "student_program.py")
        ) {
            throw std::runtime_error(
                "Student Python script was not found in the run directory."
            );
        }

        const std::string pipe_name =
            R"(\\.\pipe\CodeAndConquer-)" + run_id;

            
        std::cout
            << R"({"type":"run_request_valid","pipe":")"
            << json_escape(pipe_name)
            << R"("})"
            << std::endl;
        
        PSID appcontainer_sid = get_or_create_appcontainer_sid();
        HANDLE student_pipe = INVALID_HANDLE_VALUE;
        HANDLE student_job = create_student_job();

        try {
            student_pipe = create_student_pipe(run_id, appcontainer_sid);

            std::cout
                << R"({"type":"pipe_created","pipe":")"
                << json_escape(pipe_name)
                << R"("})"
                << std::endl;
                
            const std::wstring extra_arguments = is_python
                ? L" -I \"student_program.py\""
                : L"";

            const DWORD student_pid = launch_cpp_in_appcontainer(
                executable,
                run_directory,
                student_job,
                extra_arguments
            );

            std::cout
                << R"({"type":"started","pid":)"
                << student_pid
                << "}"
                << std::endl;
            

            const BOOL connected = ConnectNamedPipe(student_pipe, nullptr)
                ? TRUE
                : GetLastError() == ERROR_PIPE_CONNECTED;

            if (!connected) {
                throw std::runtime_error(
                    "Student program could not connect to the named pipe. Windows error: "
                    + std::to_string(GetLastError())
                );
            }

            std::cout << R"({"type":"student_connected"})" << std::endl;

            SOCKET godot_socket = INVALID_SOCKET;

            try {
                godot_socket = connect_worker_to_godot(
                    godot_port,
                    ipc_token
                );

                while (true) {
                    std::array<char, 8192> message_buffer{};
                    DWORD bytes_read = 0;

                    if (!ReadFile(
                        student_pipe,
                        message_buffer.data(),
                        static_cast<DWORD>(message_buffer.size()),
                        &bytes_read,
                        nullptr
                    )) {
                        const DWORD pipe_error = GetLastError();

                        if (pipe_error == ERROR_BROKEN_PIPE) {
                            break;
                        }

                        throw std::runtime_error(
                            "Could not read the student pipe message. Windows error: "
                            + std::to_string(pipe_error)
                        );
                    }

                    if (bytes_read == 0) {
                        continue;
                    }

                    const std::string message(
                        message_buffer.data(),
                        bytes_read
                    );

                    std::cout
                        << R"({"type":"pipe_message","message":")"
                        << json_escape(message)
                        << R"("})"
                        << std::endl;

                    send_all(godot_socket, message);

                    const bool needs_reply =
                        message.rfind("[CMD]", 0) == 0
                        || message.rfind("[QUERY]", 0) == 0;

                    if (needs_reply) {
                        const std::string godot_reply =
                            receive_line(godot_socket);

                        const std::string pipe_reply =
                            godot_reply + "\n";

                        DWORD bytes_written = 0;

                        if (!WriteFile(
                            student_pipe,
                            pipe_reply.data(),
                            static_cast<DWORD>(pipe_reply.size()),
                            &bytes_written,
                            nullptr
                        )) {
                            throw std::runtime_error(
                                "Could not write Godot's reply to the student pipe. Windows error: "
                                + std::to_string(GetLastError())
                            );
                        }
                    }

                    if (message.rfind("[DONE]", 0) == 0) {
                        break;
                    }
                }

                closesocket(godot_socket);
                WSACleanup();
            } catch (...) {
                if (godot_socket != INVALID_SOCKET) {
                    closesocket(godot_socket);
                }

                WSACleanup();
                throw;
            }
                            
        } catch (...) {
            if (student_pipe != INVALID_HANDLE_VALUE) {
                CloseHandle(student_pipe);
            }

            CloseHandle(student_job);
            FreeSid(appcontainer_sid);
            throw;
        }
        
        CloseHandle(student_pipe);
        CloseHandle(student_job);
        FreeSid(appcontainer_sid);  

        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
 
    std::cerr << "Usage: sandbox_runner --ping | --prepare-run <run-id> <token> | --prepare-python-run <run-id> <token> <runtime-source> | --delete-run-dir <run-id> <token> | --launch-cpp <run-id> <token> | --run-cpp <run-id> <token> <godot-port> <ipc-token>" << std::endl;
    return 1;
}
