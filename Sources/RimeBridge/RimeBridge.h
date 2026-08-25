#ifndef RIME_INPUT_METHOD_BRIDGE_H
#define RIME_INPUT_METHOD_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__clang__)
#pragma clang assume_nonnull begin
#endif

typedef struct RBService *RBServiceRef;
typedef uintptr_t RBSessionRef;

typedef enum RBResult {
  RB_RESULT_OK = 0,
  RB_RESULT_INVALID_ARGUMENT = 1,
  RB_RESULT_ALREADY_INITIALIZED = 2,
  RB_RESULT_API_UNAVAILABLE = 3,
  RB_RESULT_INITIALIZATION_FAILED = 4,
  RB_RESULT_DEPLOYMENT_FAILED = 5,
  RB_RESULT_SESSION_FAILED = 6,
  RB_RESULT_OUT_OF_MEMORY = 7
} RBResult;

typedef struct RBServiceConfiguration {
  const char *shared_data_dir;
  const char *user_data_dir;
  const char *prebuilt_data_dir;
  const char *staging_dir;
  const char *log_dir;
  const char *distribution_name;
  const char *distribution_code_name;
  const char *distribution_version;
  const char *app_name;
  int min_log_level;
} RBServiceConfiguration;

typedef struct RBCandidate {
  char *_Nullable text;
  char *_Nullable comment;
} RBCandidate;

typedef struct RBSnapshot {
  char *_Nullable commit_text;
  char *_Nullable preedit;
  size_t cursor_pos;
  size_t selection_start;
  size_t selection_end;
  int page_size;
  int page_number;
  int is_last_page;
  int highlighted_candidate_index;
  size_t candidate_count;
  RBCandidate *_Nullable candidates;
  char *_Nullable schema_id;
  char *_Nullable schema_name;
  int is_composing;
  int is_ascii_mode;
  int is_disabled;
} RBSnapshot;

RBResult rb_service_create(const RBServiceConfiguration *configuration,
                           RBServiceRef _Nullable *_Nonnull service,
                           char *_Nullable *_Nullable error_message);
void rb_service_destroy(RBServiceRef service);
const char *_Nullable rb_service_version(RBServiceRef service);
RBResult rb_service_deploy(RBServiceRef service,
                           int full_check,
                           char *_Nullable *_Nullable error_message);

RBResult rb_session_create(RBServiceRef service,
                           RBSessionRef *session,
                           char *_Nullable *_Nullable error_message);
void rb_session_destroy(RBServiceRef service, RBSessionRef session);
int rb_session_process_key(RBServiceRef service,
                           RBSessionRef session,
                           int keycode,
                           int modifier_mask);
int rb_session_simulate_key_sequence(RBServiceRef service,
                                     RBSessionRef session,
                                     const char *sequence);
int rb_session_commit_composition(RBServiceRef service, RBSessionRef session);
void rb_session_clear_composition(RBServiceRef service, RBSessionRef session);
int rb_session_select_candidate(RBServiceRef service,
                                RBSessionRef session,
                                size_t index);
int rb_session_select_schema(RBServiceRef service,
                             RBSessionRef session,
                             const char *schema_id);
int rb_session_set_option(RBServiceRef service,
                          RBSessionRef session,
                          const char *option,
                          int value);
int rb_session_get_option(RBServiceRef service,
                          RBSessionRef session,
                          const char *option,
                          int *value);

void rb_snapshot_init(RBSnapshot *snapshot);
void rb_snapshot_clear(RBSnapshot *snapshot);
RBResult rb_session_read_snapshot(RBServiceRef service,
                                  RBSessionRef session,
                                  RBSnapshot *snapshot,
                                  char *_Nullable *_Nullable error_message);

void rb_error_message_free(char *error_message);

#if defined(__clang__)
#pragma clang assume_nonnull end
#endif

#ifdef __cplusplus
}
#endif

#endif
