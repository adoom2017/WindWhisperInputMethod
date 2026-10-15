#pragma once

#include <stdint.h>
#include <stddef.h>

#if defined(FY_ENGINE_STATIC)
#  define FY_API
#elif defined(_WIN32)
#  ifdef FY_ENGINE_BUILD
#    define FY_API __declspec(dllexport)
#  else
#    define FY_API __declspec(dllimport)
#  endif
#else
#  define FY_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fy_engine fy_engine;
typedef struct fy_session fy_session;

typedef struct fy_candidate {
    const char *text; size_t text_len;
    const char *comment; size_t comment_len;
} fy_candidate;

typedef struct fy_snapshot {
    const char *commit; size_t commit_len;
    const char *composition; size_t composition_len;
    size_t cursor;
    const fy_candidate *candidates; size_t candidate_count;
    size_t page; size_t page_count; size_t highlighted;
    int is_last_page; int is_composing; int ascii_mode;
} fy_snapshot;

// Snapshot strings and candidate arrays are owned by the session and remain
// valid until the next call that mutates or snapshots that session. A commit is
// delivered by exactly one successful snapshot.

// Returns NULL when the dictionary contains no usable entries.
FY_API fy_engine *fy_engine_create(const char *dictionary_utf8, size_t length);
// Configure before creating sessions. UTF-8 directory; history is shared by
// processes using that directory. Without a path, learning is memory-only.
FY_API int fy_engine_set_user_data_path(fy_engine *engine, const char *path, size_t length);
FY_API void fy_engine_destroy(fy_engine *engine);
FY_API fy_session *fy_session_create(fy_engine *engine);
FY_API void fy_session_destroy(fy_session *session);
FY_API void fy_session_reset(fy_session *session);
FY_API int fy_session_process_key(fy_session *session, uint32_t key, uint32_t modifiers);
FY_API int fy_session_select_candidate(fy_session *session, size_t index);
FY_API int fy_session_page(fy_session *session, int delta);
// Tells the session that the host received text without going through it
// (keys the engine passed through), so context rules such as "3." keeping a
// half-width period still apply. An empty text clears that context.
FY_API void fy_session_note_host_text(fy_session *session, const char *text, size_t length);
// Options: "traditional", "full_shape" (full-width letters, digits and
// symbols), "ascii_punct" (English instead of Chinese punctuation), and the
// per-key Chinese forms "punct_bracket" ([ ] → 【】), "punct_angle" (< > → 《》),
// "punct_backslash" (\ → 、), "punct_caret" (^ → ……), "punct_underscore"
// (_ → ——), all on by default, plus "punct_yuan" ($ → ￥), off by default.
FY_API int fy_session_set_option(fy_session *session, const char *name, size_t name_len, int value);
FY_API int fy_session_select_schema(fy_session *session, const char *schema, size_t schema_len);
FY_API int fy_session_snapshot(fy_session *session, fy_snapshot *out);

#ifdef __cplusplus
}
#endif
