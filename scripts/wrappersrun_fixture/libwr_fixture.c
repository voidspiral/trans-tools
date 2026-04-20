#include <stddef.h>

#ifndef WR_FIXTURE_MARKER
#define WR_FIXTURE_MARKER "WR_FIXTURE_UNKNOWN"
#endif

__attribute__((visibility("default"))) const char *wr_fixture_marker(void) {
  return WR_FIXTURE_MARKER;
}
