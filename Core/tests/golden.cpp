#include "fy_engine.h"

#include <cstring>
#include <iostream>

#define CHECK(condition)      \
    do {                      \
        if (!(condition)) {   \
            return __LINE__;  \
        }                     \
    } while (false)

namespace {
bool type(fy_session *session, const char *text) {
    for (; *text; ++text) {
        if (!fy_session_process_key(session, static_cast<unsigned char>(*text), 0)) {
            return false;
        }
    }
    return true;
}

bool equals(const char *text, size_t length, const char *expected) {
    return length == std::strlen(expected) &&
           std::memcmp(text, expected, length) == 0;
}
}

int main() {
    fy_engine *engine = fy_engine_create(nullptr, 0);
    CHECK(engine != nullptr);
    fy_session *session = fy_session_create(engine);
    CHECK(session != nullptr);

    for (const char *sequence : {"nihao", "haishiyiyang", "womenkeyiyiqi"}) {
        CHECK(type(session, sequence));
        fy_snapshot snapshot{};
        CHECK(fy_session_snapshot(session, &snapshot));
        CHECK(snapshot.candidate_count > 0);
        CHECK(fy_session_select_candidate(session, 0));
    }

    CHECK(type(session, "ni~"));
    fy_snapshot snapshot{};
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(snapshot.candidate_count > 0);
    CHECK(snapshot.candidates[0].comment_len == 4);
    fy_session_reset(session);

    CHECK(type(session, "ni"));
    CHECK(fy_session_process_key(session, '2', 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(equals(snapshot.commit, snapshot.commit_len, "倪"));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(snapshot.commit_len == 0);
    CHECK(fy_session_process_key(session, 'n', 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(snapshot.commit_len == 0);
    CHECK(fy_session_process_key(session, 0x1B, 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(!snapshot.is_composing);

    fy_session *other = fy_session_create(engine);
    CHECK(other != nullptr);
    CHECK(type(session, "nihao"));
    CHECK(type(other, "haishiyiyang"));
    fy_snapshot first_snapshot{};
    fy_snapshot other_snapshot{};
    CHECK(fy_session_snapshot(session, &first_snapshot));
    CHECK(fy_session_snapshot(other, &other_snapshot));
    CHECK(equals(first_snapshot.composition, first_snapshot.composition_len, "nihao"));
    CHECK(equals(other_snapshot.composition, other_snapshot.composition_len,
                 "haishiyiyang"));

    fy_session_reset(session);
    CHECK(type(session, "haishiyiyang"));
    CHECK(fy_session_set_option(session, "traditional", 11, 1));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(snapshot.candidate_count > 0);
    CHECK(equals(snapshot.candidates[0].text,
                 snapshot.candidates[0].text_len, "還是一樣"));
    CHECK(fy_session_select_candidate(session, 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(equals(snapshot.commit, snapshot.commit_len, "還是一樣"));

    fy_session_reset(session);
    CHECK(fy_session_set_option(session, "traditional", 11, 0));
    CHECK(fy_session_set_option(session, "full_shape", 10, 1));
    CHECK(fy_session_process_key(session, ',', 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(equals(snapshot.commit, snapshot.commit_len, "，"));
    CHECK(fy_session_process_key(session, '1', 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(equals(snapshot.commit, snapshot.commit_len, "１"));
    CHECK(type(session, "nihao"));
    CHECK(fy_session_process_key(session, '!', 0));
    CHECK(fy_session_snapshot(session, &snapshot));
    CHECK(equals(snapshot.commit, snapshot.commit_len, "你好！"));

    fy_session_destroy(other);
    fy_session_destroy(session);
    fy_engine_destroy(engine);
    std::cout << "cross-platform golden tests passed\n";
    return 0;
}
