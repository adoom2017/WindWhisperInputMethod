#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
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

FY_API fy_engine *fy_engine_create(const char *dictionary_utf8, size_t length);
FY_API void fy_engine_destroy(fy_engine *engine);
FY_API fy_session *fy_session_create(fy_engine *engine);
FY_API void fy_session_destroy(fy_session *session);
FY_API void fy_session_reset(fy_session *session);
FY_API int fy_session_process_key(fy_session *session, uint32_t key, uint32_t modifiers);
FY_API int fy_session_select_candidate(fy_session *session, size_t index);
FY_API int fy_session_page(fy_session *session, int delta);
FY_API int fy_session_set_option(fy_session *session, const char *name, size_t name_len, int value);
FY_API int fy_session_select_schema(fy_session *session, const char *schema, size_t schema_len);
FY_API int fy_session_snapshot(fy_session *session, fy_snapshot *out);
FY_API void fy_snapshot_free(fy_snapshot *snapshot);

#ifdef __cplusplus
}
#endif
