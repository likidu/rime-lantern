/* rime_probe: headless librime session for tests.
 * Usage: rime_probe --user DIR --shared DIR --schema ID [--option NAME=0|1]... KEYS
 * Prints one line per candidate on the first page: text<TAB>comment
 * Build: cc -O -o rime_probe rime_probe.c -lrime
 */
#include <rime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  const char *user = NULL, *shared = NULL, *schema = NULL, *keys = NULL;
  const char *opts[32]; int nopts = 0;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--user") && i + 1 < argc) user = argv[++i];
    else if (!strcmp(argv[i], "--shared") && i + 1 < argc) shared = argv[++i];
    else if (!strcmp(argv[i], "--schema") && i + 1 < argc) schema = argv[++i];
    else if (!strcmp(argv[i], "--option") && i + 1 < argc && nopts < 32) opts[nopts++] = argv[++i];
    else keys = argv[i];
  }
  if (!user || !shared || !schema || !keys) {
    fprintf(stderr, "usage: rime_probe --user DIR --shared DIR --schema ID [--option NAME=0|1] KEYS\n");
    return 2;
  }
  RimeApi *rime = rime_get_api();
  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = shared;
  traits.user_data_dir = user;
  traits.log_dir = user;
  traits.app_name = "rime.probe";
  traits.distribution_name = "rime-lantern probe";
  traits.distribution_code_name = "rime-probe";
  traits.distribution_version = "0.1";
  traits.min_log_level = 0;
  rime->setup(&traits);
  rime->initialize(NULL);
  if (rime->start_maintenance(True)) rime->join_maintenance_thread();
  RimeSessionId sid = rime->create_session();
  if (!sid) { fprintf(stderr, "no session\n"); return 1; }
  if (!rime->select_schema(sid, schema)) { fprintf(stderr, "schema %s not found\n", schema); return 1; }
  for (int i = 0; i < nopts; i++) {
    char name[64]; const char *eq = strchr(opts[i], '=');
    size_t n = eq ? (size_t)(eq - opts[i]) : strlen(opts[i]);
    if (n >= sizeof name) n = sizeof name - 1;
    memcpy(name, opts[i], n); name[n] = 0;
    rime->set_option(sid, name, eq ? atoi(eq + 1) != 0 : True);
  }
  if (!rime->simulate_key_sequence(sid, keys)) { fprintf(stderr, "bad key sequence\n"); return 1; }
  RIME_STRUCT(RimeContext, ctx);
  if (rime->get_context(sid, &ctx)) {
    for (int i = 0; i < ctx.menu.num_candidates; i++)
      printf("%s\t%s\n", ctx.menu.candidates[i].text,
             ctx.menu.candidates[i].comment ? ctx.menu.candidates[i].comment : "");
    rime->free_context(&ctx);
  }
  rime->destroy_session(sid);
  rime->finalize();
  return 0;
}
