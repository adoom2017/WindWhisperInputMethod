#include "fy_engine.h"

#include <cstring>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

#ifndef FY_DICTIONARY_PATH
#define FY_DICTIONARY_PATH "Resources/fy.dict.yaml"
#endif

static bool Type(fy_session *session, const char *text) {
    for (; *text; ++text) {
        if (!fy_session_process_key(session, static_cast<unsigned char>(*text), 0)) {
            return false;
        }
    }
    return true;
}

static bool FirstIs(fy_session *session, const char *expected) {
    fy_snapshot snapshot{};
    if (!fy_session_snapshot(session, &snapshot) || snapshot.candidate_count == 0) {
        return false;
    }
    const fy_candidate &candidate = snapshot.candidates[0];
    return candidate.text_len == std::strlen(expected) &&
           std::memcmp(candidate.text, expected, candidate.text_len) == 0;
}

static bool Contains(fy_session *session, const char *expected) {
    fy_snapshot snapshot{};
    if (!fy_session_snapshot(session, &snapshot)) return false;
    for (size_t i = 0; i < snapshot.candidate_count; ++i) {
        if (snapshot.candidates[i].text_len == std::strlen(expected) &&
            std::memcmp(snapshot.candidates[i].text, expected,
                        snapshot.candidates[i].text_len) == 0) return true;
    }
    return false;
}

static bool CommitIs(fy_session *session, const char *expected) {
    fy_snapshot snapshot{};
    if (!fy_session_snapshot(session, &snapshot)) return false;
    return snapshot.commit_len == std::strlen(expected) &&
           std::memcmp(snapshot.commit, expected, snapshot.commit_len) == 0;
}
int main() {
    std::ifstream file(FY_DICTIONARY_PATH, std::ios::binary);
    if (!file) return 1;
    const std::string data((std::istreambuf_iterator<char>(file)), {});
    fy_engine *engine = fy_engine_create(data.data(), data.size());
    fy_session *session = fy_session_create(engine);
    if (!engine || !session) return 2;

    bool ok = Type(session, "nihao") && FirstIs(session, "你好");
    fy_session_reset(session);
    ok = ok && fy_session_select_schema(session, "flypyPhonetic", 13) &&
         Type(session, "nihc") && FirstIs(session, "你好");
    const char *phonetic_cases[][2] = {
        {"jbtmtmqihfhc", "今天天气很好"}, {"hduiyiyh", "还是一样"},
        {"womfkeyiyiqi", "我们可以一起"}, {"woxlycvege", "我想要这个"}};
    for (const auto &item : phonetic_cases) {
        fy_session_reset(session);
        ok = ok && Type(session, item[0]) && Contains(session, item[1]);
    }
    fy_session_reset(session);
    ok = ok && fy_session_select_schema(session, "flypyShape", 10) &&
         Type(session, "ubu") && FirstIs(session, "是不是");
    const char *shape_cases[][2] = {{"k", "可以"}, {"aj", "按键"},
                                    {"hvy", "呼之欲出"}, {"ahqi", "昂起"},
                                    {"anui", "按时"}, {"keyi", "可以"},
                                    {"quts", "趋同"}};
    for (const auto &item : shape_cases) {
        fy_session_reset(session);
        ok = ok && Type(session, item[0]) &&
             (Contains(session, item[1]) || CommitIs(session, item[1]));
    }
    fy_session_reset(session);
    ok = ok && Type(session, "ni") && fy_session_process_key(session, '~', 0);
    fy_snapshot reverse{};
    ok = ok && fy_session_snapshot(session, &reverse) && reverse.candidate_count > 0 &&
         reverse.candidates[0].comment_len > 0;
    ok = ok && Type(session, "r");
    fy_snapshot narrowed{};
    ok = ok && fy_session_snapshot(session, &narrowed) && narrowed.candidate_count > 0 &&
         narrowed.candidates[0].comment_len > 0;
    fy_session_reset(session);
    ok = ok && fy_session_select_schema(session, "fullPinyin", 10) &&
         fy_session_set_option(session, "traditional", 11, 1) &&
         Type(session, "hanzi") && fy_session_select_candidate(session, 0) &&
         CommitIs(session, "漢字");

    fy_session_destroy(session);
    fy_engine_destroy(engine);
    std::cout << (ok ? "dictionary smoke passed\n" : "dictionary smoke failed\n");
    return ok ? 0 : 3;
}
