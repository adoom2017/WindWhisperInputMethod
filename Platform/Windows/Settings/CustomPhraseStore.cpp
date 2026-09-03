#include "CustomPhraseStore.h"

#ifdef _WIN32
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cwctype>
#include <fstream>
#include <iterator>
#include <unordered_map>

namespace fengyu {
namespace {

std::wstring Utf8ToWide(const std::string &value) {
    if (value.empty()) return {};
    const int length = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(),
                            length) != length) {
        return {};
    }
    return result;
}

std::string WideToUtf8(const std::wstring &value) {
    if (value.empty()) return {};
    const int length = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
        static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (length <= 0) return {};
    std::string result(static_cast<size_t>(length), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), result.data(),
                            length, nullptr, nullptr) != length) {
        return {};
    }
    return result;
}

std::wstring Trim(std::wstring value) {
    const auto not_space = [](wchar_t character) {
        return !std::iswspace(character);
    };
    value.erase(value.begin(),
                std::find_if(value.begin(), value.end(), not_space));
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(),
                value.end());
    return value;
}

std::string TrimAscii(std::string value) {
    const auto not_space = [](unsigned char character) {
        return character != ' ' && character != '\t' && character != '\r' &&
               character != '\n';
    };
    value.erase(value.begin(),
                std::find_if(value.begin(), value.end(), not_space));
    value.erase(std::find_if(value.rbegin(), value.rend(), not_space).base(),
                value.end());
    return value;
}

void SetError(std::wstring *error_message, const std::wstring &value) {
    if (error_message) *error_message = value;
}

bool ParseWeight(const std::string &value, std::optional<int> *weight) {
    if (!weight) return false;
    const std::string trimmed = TrimAscii(value);
    if (trimmed.empty()) {
        *weight = std::nullopt;
        return true;
    }
    int parsed = 0;
    const auto result = std::from_chars(
        trimmed.data(), trimmed.data() + trimmed.size(), parsed);
    if (result.ec != std::errc{} ||
        result.ptr != trimmed.data() + trimmed.size() || parsed < 0) {
        return false;
    }
    *weight = parsed;
    return true;
}

}  // namespace

std::filesystem::path CustomPhraseFilePath() {
    wchar_t local_app_data[32768]{};
    const DWORD length = GetEnvironmentVariableW(
        L"LOCALAPPDATA", local_app_data,
        static_cast<DWORD>(std::size(local_app_data)));
    if (length == 0 || length >= std::size(local_app_data)) return {};
    return std::filesystem::path(local_app_data, local_app_data + length) /
           L"WindWhisper" / L"InputMethod" / L"custom_words.tsv";
}

bool NormalizeCustomPhrases(CustomPhraseDocument *document,
                            std::wstring *error_message) {
    if (!document) {
        SetError(error_message, L"自定义词组数据不可用。");
        return false;
    }
    std::unordered_map<std::string, size_t> first_index;
    for (size_t index = 0; index < document->entries.size(); ++index) {
        CustomPhrase &entry = document->entries[index];
        entry.text = Trim(std::move(entry.text));
        entry.code = TrimAscii(std::move(entry.code));
        std::transform(entry.code.begin(), entry.code.end(), entry.code.begin(),
                       [](unsigned char value) {
                           return static_cast<char>(std::tolower(value));
                       });
        const std::wstring row = std::to_wstring(index + 1);
        if (entry.text.empty()) {
            SetError(error_message, L"第 " + row + L" 个词组不能为空。");
            return false;
        }
        if (entry.text.find_first_of(L"\t\r\n") != std::wstring::npos) {
            SetError(error_message,
                     L"第 " + row + L" 个词组不能包含制表符或换行。");
            return false;
        }
        if (entry.code.empty() ||
            !std::all_of(entry.code.begin(), entry.code.end(), [](char value) {
                return (value >= 'a' && value <= 'z') || value == '\'';
            })) {
            SetError(error_message,
                     L"第 " + row + L" 个编码只能包含英文字母和撇号。");
            return false;
        }
        if (entry.weight && *entry.weight < 0) {
            SetError(error_message, L"第 " + row + L" 个权重必须是非负整数。");
            return false;
        }
        const std::string key = WideToUtf8(entry.text) + '\0' + entry.code;
        const auto inserted = first_index.emplace(key, index);
        if (!inserted.second) {
            SetError(error_message,
                     L"第 " + row + L" 个词组与第 " +
                         std::to_wstring(inserted.first->second + 1) +
                         L" 个词组重复。");
            return false;
        }
    }
    if (error_message) error_message->clear();
    return true;
}

bool LoadCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument *document,
                       std::wstring *error_message) {
    if (!document || path.empty()) {
        SetError(error_message, L"无法确定自定义词典路径。");
        return false;
    }
    *document = {};
    if (!std::filesystem::exists(path)) {
        if (error_message) error_message->clear();
        return true;
    }
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        SetError(error_message, L"无法读取 custom_words.tsv。");
        return false;
    }
    std::string line;
    size_t line_number = 0;
    while (std::getline(input, line)) {
        ++line_number;
        if (line_number == 1 && line.rfind("\xEF\xBB\xBF", 0) == 0) {
            line.erase(0, 3);
        }
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const std::string trimmed = TrimAscii(line);
        if (trimmed.empty()) continue;
        if (trimmed[0] == '#' || trimmed[0] == '-') {
            document->comments.push_back(line);
            continue;
        }
        const size_t first_tab = line.find('\t');
        const size_t second_tab = first_tab == std::string::npos
                                      ? std::string::npos
                                      : line.find('\t', first_tab + 1);
        if (first_tab == std::string::npos ||
            (second_tab != std::string::npos &&
             line.find('\t', second_tab + 1) != std::string::npos)) {
            SetError(error_message, L"custom_words.tsv 第 " +
                                        std::to_wstring(line_number) +
                                        L" 行格式不正确。");
            return false;
        }
        CustomPhrase entry;
        const std::string utf8_text = line.substr(0, first_tab);
        entry.text = Utf8ToWide(utf8_text);
        if (entry.text.empty() && !utf8_text.empty()) {
            SetError(error_message, L"custom_words.tsv 第 " +
                                        std::to_wstring(line_number) +
                                        L" 行不是有效的 UTF-8 文本。");
            return false;
        }
        entry.code = line.substr(
            first_tab + 1,
            second_tab == std::string::npos ? std::string::npos
                                            : second_tab - first_tab - 1);
        if (second_tab != std::string::npos &&
            !ParseWeight(line.substr(second_tab + 1), &entry.weight)) {
            SetError(error_message, L"custom_words.tsv 第 " +
                                        std::to_wstring(line_number) +
                                        L" 行的权重必须是非负整数。");
            return false;
        }
        document->entries.push_back(std::move(entry));
    }
    return NormalizeCustomPhrases(document, error_message);
}

bool SaveCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument document,
                       std::wstring *error_message) {
    if (path.empty()) {
        SetError(error_message, L"无法确定自定义词典路径。");
        return false;
    }
    if (!NormalizeCustomPhrases(&document, error_message)) {
        return false;
    }
    std::error_code filesystem_error;
    std::filesystem::create_directories(path.parent_path(), filesystem_error);
    if (filesystem_error) {
        SetError(error_message, L"无法创建自定义词典目录。");
        return false;
    }
    std::filesystem::path temporary = path;
    temporary += L".tmp";
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output) {
        SetError(error_message, L"无法写入自定义词典临时文件。");
        return false;
    }
    output << "# 词条<Tab>编码<Tab>可选权重\n";
    for (const std::string &comment : document.comments) {
        if (comment != "# 词条<Tab>编码<Tab>可选权重") {
            output << comment << '\n';
        }
    }
    for (const CustomPhrase &entry : document.entries) {
        output << WideToUtf8(entry.text) << '\t' << entry.code;
        if (entry.weight) output << '\t' << *entry.weight;
        output << '\n';
    }
    output.close();
    if (!output) {
        std::filesystem::remove(temporary, filesystem_error);
        SetError(error_message, L"写入自定义词典失败，请检查磁盘空间。");
        return false;
    }
    if (!MoveFileExW(temporary.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        std::filesystem::remove(temporary, filesystem_error);
        SetError(error_message, L"保存失败，请确认 custom_words.tsv 未被占用。");
        return false;
    }
    if (error_message) error_message->clear();
    return true;
}

bool MergeCustomPhrases(CustomPhraseDocument *target,
                        CustomPhraseDocument imported,
                        CustomPhraseMergeResult *result,
                        std::wstring *error_message) {
    if (!target) {
        SetError(error_message, L"当前自定义词库不可用。");
        return false;
    }
    if (!NormalizeCustomPhrases(target, error_message) ||
        !NormalizeCustomPhrases(&imported, error_message)) {
        return false;
    }
    CustomPhraseMergeResult summary;
    std::unordered_map<std::string, size_t> existing;
    for (size_t index = 0; index < target->entries.size(); ++index) {
        const CustomPhrase &entry = target->entries[index];
        existing.emplace(WideToUtf8(entry.text) + '\0' + entry.code, index);
    }
    for (CustomPhrase &entry : imported.entries) {
        const std::string key = WideToUtf8(entry.text) + '\0' + entry.code;
        const auto found = existing.find(key);
        if (found == existing.end()) {
            existing.emplace(key, target->entries.size());
            target->entries.push_back(std::move(entry));
            ++summary.added;
        } else if (target->entries[found->second].weight != entry.weight) {
            target->entries[found->second].weight = entry.weight;
            ++summary.updated;
        } else {
            ++summary.unchanged;
        }
    }
    for (std::string &comment : imported.comments) {
        if (std::find(target->comments.begin(), target->comments.end(), comment) ==
            target->comments.end()) {
            target->comments.push_back(std::move(comment));
        }
    }
    if (result) *result = summary;
    if (error_message) error_message->clear();
    return true;
}

}  // namespace fengyu
#endif
