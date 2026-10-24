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

std::filesystem::path CustomPhraseFilePath();
bool NormalizeCustomPhrases(CustomPhraseDocument *document,
                            std::wstring *error_message);
bool LoadCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument *document,
                       std::wstring *error_message);
bool SaveCustomPhrases(const std::filesystem::path &path,
                       CustomPhraseDocument document,
                       std::wstring *error_message);

}  // namespace fengyu
#endif
