#include "CustomPhraseStore.h"

#include <windows.h>

#include <filesystem>
#include <fstream>

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

    // Importing replaces the whole list with the file's entries (a file
    // exported by macOS/iOS, or saved by Notepad with a BOM and CRLF).
    const std::filesystem::path import_path =
        std::filesystem::path(temporary_directory) /
        L"windwhisper-custom-phrase-import-test.tsv";
    {
        std::ofstream file(import_path, std::ios::binary);
        file << "\xEF\xBB\xBF# \xE8\xAF\x8D\xE6\x9D\xA1<Tab>\xE7\xBC\x96\xE7\xA0\x81<Tab>\xE5\x8F\xAF\xE9\x80\x89\xE6\x9D\x83\xE9\x87\x8D\r\n"
             << "\xE5\xAF\xBC\xE5\x85\xA5\xE8\xAF\x8D\xE7\xBB\x84\tdrcz\t4000000\r\n";
    }
    CHECK(fengyu::LoadCustomPhrases(import_path, &loaded, &error));
    CHECK(loaded.entries.size() == 1);
    CHECK(loaded.entries[0].text == L"导入词组");
    CHECK(loaded.entries[0].weight == 4000000);

    loaded.entries.push_back({L"风语输入法", "FY", std::nullopt});
    CHECK(!fengyu::NormalizeCustomPhrases(&loaded, &error));
    CHECK(!error.empty());

    std::error_code remove_error;
    std::filesystem::remove(path, remove_error);
    std::filesystem::remove(import_path, remove_error);
    return 0;
}
