#ifndef AETHER_SCREENS_CATALOG_H
#define AETHER_SCREENS_CATALOG_H
#include <stdint.h>
/* Read-only catalog conversion. Caller provides a 104-byte output buffer. */
int32_t ae_collect_catalog(const char *path, uint16_t level, uint8_t output[104]);
/* Restores dates/Finder/encoding only. Does not set permissions or lock flags. */
int32_t ae_restore_catalog_metadata(int descriptor, const uint8_t header[104]);
#endif
