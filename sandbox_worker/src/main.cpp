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

namespace fs = std::filesystem;
constexpr const char* TOKEN_FILE = ".cleanup-token";

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
    const char* local_app_data = std::getenv("LOCALAPPDATA");
    if (local_app_data != nullptr && *local_app_data != '\0') return fs::path(local_app_data) / "CodeAndConquer" / "sandbox-runs";
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
    return run_directory;
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

int main(int argc, char* argv[]) {
    if (argc == 2 && std::string(argv[1]) == "--ping") {
        std::cout << R"({"type":"ready","protocol":1})" << std::endl;
        return 0;
    }
    if (argc == 4 && std::string(argv[1]) == "--make-run-dir") {
        try {
            const fs::path path = make_run_directory(argv[2], argv[3]);
            std::cout << R"({"type":"run_directory","path":")" << json_escape(path.string()) << R"("})" << std::endl;
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << std::endl; return 1; }
    }
    if (argc == 4 && std::string(argv[1]) == "--delete-run-dir") {
        try {
            delete_run_directory(argv[2], argv[3]);
            std::cout << R"({"type":"cleanup_complete"})" << std::endl;
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << std::endl; return 1; }
    }
    std::cerr << "Usage: sandbox_runner --ping | --make-run-dir <run-id> <token> | --delete-run-dir <run-id> <token>" << std::endl;
    return 1;
}
