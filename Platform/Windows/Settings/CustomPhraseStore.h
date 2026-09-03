#pragma once

#ifdef _WIN32
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace fengyu {

struct CustomPhrase {
    std::wstring text;
    std::string code;
    std::optional<int> weight;
};

struct CustomPhraseDocument {
    std::vector<std::string> comments;
    std::vector<CustomPhrase> entries;
};

struct CustomPhraseMergeResult {
    size_t added = 0;
    size_t updated = 0;
    size_t unchanged = 0;
};

std::filesystem::path CustomPhraseFilePath();
bool NormalizeCustomPhrases(CustomPhraseDocument *document,
                            std::wstring *error_message);
bool LoadCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument *document,
                       std::wstring *error_message);
bool SaveCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument document,
                       std::wstring *error_message);
bool MergeCustomPhrases(CustomPhraseDocument *target,
                        CustomPhraseDocument imported,
                        CustomPhraseMergeResult *result,
                        std::wstring *error_message);

}  // namespace fengyu
#endif
