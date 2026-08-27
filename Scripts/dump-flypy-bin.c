#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "rime_api.h"

static int make_directory(const char *path) {
  if (mkdir(path, 0700) == 0 || errno == EEXIST) {
    return 1;
  }
  fprintf(stderr, "cannot create %s: %s\n", path, strerror(errno));
  return 0;
}

static int copy_file(const char *source_path, const char *destination_path) {
  FILE *source = fopen(source_path, "rb");
  if (source == NULL) {
    fprintf(stderr, "cannot open %s: %s\n", source_path, strerror(errno));
    return 0;
  }
  FILE *destination = fopen(destination_path, "wb");
  if (destination == NULL) {
    fprintf(stderr, "cannot open %s: %s\n", destination_path,
            strerror(errno));
    fclose(source);
    return 0;
  }

  char buffer[65536];
  int succeeded = 1;
  size_t bytes_read;
  while ((bytes_read = fread(buffer, 1, sizeof(buffer), source)) > 0) {
    if (fwrite(buffer, 1, bytes_read, destination) != bytes_read) {
      fprintf(stderr, "cannot write %s: %s\n", destination_path,
              strerror(errno));
      succeeded = 0;
      break;
    }
  }
  if (ferror(source)) {
    fprintf(stderr, "cannot read %s: %s\n", source_path, strerror(errno));
    succeeded = 0;
  }
  if (fclose(destination) != 0) {
    fprintf(stderr, "cannot finish %s: %s\n", destination_path,
            strerror(errno));
    succeeded = 0;
  }
  fclose(source);
  return succeeded;
}

static int install_isolated_schema_patch(const char *user_data) {
  char path[4096];
  if (snprintf(path, sizeof(path), "%s/flypy.custom.yaml", user_data) >=
      (int)sizeof(path)) {
    return 0;
  }
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    fprintf(stderr, "cannot open %s: %s\n", path, strerror(errno));
    return 0;
  }
  const char *patch =
      "patch:\n"
      "  engine/translators:\n"
      "    - table_translator\n"
      "  engine/filters: []\n"
      "  speller/auto_select: false\n"
      "  translator/enable_sentence: false\n"
      "  translator/enable_completion: false\n"
      "  translator/enable_user_dict: false\n";
  int succeeded = fputs(patch, file) >= 0;
  if (fclose(file) != 0) {
    succeeded = 0;
  }
  if (!succeeded) {
    fprintf(stderr, "cannot write %s: %s\n", path, strerror(errno));
  }
  return succeeded;
}

static int deploy_data(RimeApi *api,
                       const char *prebuilt_data,
                       const char *staging_dir,
                       int restore_flypy_bins) {
  if (!api->start_maintenance(True)) {
    fprintf(stderr, "librime did not start deployment\n");
    return 0;
  }
  api->join_maintenance_thread();

  if (!restore_flypy_bins) {
    return 1;
  }

  static const char *file_names[] = {
      "flypy.table.bin", "flypy.prism.bin", "flypy.reverse.bin"};
  for (size_t index = 0; index < sizeof(file_names) / sizeof(file_names[0]);
       ++index) {
    char source[4096];
    char destination[4096];
    if (snprintf(source, sizeof(source), "%s/%s", prebuilt_data,
                 file_names[index]) >= (int)sizeof(source) ||
        snprintf(destination, sizeof(destination), "%s/%s", staging_dir,
                 file_names[index]) >= (int)sizeof(destination) ||
        !copy_file(source, destination)) {
      return 0;
    }
  }
  return 1;
}

static int write_candidates(RimeApi *api,
                            RimeSessionId session,
                            FILE *output,
                            const char *code,
                            size_t *entry_count) {
  api->clear_composition(session);
  if (!api->set_input(session, code)) {
    return 1;
  }

  RimeCandidateListIterator iterator = {0};
  if (!api->candidate_list_begin(session, &iterator)) {
    return 1;
  }

  while (api->candidate_list_next(&iterator)) {
    if (iterator.candidate.text == NULL || iterator.candidate.text[0] == '\0') {
      continue;
    }
    fprintf(output, "%s\t%s\n", iterator.candidate.text, code);
    ++*entry_count;
  }
  api->candidate_list_end(&iterator);
  return 1;
}

static int enumerate_codes(RimeApi *api,
                           RimeSessionId session,
                           FILE *output,
                           char *code,
                           int position,
                           int length,
                           size_t *code_count,
                           size_t *entry_count) {
  if (position == length) {
    code[length] = '\0';
    ++*code_count;
    return write_candidates(api, session, output, code, entry_count);
  }

  for (char letter = 'a'; letter <= 'z'; ++letter) {
    code[position] = letter;
    if (!enumerate_codes(api, session, output, code, position + 1, length,
                         code_count, entry_count)) {
      return 0;
    }
  }
  return 1;
}

static void usage(const char *program) {
  fprintf(stderr,
          "Usage: %s SHARED_DATA USER_DATA OUTPUT [CODE ...]\n"
          "With CODE arguments, dumps only those codes. Without them, enumerates "
          "a-z codes of length 1 through 4.\n",
          program);
}

int main(int argc, char **argv) {
  if (argc < 4) {
    usage(argv[0]);
    return 64;
  }

  const char *shared_data = argv[1];
  const char *user_data = argv[2];
  const char *output_path = argv[3];
  char staging_dir[4096];
  char log_dir[4096];
  if (snprintf(staging_dir, sizeof(staging_dir), "%s/build", user_data) >=
          (int)sizeof(staging_dir) ||
      snprintf(log_dir, sizeof(log_dir), "%s/log", user_data) >=
          (int)sizeof(log_dir)) {
    fprintf(stderr, "user data path is too long\n");
    return 64;
  }
  if (!make_directory(user_data) || !make_directory(staging_dir) ||
      !make_directory(log_dir) || !install_isolated_schema_patch(user_data)) {
    return 1;
  }

  char prebuilt_data[4096];
  if (snprintf(prebuilt_data, sizeof(prebuilt_data), "%s/build", shared_data) >=
      (int)sizeof(prebuilt_data)) {
    fprintf(stderr, "shared data path is too long\n");
    return 64;
  }

  RimeApi *api = rime_get_api();
  if (api == NULL || !RIME_API_AVAILABLE(api, setup) ||
      !RIME_API_AVAILABLE(api, initialize) ||
      !RIME_API_AVAILABLE(api, finalize) ||
      !RIME_API_AVAILABLE(api, create_session) ||
      !RIME_API_AVAILABLE(api, destroy_session) ||
      !RIME_API_AVAILABLE(api, start_maintenance) ||
      !RIME_API_AVAILABLE(api, join_maintenance_thread) ||
      !RIME_API_AVAILABLE(api, select_schema) ||
      !RIME_API_AVAILABLE(api, set_input) ||
      !RIME_API_AVAILABLE(api, clear_composition) ||
      !RIME_API_AVAILABLE(api, candidate_list_begin) ||
      !RIME_API_AVAILABLE(api, candidate_list_next) ||
      !RIME_API_AVAILABLE(api, candidate_list_end)) {
    fprintf(stderr, "required librime API is unavailable\n");
    return 1;
  }

  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared_data;
  traits.user_data_dir = user_data;
  traits.prebuilt_data_dir = prebuilt_data;
  traits.staging_dir = staging_dir;
  traits.log_dir = log_dir;
  traits.distribution_name = "flypy-bin-dump";
  traits.distribution_code_name = "flypy-bin-dump";
  traits.distribution_version = "1";
  traits.app_name = "flypy.bin_dump";
  traits.min_log_level = 2;

  api->setup(&traits);
  api->initialize(&traits);

  int restore_flypy_bins = getenv("FLYPY_DUMP_COMPILE_SOURCE") == NULL;
  if (!deploy_data(api, prebuilt_data, staging_dir, restore_flypy_bins)) {
    api->finalize();
    return 1;
  }

  int result = 1;
  RimeSessionId session = api->create_session();
  if (session == 0 || !api->select_schema(session, "flypy")) {
    fprintf(stderr, "cannot create a flypy session\n");
    goto cleanup;
  }

  FILE *output = fopen(output_path, "w");
  if (output == NULL) {
    fprintf(stderr, "cannot open %s: %s\n", output_path, strerror(errno));
    goto cleanup;
  }
  fprintf(output,
          "# Extracted through librime's public candidate API.\n"
          "# Columns: text and code. Per-code line order preserves candidate rank.\n"
          "---\n"
          "name: flypy\n"
          "version: \"1\"\n"
          "sort: original\n"
          "use_preset_vocabulary: false\n"
          "...\n");

  size_t code_count = 0;
  size_t entry_count = 0;
  if (argc > 4) {
    for (int index = 4; index < argc; ++index) {
      ++code_count;
      if (!write_candidates(api, session, output, argv[index], &entry_count)) {
        fprintf(stderr, "failed to query code: %s\n", argv[index]);
        fclose(output);
        goto cleanup;
      }
    }
  } else {
    char code[5];
    for (int length = 1; length <= 4; ++length) {
      if (!enumerate_codes(api, session, output, code, 0, length, &code_count,
                           &entry_count)) {
        fprintf(stderr, "candidate enumeration failed\n");
        fclose(output);
        goto cleanup;
      }
      fprintf(stderr, "finished length %d: %zu codes, %zu entries\n", length,
              code_count, entry_count);
    }
  }

  if (fclose(output) != 0) {
    fprintf(stderr, "cannot finish %s: %s\n", output_path, strerror(errno));
    goto cleanup;
  }
  fprintf(stderr, "dumped %zu entries from %zu codes to %s\n", entry_count,
          code_count, output_path);
  result = 0;

cleanup:
  if (session != 0) {
    api->destroy_session(session);
  }
  api->finalize();
  return result;
}
