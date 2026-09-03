#include "CustomPhraseStore.h"

#include <windows.h>

#include <filesystem>

#define CHECK(condition)    \
    do {                    \
        if (!(condition)) { \
            return __LINE__; \
        }                   \
    } while (false)

int wmain() {
    wchar_t temporary_directory[MAX_PATH]{};
    CHECK(GetTempPathW(MAX_PATH, temporary_directory) > 0);
    const std::filesystem::path path =
        std::filesystem::path(temporary_directory) /
        L"windwhisper-custom-phrase-store-test.tsv";

    fengyu::CustomPhraseDocument document;
    document.comments.push_back("# preserved comment");
    document.entries.push_back({L"风语输入法", "FY", 3000000});
    document.entries.push_back({L"自定义词组", "zdycz", std::nullopt});
    std::wstring error;
    CHECK(fengyu::SaveCustomPhrases(path, document, &error));

    fengyu::CustomPhraseDocument loaded;
    CHECK(fengyu::LoadCustomPhrases(path, &loaded, &error));
    CHECK(loaded.entries.size() == 2);
    CHECK(loaded.entries[0].text == L"风语输入法");
    CHECK(loaded.entries[0].code == "fy");
    CHECK(loaded.entries[0].weight == 3000000);
    CHECK(loaded.entries[1].code == "zdycz");
    CHECK(!loaded.entries[1].weight.has_value());

    fengyu::CustomPhraseDocument imported;
    imported.entries.push_back({L"风语输入法", "fy", 4000000});
    imported.entries.push_back({L"导入词组", "drcz", std::nullopt});
    fengyu::CustomPhraseMergeResult merge;
    CHECK(fengyu::MergeCustomPhrases(&loaded, imported, &merge, &error));
    CHECK(merge.added == 1);
    CHECK(merge.updated == 1);
    CHECK(merge.unchanged == 0);
    CHECK(loaded.entries.size() == 3);
    CHECK(loaded.entries[0].weight == 4000000);

    loaded.entries.push_back({L"风语输入法", "FY", std::nullopt});
    CHECK(!fengyu::NormalizeCustomPhrases(&loaded, &error));
    CHECK(!error.empty());

    std::error_code remove_error;
    std::filesystem::remove(path, remove_error);
    return 0;
}
