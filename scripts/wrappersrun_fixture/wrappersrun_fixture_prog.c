#include <stdio.h>

const char *wr_fixture_marker(void);

int main(void) {
  const char *m = wr_fixture_marker();
  printf("STAGE=fixture-provenance\n");
  printf("WRAPPER_FIXTURE_MARKER=%s\n", m);
  fflush(stdout);
  return 0;
}
