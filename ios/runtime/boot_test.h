#pragma once
#include <stddef.h>
/* Synchronous single-shot fixture boot; caller must be a background thread.
 * All guest execution itself uses a dedicated 16 MiB host thread. */
int ws_boot_test(const char *images, char *report, size_t capacity);
