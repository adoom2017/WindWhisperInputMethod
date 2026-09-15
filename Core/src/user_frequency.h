#pragma once

#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#endif

// The sidecar lock remains stable when the data file is atomically replaced.
// Windows loads one IME per application, so an in-process mutex alone loses
// selections when two applications save concurrently.
class FrequencyFileLock {
public:
    explicit FrequencyFileLock(const std::filesystem::path &path) {
#ifdef _WIN32
        handle_ = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                             OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        locked_ = handle_ != INVALID_HANDLE_VALUE &&
                  LockFileEx(handle_, LOCKFILE_EXCLUSIVE_LOCK, 0, 1, 0, &overlapped_);
#else
        descriptor_ = open(path.c_str(), O_CREAT | O_RDWR, 0600);
        locked_ = descriptor_ >= 0 && flock(descriptor_, LOCK_EX) == 0;
#endif
    }
    ~FrequencyFileLock() {
#ifdef _WIN32
        if (locked_) UnlockFileEx(handle_, 0, 1, 0, &overlapped_);
        if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_);
#else
        if (locked_) flock(descriptor_, LOCK_UN);
        if (descriptor_ >= 0) close(descriptor_);
#endif
    }
    explicit operator bool() const { return locked_; }
private:
    bool locked_ = false;
#ifdef _WIN32
    HANDLE handle_ = INVALID_HANDLE_VALUE;
    OVERLAPPED overlapped_{};
#else
    int descriptor_ = -1;
#endif
};

class UserFrequency {
public:
    bool configure(const std::string &directory) {
        std::lock_guard<std::mutex> guard(mutex_);
        std::error_code error;
        const auto root = std::filesystem::u8path(directory);
        std::filesystem::create_directories(root, error);
        if (error) return false;
        path_ = root / "user_frequency.tsv";
        lock_path_ = root / "user_frequency.lock";
        reload();
        return true;
    }

    std::unordered_map<std::string, int> frequencies(const std::string &schema,
                                                   const std::string &code) {
        std::lock_guard<std::mutex> guard(mutex_);
        reload();
        std::unordered_map<std::string, int> result;
        const auto prefix = schema + '\t' + code + '\t';
        for (auto it = counts_.lower_bound(prefix);
             it != counts_.end() && it->first.compare(0, prefix.size(), prefix) == 0; ++it) {
            result.emplace(it->first.substr(prefix.size()), it->second);
        }
        return result;
    }

    void record(const std::string &schema, const std::string &code, const std::string &text) {
        if (code.empty() || text.empty() || code.find_first_of("\t\r\n") != std::string::npos ||
            text.find_first_of("\t\r\n") != std::string::npos) return;
        std::lock_guard<std::mutex> guard(mutex_);
        const auto key = schema + '\t' + code + '\t' + text;
        if (path_.empty()) {
            increment(key);
            return;
        }
        FrequencyFileLock file_lock(lock_path_);
        if (!file_lock) return;
        reload(true);
        increment(key);
        auto temporary = path_;
        temporary += ".tmp";
        std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
        if (!output) return;
        for (const auto &entry : counts_) output << entry.first << '\t' << entry.second << '\n';
        output.close();
        if (!output) return;
#ifdef _WIN32
        if (!MoveFileExW(temporary.c_str(), path_.c_str(),
                         MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) return;
#else
        std::error_code error;
        std::filesystem::rename(temporary, path_, error);
        if (error) return;
#endif
        update_stamp();
    }

private:
    void increment(const std::string &key) {
        auto &count = counts_[key];
        if (count < 1000000000) ++count;
    }
    void update_stamp() {
        std::error_code error;
        stamp_ = std::filesystem::last_write_time(path_, error);
        size_ = std::filesystem::file_size(path_, error);
    }
    void reload(bool force = false) {
        if (path_.empty()) return;
        std::error_code error;
        const auto stamp = std::filesystem::last_write_time(path_, error);
        if (error) return;
        const auto size = std::filesystem::file_size(path_, error);
        if (error || (!force && stamp == stamp_ && size == size_)) return;
        // A Windows reader must not hold the TSV open while another process
        // replaces it (fstream does not request FILE_SHARE_DELETE).
        std::unique_ptr<FrequencyFileLock> reader_lock;
        if (!force) {
            reader_lock = std::make_unique<FrequencyFileLock>(lock_path_);
            if (!*reader_lock) return;
        }
        std::ifstream input(path_, std::ios::binary);
        if (!input) return;
        std::map<std::string, int> loaded;
        std::string line;
        while (std::getline(input, line)) {
            const auto first = line.find('\t');
            const auto second = first == std::string::npos ? first : line.find('\t', first + 1);
            const auto third = second == std::string::npos ? second : line.find('\t', second + 1);
            if (third == std::string::npos || second == first + 1 || third == second + 1) continue;
            const auto schema = line.substr(0, first);
            if (schema != "fullPinyin" && schema != "flypyShape" && schema != "flypyPhonetic") continue;
            try {
                const auto number = line.substr(third + 1);
                size_t used = 0;
                const auto count = std::stoll(number, &used);
                if (used == number.size() && count > 0 && count <= 1000000000)
                    loaded[line.substr(0, third)] = static_cast<int>(count);
            } catch (...) { /* Ignore malformed rows without losing valid history. */ }
        }
        if (!input.eof()) return;
        counts_ = std::move(loaded);
        stamp_ = stamp;
        size_ = size;
    }

    std::mutex mutex_;
    std::map<std::string, int> counts_;
    std::filesystem::path path_, lock_path_;
    std::filesystem::file_time_type stamp_{};
    uintmax_t size_ = 0;
};
