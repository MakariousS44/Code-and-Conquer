#include <chrono>
#include <filesystem>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <system_error>

namespace fs = std::filesystem;

std::string json_escape(const std::string& value) {
    std::string escaped;

    for (char character : value) {
        if (character == '\\') {
            escaped += "\\\\";
        } else if (character == '"') {
            escaped += "\\\"";
        } else {
            escaped += character;
        }
    }

    return escaped;
}

fs::path make_run_directory() {
    const fs::path root = fs::temp_directory_path() / "CodeAndConquer";
    fs::create_directories(root);

    std::random_device device;
    std::mt19937_64 random_generator(device());

    for (int attempt = 0; attempt < 10; ++attempt) {
        const auto timestamp =
            std::chrono::steady_clock::now().time_since_epoch().count();

        const fs::path run_directory =
            root / ("run-" + std::to_string(timestamp) + "-" +
                    std::to_string(random_generator()));

        if (fs::create_directory(run_directory)) {
            return run_directory;
        }
    }

    throw std::runtime_error("Could not create a unique run directory.");
}

fs::path run_root(){
    return fs::temp_directory_path() / "CodeAndConquer";
}

void delete_run_directory(const fs::path& requested_path){
    std::error_code error;

    const fs::path root = fs::weakly_canonical(run_root(), error);

    if(error){
        throw std::runtime_error("Could not resolve the run-folder root.");
    }

    const fs::path target = fs::weakly_canonical(requested_path, error);
    if (error  || target == root ||
        target.parent_path() != root ||
        target.filename().string().rfind("run-",0) != 0 ||
        !fs::is_directory(target)){
            throw std::runtime_error("Refusing to delete an unsafe path.");
        }
    
    fs::remove_all(target, error);
    if (error){
        throw std::runtime_error("Could not delete the run directory.");
    } 
}

int main(int argc, char* argv[]) {
    if (argc == 2 && std::string(argv[1]) == "--ping") {
        std::cout << R"({"type":"ready","protocol":1})" << std::endl;
        return 0;
    }

    if (argc == 2 && std::string(argv[1]) == "--make-run-dir") {
        try {
            const fs::path run_directory = make_run_directory();

            std::cout
                << R"({"type":"run_directory","path":")"
                << json_escape(run_directory.string())
                << R"("})"
                << std::endl;

            return 0;
        } catch (const std::exception& error) {
            std::cerr << error.what() << std::endl;
            return 1;
        }
    }

    if (argc == 3 && std::string(argv[1]) == "--delete-run-dir"){
        try {
            delete_run_directory(argv[2]);
            std::cout << R"({"type":"cleanup_complete"})" << std::endl;
            return 0;
        } catch (const std::exception& error){
            std::cerr << error.what() << std::endl;
            return 1;
        }
    }

    std::cerr << "Usage: sandbox_runner --ping | --make-run-dir | --delete-run-dir <path>" << std::endl;
    return 1;
}