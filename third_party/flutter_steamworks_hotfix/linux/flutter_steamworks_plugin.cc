#include "include/flutter_steamworks/flutter_steamworks_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <vector>

#include <glib.h>

#include "flutter_steamworks_plugin_private.h"

#define FLUTTER_STEAMWORKS_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_steamworks_plugin_get_type(), \
                              FlutterSteamworksPlugin))

struct _FlutterSteamworksPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterSteamworksPlugin, flutter_steamworks_plugin, g_object_get_type())

namespace {

using SteamAPIInitFn = bool (*)();
using SteamAPIInitFlatFn = int (*)(void *);
using SteamAPIShutdownFn = void (*)();

struct SteamRuntime {
  void *handle = nullptr;
  SteamAPIInitFn init_fn = nullptr;
  SteamAPIInitFlatFn init_flat_fn = nullptr;
  SteamAPIShutdownFn shutdown_fn = nullptr;
  bool initialized = false;
};

SteamRuntime &GetSteamRuntime() {
  static SteamRuntime runtime;
  return runtime;
}

std::vector<std::string> BuildSteamLibraryCandidates() {
  static const char *kNames[] = {
      "libsteam_api.so", "steam_api.so", "libsteam_api.so.1", "steam_api64.so"};

  std::vector<std::string> paths;

  Dl_info info;
  if (dladdr(reinterpret_cast<void *>(BuildSteamLibraryCandidates), &info) != 0 &&
      info.dli_fname != nullptr) {
    g_autofree gchar *dir = g_path_get_dirname(info.dli_fname);
    if (dir != nullptr) {
      for (const char *name : kNames) {
        paths.emplace_back(std::string(dir) + G_DIR_SEPARATOR_S + name);
      }
    }
  }

  for (const char *name : kNames) {
    paths.emplace_back(name);
  }

  return paths;
}

bool EnsureSteamLibraryLoaded() {
  SteamRuntime &runtime = GetSteamRuntime();
  if (runtime.handle != nullptr) {
    return (runtime.init_fn != nullptr || runtime.init_flat_fn != nullptr) &&
           runtime.shutdown_fn != nullptr;
  }

  const std::vector<std::string> candidates = BuildSteamLibraryCandidates();
  for (const std::string &path : candidates) {
    void *handle = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (handle == nullptr) {
      continue;
    }

    SteamAPIInitFn init_fn = reinterpret_cast<SteamAPIInitFn>(dlsym(handle, "SteamAPI_Init"));
    SteamAPIInitFlatFn init_flat_fn = nullptr;
    if (init_fn == nullptr) {
      init_flat_fn = reinterpret_cast<SteamAPIInitFlatFn>(dlsym(handle, "SteamAPI_InitFlat"));
    }
    SteamAPIShutdownFn shutdown_fn = reinterpret_cast<SteamAPIShutdownFn>(dlsym(handle, "SteamAPI_Shutdown"));

    if ((init_fn != nullptr || init_flat_fn != nullptr) && shutdown_fn != nullptr) {
      runtime.handle = handle;
      runtime.init_fn = init_fn;
      runtime.init_flat_fn = init_flat_fn;
      runtime.shutdown_fn = shutdown_fn;
      return true;
    }

    dlclose(handle);
  }

  g_warning("[flutter_steamworks] 未能找到 libsteam_api 库，请确认其已与应用一起分发");
  return false;
}

bool InvokeSteamInit() {
  SteamRuntime &runtime = GetSteamRuntime();
  if (runtime.init_fn != nullptr) {
    return runtime.init_fn();
  }
  if (runtime.init_flat_fn != nullptr) {
    return runtime.init_flat_fn(nullptr) == 0;
  }
  return false;
}

void ShutdownSteamIfNeeded() {
  SteamRuntime &runtime = GetSteamRuntime();
  if (runtime.initialized && runtime.shutdown_fn != nullptr) {
    runtime.shutdown_fn();
  }
  if (runtime.handle != nullptr) {
    dlclose(runtime.handle);
  }
  runtime = SteamRuntime{};
}

bool SetSteamEnvironment(const std::string &app_id) {
  if (setenv("SteamAppId", app_id.c_str(), 1) != 0) {
    g_warning("[flutter_steamworks] 设置 SteamAppId 环境变量失败");
    return false;
  }
  if (setenv("SteamGameId", app_id.c_str(), 1) != 0) {
    g_warning("[flutter_steamworks] 设置 SteamGameId 环境变量失败");
    return false;
  }
  return true;
}

bool ExtractAppId(FlMethodCall *method_call, std::string *out_app_id) {
  FlValue *arguments = fl_method_call_get_args(method_call);
  if (arguments == nullptr || fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return false;
  }

  FlValue *app_id_value = fl_value_lookup_string(arguments, "appId");
  if (app_id_value == nullptr) {
    return false;
  }

  switch (fl_value_get_type(app_id_value)) {
    case FL_VALUE_TYPE_STRING: {
      const gchar *value = fl_value_get_string(app_id_value);
      if (value == nullptr || *value == '\0') {
        return false;
      }
      *out_app_id = value;
      return true;
    }
    case FL_VALUE_TYPE_INT: {
      gint64 number = fl_value_get_int(app_id_value);
      if (number <= 0) {
        return false;
      }
      *out_app_id = std::to_string(number);
      return true;
    }
    default:
      return false;
  }
}

void HandleInitSteam(FlMethodCall *method_call, FlMethodResponse **out_response) {
  std::string app_id;
  if (!ExtractAppId(method_call, &app_id)) {
    *out_response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalid-argument", "App ID is required", nullptr));
    return;
  }

  if (!SetSteamEnvironment(app_id)) {
    *out_response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    return;
  }

  if (!EnsureSteamLibraryLoaded()) {
    *out_response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
    return;
  }

  SteamRuntime &runtime = GetSteamRuntime();
  if (runtime.initialized) {
    *out_response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    return;
  }

  if (InvokeSteamInit()) {
    runtime.initialized = true;
    g_message("[flutter_steamworks] Steam API 初始化成功");
    *out_response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
  } else {
    g_warning("[flutter_steamworks] Steam API 初始化失败，请确认 Steam 客户端已启动");
    *out_response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }
}

}  // namespace

// Called when a method call is received from Flutter.
static void flutter_steamworks_plugin_handle_method_call(
    FlutterSteamworksPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "initSteam") == 0) {
    HandleInitSteam(method_call, &response);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void flutter_steamworks_plugin_dispose(GObject* object) {
  ShutdownSteamIfNeeded();
  G_OBJECT_CLASS(flutter_steamworks_plugin_parent_class)->dispose(object);
}

static void flutter_steamworks_plugin_class_init(FlutterSteamworksPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_steamworks_plugin_dispose;
}

static void flutter_steamworks_plugin_init(FlutterSteamworksPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FlutterSteamworksPlugin* plugin = FLUTTER_STEAMWORKS_PLUGIN(user_data);
  flutter_steamworks_plugin_handle_method_call(plugin, method_call);
}

void flutter_steamworks_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterSteamworksPlugin* plugin = FLUTTER_STEAMWORKS_PLUGIN(
      g_object_new(flutter_steamworks_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "flutter_steamworks",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
