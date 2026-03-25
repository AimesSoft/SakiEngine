#include "flutter_steamworks_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstdlib>
#include <filesystem>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

namespace flutter_steamworks {

namespace {

using SteamAPIInitFn = bool (*)();
using SteamAPIInitFlatFn = int (*)(void *);
using SteamAPIShutdownFn = void (*)();

struct SteamRuntime {
  HMODULE module = nullptr;
  SteamAPIInitFn init_fn = nullptr;
  SteamAPIInitFlatFn init_flat_fn = nullptr;
  SteamAPIShutdownFn shutdown_fn = nullptr;
  bool initialized = false;
};

SteamRuntime &GetSteamRuntime() {
  static SteamRuntime runtime;
  return runtime;
}

void DebugOutput(const wchar_t *message) {
  if (message == nullptr) {
    return;
  }
  std::wstring output(message);
  if (output.empty() || output.back() != L'\n') {
    output.push_back(L'\n');
  }
  ::OutputDebugStringW(output.c_str());
}

std::vector<std::filesystem::path> BuildSteamLibraryCandidates() {
  static const wchar_t *kNames[] = {L"steam_api64.dll", L"steam_api.dll"};
  std::vector<std::filesystem::path> candidates;

  HMODULE module = nullptr;
  if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                             GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                         reinterpret_cast<LPCWSTR>(&BuildSteamLibraryCandidates),
                         &module)) {
    wchar_t path_buffer[MAX_PATH] = {0};
    DWORD length = GetModuleFileNameW(module, path_buffer, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
      std::filesystem::path module_path(path_buffer);
      std::filesystem::path dir = module_path.parent_path();
      for (const wchar_t *name : kNames) {
        candidates.emplace_back(dir / name);
      }
    }
  }

  for (const wchar_t *name : kNames) {
    candidates.emplace_back(name);
  }

  return candidates;
}

bool EnsureSteamLibraryLoaded() {
  SteamRuntime &runtime = GetSteamRuntime();
  if (runtime.module != nullptr) {
    return (runtime.init_fn != nullptr || runtime.init_flat_fn != nullptr) &&
           runtime.shutdown_fn != nullptr;
  }

  const auto candidates = BuildSteamLibraryCandidates();
  for (const auto &candidate : candidates) {
    HMODULE module = LoadLibraryW(candidate.c_str());
    if (module == nullptr) {
      continue;
    }

    SteamAPIInitFn init_fn = reinterpret_cast<SteamAPIInitFn>(GetProcAddress(module, "SteamAPI_Init"));
    SteamAPIInitFlatFn init_flat_fn = nullptr;
    if (init_fn == nullptr) {
      init_flat_fn = reinterpret_cast<SteamAPIInitFlatFn>(GetProcAddress(module, "SteamAPI_InitFlat"));
    }
    SteamAPIShutdownFn shutdown_fn = reinterpret_cast<SteamAPIShutdownFn>(GetProcAddress(module, "SteamAPI_Shutdown"));

    if ((init_fn != nullptr || init_flat_fn != nullptr) && shutdown_fn != nullptr) {
      runtime.module = module;
      runtime.init_fn = init_fn;
      runtime.init_flat_fn = init_flat_fn;
      runtime.shutdown_fn = shutdown_fn;
      return true;
    }

    FreeLibrary(module);
  }

  DebugOutput(L"[flutter_steamworks] steam_api64.dll not found. Ensure it is shipped with the app.");
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
  if (runtime.module != nullptr) {
    FreeLibrary(runtime.module);
  }
  runtime = SteamRuntime{};
}

bool SetSteamEnvironment(const std::string &app_id) {
  if (_putenv_s("SteamAppId", app_id.c_str()) != 0) {
    DebugOutput(L"[flutter_steamworks] Failed to set SteamAppId environment variable.");
    return false;
  }
  if (_putenv_s("SteamGameId", app_id.c_str()) != 0) {
    DebugOutput(L"[flutter_steamworks] Failed to set SteamGameId environment variable.");
    return false;
  }
  return true;
}

std::optional<std::string> ExtractAppId(const flutter::MethodCall<flutter::EncodableValue> &call) {
  const auto *arguments = call.arguments();
  if (arguments == nullptr) {
    return std::nullopt;
  }

  const auto *map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return std::nullopt;
  }

  const auto iterator = map->find(flutter::EncodableValue("appId"));
  if (iterator == map->end()) {
    return std::nullopt;
  }

  const flutter::EncodableValue &value = iterator->second;
  if (const auto *string_value = std::get_if<std::string>(&value)) {
    if (!string_value->empty()) {
      return *string_value;
    }
    return std::nullopt;
  }

  if (const auto *int_value = std::get_if<int32_t>(&value)) {
    if (*int_value > 0) {
      return std::to_string(*int_value);
    }
    return std::nullopt;
  }

  if (const auto *long_value = std::get_if<int64_t>(&value)) {
    if (*long_value > 0) {
      return std::to_string(*long_value);
    }
    return std::nullopt;
  }

  return std::nullopt;
}

}  // namespace

// static
void FlutterSteamworksPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_steamworks",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterSteamworksPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterSteamworksPlugin::FlutterSteamworksPlugin() {}

FlutterSteamworksPlugin::~FlutterSteamworksPlugin() {
  ShutdownSteamIfNeeded();
}

void FlutterSteamworksPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("initSteam") == 0) {
    const auto app_id = ExtractAppId(method_call);
    if (!app_id.has_value()) {
      result->Error("invalid-argument", "App ID is required");
      return;
    }

    if (!SetSteamEnvironment(*app_id)) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    if (!EnsureSteamLibraryLoaded()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }

    SteamRuntime &runtime = GetSteamRuntime();
    if (runtime.initialized) {
      result->Success(flutter::EncodableValue(true));
      return;
    }

    if (InvokeSteamInit()) {
      runtime.initialized = true;
      DebugOutput(L"[flutter_steamworks] Steam API initialized successfully.");
      result->Success(flutter::EncodableValue(true));
    } else {
      DebugOutput(L"[flutter_steamworks] Steam API initialization failed. Verify Steam client is running.");
      result->Success(flutter::EncodableValue(false));
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_steamworks
