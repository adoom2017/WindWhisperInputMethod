#include "fy_engine.h"
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#define CHECK(value) do { if (!(value)) throw std::runtime_error("line " + std::to_string(__LINE__)); } while (false)

static void type(fy_session *session, const std::string &code) {
    for (auto c : code) CHECK(fy_session_process_key(session, static_cast<unsigned char>(c), 0));
}
static std::string first(fy_engine *engine, const char *schema, const char *code = "d", bool traditional = false) {
    auto *session = fy_session_create(engine);
    CHECK(fy_session_select_schema(session, schema, std::strlen(schema)));
    CHECK(fy_session_set_option(session, "traditional", 11, traditional));
    type(session, code);
    fy_snapshot snapshot{};
    CHECK(fy_session_snapshot(session, &snapshot));
    const auto result = snapshot.candidate_count == 0 ? std::string() :
        std::string(snapshot.candidates[0].text, snapshot.candidates[0].text_len);
    fy_session_destroy(session);
    return result;
}
static void choose(fy_engine *engine, const char *schema, const std::string &text, bool traditional = false) {
    auto *session = fy_session_create(engine);
    CHECK(fy_session_select_schema(session, schema, std::strlen(schema)));
    CHECK(fy_session_set_option(session, "traditional", 11, traditional));
    type(session, "d");
    for (;;) {
        fy_snapshot snapshot{};
        CHECK(fy_session_snapshot(session, &snapshot));
        for (size_t i = 0; i < snapshot.candidate_count; ++i) {
            if (std::string(snapshot.candidates[i].text, snapshot.candidates[i].text_len) != text) continue;
            CHECK(fy_session_select_candidate(session, i));
            CHECK(fy_session_snapshot(session, &snapshot));
            CHECK(std::string(snapshot.commit, snapshot.commit_len) == text);
            fy_session_destroy(session);
            return;
        }
        CHECK(fy_session_page(session, 1));
    }
}
static std::string read(const std::filesystem::path &path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
int main() {
    const auto root = std::filesystem::temp_directory_path() /
        std::filesystem::u8path("风语-frequency-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    try {
        const auto path = root.u8string();
        std::string dictionary;
        const std::vector<std::string> words = {"的", "地", "得", "等", "大", "到", "道", "电", "点", "东", "动", "定"};
        for (size_t i = 0; i < words.size(); ++i) {
            dictionary += words[i] + "\tde\t" + std::to_string(1000 - i) + "\tpinyin\t" + std::to_string(i) + "\n";
            dictionary += words[i] + "\tda\t" + std::to_string(1000 - i) + "\tflypy\t" + std::to_string(i) + "\n";
        }
        dictionary += "的\td\t2000\tflypy\t20\n";
        auto make = [&] {
            auto *engine = fy_engine_create(dictionary.data(), dictionary.size());
            CHECK(fy_engine_set_user_data_path(engine, path.data(), path.size()));
            return engine;
        };
        auto *engine = make();
        auto *other = make();
        for (const char *schema : {"fullPinyin", "flypyPhonetic", "flypyShape"}) {
            CHECK(first(engine, schema) == "的");
            choose(engine, schema, "电"); // Second-page candidate, below an exact shape code.
            CHECK(first(engine, schema) == "电");
            CHECK(first(other, schema) == "电");
            if (std::strcmp(schema, "flypyShape") != 0) CHECK(first(engine, schema, "de") == "的");
            choose(other, schema, "地");
            CHECK(first(engine, schema) == "地"); // Equal counts retain base order.
            choose(engine, schema, "電", true);
            CHECK(first(engine, schema) == "电");
            CHECK(first(engine, schema, "d", true) == "電");
            auto *restored = make();
            CHECK(first(restored, schema) == "电");
            fy_engine_destroy(restored);
            const auto before = read(root / "user_frequency.tsv");
            auto *session = fy_session_create(engine);
            CHECK(fy_session_select_schema(session, schema, std::strlen(schema)));
            type(session, "d");
            CHECK(!fy_session_select_candidate(session, 9999));
            CHECK(fy_session_process_key(session, 0xFF1B, 0));
            type(session, "vvvvvv");
            CHECK(fy_session_process_key(session, 0xFF0D, 0));
            CHECK(read(root / "user_frequency.tsv") == before);
            fy_session_destroy(session);
            std::cout << "PASS learning " << schema << '\n';
        }
        // Two independent engine instances, mirroring concurrent TSF hosts.
        std::thread a([&] { for (int i = 0; i < 10; ++i) choose(engine, "fullPinyin", "电"); });
        std::thread b([&] { for (int i = 0; i < 10; ++i) choose(other, "fullPinyin", "电"); });
        a.join(); b.join();
        CHECK(read(root / "user_frequency.tsv").find("fullPinyin\td\t电\t22\n") != std::string::npos);
        CHECK(first(engine, "flypy", "d") == "电"); // Legacy shape alias shares history.
        fy_engine_destroy(other);
        fy_engine_destroy(engine);
        { std::ofstream output(root / "user_frequency.tsv", std::ios::app);
          output << "broken\nfullPinyin\td\t的\t-1\nfullPinyin\td\t的\t99999999999999999999\n"; }
        engine = make();
        CHECK(first(engine, "fullPinyin") == "电");
        fy_engine_destroy(engine);
        std::filesystem::remove_all(root);
        std::cout << "PASS persistence, concurrent writers, malformed history, UTF-8 path\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        std::filesystem::remove_all(root);
        return 1;
    }
}
