#include "RimeBridge.h"

#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>

#include "rime_api.h"

struct RBService {
  RimeApi *api;
  int initialized;
  atomic_int deployment_state;
};

static RBServiceRef active_service = NULL;

static char *rb_copy_string(const char *source) {
  if (source == NULL) {
    return NULL;
  }
  size_t length = strlen(source);
  char *copy = (char *)malloc(length + 1);
  if (copy == NULL) {
    return NULL;
  }
  memcpy(copy, source, length + 1);
  return copy;
}

static RBResult rb_fail(RBResult result,
                        const char *message,
                        char **error_message) {
  if (error_message != NULL) {
    *error_message = rb_copy_string(message);
  }
  return result;
}

static int rb_service_is_valid(RBServiceRef service) {
  return service != NULL && service == active_service &&
         service->initialized && service->api != NULL;
}

static void rb_notification_handler(void *context_object,
                                    RimeSessionId session_id,
                                    const char *message_type,
                                    const char *message_value) {
  (void)session_id;
  RBServiceRef service = (RBServiceRef)context_object;
  if (service == NULL || message_type == NULL || message_value == NULL ||
      strcmp(message_type, "deploy") != 0) {
    return;
  }
  if (strcmp(message_value, "failure") == 0) {
    atomic_store(&service->deployment_state, -1);
  } else if (strcmp(message_value, "success") == 0) {
    atomic_store(&service->deployment_state, 1);
  }
}

RBResult rb_service_create(const RBServiceConfiguration *configuration,
                           RBServiceRef *service,
                           char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (configuration == NULL || service == NULL ||
      configuration->shared_data_dir == NULL ||
      configuration->user_data_dir == NULL ||
      configuration->app_name == NULL) {
    return rb_fail(RB_RESULT_INVALID_ARGUMENT,
                   "Missing required librime service configuration.",
                   error_message);
  }
  if (active_service != NULL) {
    return rb_fail(RB_RESULT_ALREADY_INITIALIZED,
                   "Only one librime service may be active in a process.",
                   error_message);
  }

  RimeApi *api = rime_get_api();
  if (api == NULL || !RIME_API_AVAILABLE(api, setup) ||
      !RIME_API_AVAILABLE(api, initialize) ||
      !RIME_API_AVAILABLE(api, finalize) ||
      !RIME_API_AVAILABLE(api, create_session) ||
      !RIME_API_AVAILABLE(api, destroy_session)) {
    return rb_fail(RB_RESULT_API_UNAVAILABLE,
                   "The loaded librime does not provide the required API.",
                   error_message);
  }

  RBServiceRef instance = (RBServiceRef)calloc(1, sizeof(struct RBService));
  if (instance == NULL) {
    return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                   "Unable to allocate the librime service.",
                   error_message);
  }

  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = configuration->shared_data_dir;
  traits.user_data_dir = configuration->user_data_dir;
  traits.prebuilt_data_dir = configuration->prebuilt_data_dir;
  traits.staging_dir = configuration->staging_dir;
  traits.log_dir = configuration->log_dir;
  traits.distribution_name = configuration->distribution_name;
  traits.distribution_code_name = configuration->distribution_code_name;
  traits.distribution_version = configuration->distribution_version;
  traits.app_name = configuration->app_name;
  traits.min_log_level = configuration->min_log_level;

  instance->api = api;
  atomic_init(&instance->deployment_state, 0);
  api->setup(&traits);
  if (RIME_API_AVAILABLE(api, set_notification_handler)) {
    api->set_notification_handler(rb_notification_handler, instance);
  }
  api->initialize(&traits);

  instance->initialized = 1;
  active_service = instance;
  *service = instance;
  return RB_RESULT_OK;
}

void rb_service_destroy(RBServiceRef service) {
  if (!rb_service_is_valid(service)) {
    return;
  }
  if (RIME_API_AVAILABLE(service->api, cleanup_all_sessions)) {
    service->api->cleanup_all_sessions();
  }
  if (RIME_API_AVAILABLE(service->api, set_notification_handler)) {
    service->api->set_notification_handler(NULL, NULL);
  }
  service->api->finalize();
  service->initialized = 0;
  active_service = NULL;
  free(service);
}

const char *rb_service_version(RBServiceRef service) {
  if (!rb_service_is_valid(service) ||
      !RIME_API_AVAILABLE(service->api, get_version)) {
    return NULL;
  }
  return service->api->get_version();
}

RBResult rb_service_deploy(RBServiceRef service,
                           int full_check,
                           char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (!rb_service_is_valid(service)) {
    return rb_fail(RB_RESULT_INVALID_ARGUMENT,
                   "The librime service is not active.",
                   error_message);
  }
  if (!RIME_API_AVAILABLE(service->api, start_maintenance) ||
      !RIME_API_AVAILABLE(service->api, join_maintenance_thread)) {
    return rb_fail(RB_RESULT_API_UNAVAILABLE,
                   "The loaded librime does not provide deployment APIs.",
                   error_message);
  }

  atomic_store(&service->deployment_state, 0);
  service->api->start_maintenance(full_check ? True : False);
  service->api->join_maintenance_thread();
  if (atomic_load(&service->deployment_state) < 0) {
    return rb_fail(RB_RESULT_DEPLOYMENT_FAILED,
                   "librime reported a deployment failure.",
                   error_message);
  }
  if (RIME_API_AVAILABLE(service->api, is_maintenance_mode) &&
      service->api->is_maintenance_mode()) {
    return rb_fail(RB_RESULT_DEPLOYMENT_FAILED,
                   "librime remained in maintenance mode after deployment.",
                   error_message);
  }
  return RB_RESULT_OK;
}

RBResult rb_session_create(RBServiceRef service,
                           RBSessionRef *session,
                           char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (!rb_service_is_valid(service) || session == NULL) {
    return rb_fail(RB_RESULT_INVALID_ARGUMENT,
                   "Cannot create a session without an active service.",
                   error_message);
  }
  RimeSessionId session_id = service->api->create_session();
  if (session_id == 0) {
    return rb_fail(RB_RESULT_SESSION_FAILED,
                   "librime did not create a session.",
                   error_message);
  }
  *session = (RBSessionRef)session_id;
  return RB_RESULT_OK;
}

void rb_session_destroy(RBServiceRef service, RBSessionRef session) {
  if (rb_service_is_valid(service) && session != 0) {
    service->api->destroy_session((RimeSessionId)session);
  }
}

int rb_session_process_key(RBServiceRef service,
                           RBSessionRef session,
                           int keycode,
                           int modifier_mask) {
  if (!rb_service_is_valid(service) || session == 0 ||
      !RIME_API_AVAILABLE(service->api, process_key)) {
    return 0;
  }
  return service->api->process_key((RimeSessionId)session, keycode,
                                   modifier_mask) != False;
}

int rb_session_simulate_key_sequence(RBServiceRef service,
                                     RBSessionRef session,
                                     const char *sequence) {
  if (!rb_service_is_valid(service) || session == 0 || sequence == NULL ||
      !RIME_API_AVAILABLE(service->api, simulate_key_sequence)) {
    return 0;
  }
  return service->api->simulate_key_sequence((RimeSessionId)session,
                                              sequence) != False;
}

int rb_session_commit_composition(RBServiceRef service, RBSessionRef session) {
  if (!rb_service_is_valid(service) || session == 0 ||
      !RIME_API_AVAILABLE(service->api, commit_composition)) {
    return 0;
  }
  return service->api->commit_composition((RimeSessionId)session) != False;
}

void rb_session_clear_composition(RBServiceRef service, RBSessionRef session) {
  if (rb_service_is_valid(service) && session != 0 &&
      RIME_API_AVAILABLE(service->api, clear_composition)) {
    service->api->clear_composition((RimeSessionId)session);
  }
}

int rb_session_select_candidate(RBServiceRef service,
                                RBSessionRef session,
                                size_t index) {
  if (!rb_service_is_valid(service) || session == 0 ||
      !RIME_API_AVAILABLE(service->api, select_candidate_on_current_page)) {
    return 0;
  }
  return service->api->select_candidate_on_current_page(
             (RimeSessionId)session, index) != False;
}

int rb_session_select_schema(RBServiceRef service,
                             RBSessionRef session,
                             const char *schema_id) {
  if (!rb_service_is_valid(service) || session == 0 || schema_id == NULL ||
      !RIME_API_AVAILABLE(service->api, get_schema_list) ||
      !RIME_API_AVAILABLE(service->api, free_schema_list) ||
      !RIME_API_AVAILABLE(service->api, select_schema)) {
    return 0;
  }
  RimeSchemaList schemas = {0};
  if (service->api->get_schema_list(&schemas) == False) {
    return 0;
  }
  int found = 0;
  for (size_t index = 0; index < schemas.size; ++index) {
    if (schemas.list[index].schema_id != NULL &&
        strcmp(schemas.list[index].schema_id, schema_id) == 0) {
      found = 1;
      break;
    }
  }
  service->api->free_schema_list(&schemas);
  if (!found) {
    return 0;
  }
  return service->api->select_schema((RimeSessionId)session, schema_id) != False;
}

void rb_snapshot_init(RBSnapshot *snapshot) {
  if (snapshot != NULL) {
    memset(snapshot, 0, sizeof(*snapshot));
  }
}

void rb_snapshot_clear(RBSnapshot *snapshot) {
  if (snapshot == NULL) {
    return;
  }
  free(snapshot->commit_text);
  free(snapshot->preedit);
  free(snapshot->schema_id);
  free(snapshot->schema_name);
  if (snapshot->candidates != NULL) {
    for (size_t index = 0; index < snapshot->candidate_count; ++index) {
      free(snapshot->candidates[index].text);
      free(snapshot->candidates[index].comment);
    }
    free(snapshot->candidates);
  }
  memset(snapshot, 0, sizeof(*snapshot));
}

static RBResult rb_copy_context(RBSnapshot *snapshot,
                                const RimeContext *context,
                                char **error_message) {
  if (context->composition.preedit != NULL) {
    snapshot->preedit = rb_copy_string(context->composition.preedit);
    if (snapshot->preedit == NULL) {
      return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                     "Unable to copy the composition snapshot.",
                     error_message);
    }
  }
  snapshot->cursor_pos = (size_t)context->composition.cursor_pos;
  snapshot->selection_start = (size_t)context->composition.sel_start;
  snapshot->selection_end = (size_t)context->composition.sel_end;
  snapshot->page_size = context->menu.page_size;
  snapshot->page_number = context->menu.page_no;
  snapshot->is_last_page = context->menu.is_last_page != False;
  snapshot->highlighted_candidate_index =
      context->menu.highlighted_candidate_index;

  if (context->menu.num_candidates <= 0) {
    return RB_RESULT_OK;
  }
  snapshot->candidate_count = (size_t)context->menu.num_candidates;
  snapshot->candidates = (RBCandidate *)calloc(snapshot->candidate_count,
                                               sizeof(RBCandidate));
  if (snapshot->candidates == NULL) {
    return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                   "Unable to allocate the candidate snapshot.",
                   error_message);
  }
  for (size_t index = 0; index < snapshot->candidate_count; ++index) {
    const RimeCandidate *source = &context->menu.candidates[index];
    snapshot->candidates[index].text = rb_copy_string(source->text);
    snapshot->candidates[index].comment = rb_copy_string(source->comment);
    if ((source->text != NULL && snapshot->candidates[index].text == NULL) ||
        (source->comment != NULL &&
         snapshot->candidates[index].comment == NULL)) {
      return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                     "Unable to copy a candidate snapshot.",
                     error_message);
    }
  }
  return RB_RESULT_OK;
}

static RBResult rb_copy_status(RBSnapshot *snapshot,
                               const RimeStatus *status,
                               char **error_message) {
  snapshot->schema_id = rb_copy_string(status->schema_id);
  snapshot->schema_name = rb_copy_string(status->schema_name);
  if ((status->schema_id != NULL && snapshot->schema_id == NULL) ||
      (status->schema_name != NULL && snapshot->schema_name == NULL)) {
    return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                   "Unable to copy the status snapshot.",
                   error_message);
  }
  snapshot->is_composing = status->is_composing != False;
  snapshot->is_ascii_mode = status->is_ascii_mode != False;
  snapshot->is_disabled = status->is_disabled != False;
  return RB_RESULT_OK;
}

RBResult rb_session_read_snapshot(RBServiceRef service,
                                  RBSessionRef session,
                                  RBSnapshot *snapshot,
                                  char **error_message) {
  if (error_message != NULL) {
    *error_message = NULL;
  }
  if (!rb_service_is_valid(service) || session == 0 || snapshot == NULL) {
    return rb_fail(RB_RESULT_INVALID_ARGUMENT,
                   "Cannot read a snapshot from an invalid session.",
                   error_message);
  }

  rb_snapshot_clear(snapshot);

  RIME_STRUCT(RimeCommit, commit);
  if (RIME_API_AVAILABLE(service->api, get_commit) &&
      service->api->get_commit((RimeSessionId)session, &commit)) {
    int had_commit_text = commit.text != NULL;
    snapshot->commit_text = rb_copy_string(commit.text);
    service->api->free_commit(&commit);
    if (had_commit_text && snapshot->commit_text == NULL) {
      rb_snapshot_clear(snapshot);
      return rb_fail(RB_RESULT_OUT_OF_MEMORY,
                     "Unable to copy committed text.",
                     error_message);
    }
  }

  RIME_STRUCT(RimeContext, context);
  if (RIME_API_AVAILABLE(service->api, get_context) &&
      service->api->get_context((RimeSessionId)session, &context)) {
    RBResult result = rb_copy_context(snapshot, &context, error_message);
    service->api->free_context(&context);
    if (result != RB_RESULT_OK) {
      rb_snapshot_clear(snapshot);
      return result;
    }
  }

  RIME_STRUCT(RimeStatus, status);
  if (RIME_API_AVAILABLE(service->api, get_status) &&
      service->api->get_status((RimeSessionId)session, &status)) {
    RBResult result = rb_copy_status(snapshot, &status, error_message);
    service->api->free_status(&status);
    if (result != RB_RESULT_OK) {
      rb_snapshot_clear(snapshot);
      return result;
    }
  }

  return RB_RESULT_OK;
}

void rb_error_message_free(char *error_message) {
  free(error_message);
}
