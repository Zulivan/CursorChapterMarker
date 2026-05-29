#pragma once

#include <obs-module.h>

#define PLUGIN_NAME    "cursor-chapter-marker"
#define PLUGIN_VERSION "1.0.0"

#define obs_log(level, format, ...) \
    blog(level, "[" PLUGIN_NAME "] " format, ##__VA_ARGS__)
