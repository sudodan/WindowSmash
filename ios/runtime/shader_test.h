#pragma once
#include <stddef.h>
/* Call once, on a background thread. 77 means no usable Metal device/queue. */
int ws_shader_test(char *report, size_t capacity);
