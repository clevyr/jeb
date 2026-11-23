#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int c, char **v) {
  const char *log = getenv("JEB_STUB_LOG"), *rc = getenv("JEB_STUB_RC"), *flip = getenv("JEB_STUB_FLIP");
  if (log) { FILE *f = fopen(log, "a"); if (f) { for (int i = 0; i < c; i++) fprintf(f, "%s%s", i ? " " : "", v[i]); fputc('\n', f); fclose(f); } }
  int code = rc ? atoi(rc) : 0;
  if (flip && code == 0 && c > 2 && !strcmp(v[1], "apply")) {
    char tmp[4096], rel[4096], *b = strrchr(v[2], '/');
    snprintf(tmp, sizeof tmp, "%s.new", flip); snprintf(rel, sizeof rel, "versions/%s", b ? b + 1 : v[2]);
    unlink(tmp); if (symlink(rel, tmp) == 0) rename(tmp, flip);
  }
  return code;
}
