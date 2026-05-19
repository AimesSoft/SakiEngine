#include "include/flutter_steamworks/flutter_steamworks_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_steamworks_plugin.h"

void FlutterSteamworksPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_steamworks::FlutterSteamworksPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
