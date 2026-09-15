import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/game_file_logger.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/settings_manager.dart';
import 'package:sakiengine/src/widgets/game_style_switch.dart';

class DeveloperSettingsTab extends StatefulWidget {
  const DeveloperSettingsTab({super.key, this.fileLogger});

  final GameFileLogger? fileLogger;

  @override
  State<DeveloperSettingsTab> createState() => _DeveloperSettingsTabState();
}

class _DeveloperSettingsTabState extends State<DeveloperSettingsTab> {
  final _settings = SettingsManager();
  late final GameFileLogger _fileLogger = widget.fileLogger ?? GameFileLogger();
  late final Listenable _changes = Listenable.merge([
    _settings,
    _fileLogger,
    LocalizationManager(),
  ]);
  bool _loading = true;
  bool _updatingFileLogging = false;
  Object? _settingsError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _settings.init();
      await _fileLogger.initialize();
    } catch (error) {
      _settingsError = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setFileLogging(bool enabled) async {
    if (_updatingFileLogging) return;
    setState(() {
      _updatingFileLogging = true;
      _settingsError = null;
    });
    try {
      await _fileLogger.setEnabled(enabled);
    } catch (error) {
      _settingsError = error;
    } finally {
      if (mounted) setState(() => _updatingFileLogging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _changes,
      builder: (context, _) {
        if (_loading) return const SizedBox.shrink();
        final config = SakiEngineConfig();
        final scale = context.scaleFor(ComponentType.ui);
        final textScale = context.scaleFor(ComponentType.text);
        final localization = LocalizationManager();
        final error = _settingsError ?? _fileLogger.lastStartError;
        final path = _fileLogger.currentLogFilePath;

        return SingleChildScrollView(
          padding: EdgeInsets.all(32 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToggle(
                config: config,
                scale: scale,
                textScale: textScale,
                settingKey: 'developer-fps-overlay',
                icon: Icons.speed,
                title: localization.t('settings.fpsOverlay.title'),
                description: localization.t('settings.fpsOverlay.description'),
                value: _settings.currentShowFpsOverlay,
                onChanged: _settings.setShowFpsOverlay,
              ),
              SizedBox(height: 24 * scale),
              _buildToggle(
                config: config,
                scale: scale,
                textScale: textScale,
                settingKey: 'developer-file-logging',
                icon: Icons.description_outlined,
                title: localization.t('settings.fileLogging.title'),
                description: localization.t(
                  _fileLogger.isSupported
                      ? 'settings.fileLogging.description'
                      : 'settings.fileLogging.unsupported',
                ),
                value: _fileLogger.isEnabled,
                enabled: _fileLogger.isSupported && !_updatingFileLogging,
                onChanged: _setFileLogging,
              ),
              if (path != null) ...[
                SizedBox(height: 16 * scale),
                SelectableText(
                  localization.t(
                    'settings.fileLogging.path',
                    params: {'path': path},
                  ),
                  key: const ValueKey('developer-log-file-path'),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize:
                        config.dialogueTextStyle.fontSize! * textScale * 0.6,
                    color: config.themeColors.onSurface,
                  ),
                ),
              ],
              if (error != null) ...[
                SizedBox(height: 16 * scale),
                Text(
                  localization.t(
                    'settings.fileLogging.error',
                    params: {'error': error.toString()},
                  ),
                  key: const ValueKey('developer-log-file-error'),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize:
                        config.dialogueTextStyle.fontSize! * textScale * 0.6,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggle({
    required SakiEngineConfig config,
    required double scale,
    required double textScale,
    required String settingKey,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final labels = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: config.themeColors.onSurface, size: 24 * scale),
        SizedBox(width: 16 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: config.reviewTitleTextStyle.copyWith(
                  fontSize:
                      config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                  color: config.themeColors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4 * scale),
              Text(
                description,
                style: config.dialogueTextStyle.copyWith(
                  fontSize:
                      config.dialogueTextStyle.fontSize! * textScale * 0.6,
                  color: config.themeColors.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final toggle = Semantics(
      label: title,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      child: AbsorbPointer(
        absorbing: !enabled,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: GameStyleSwitch(
            key: ValueKey(settingKey),
            value: value,
            onChanged: onChanged,
            scale: scale,
            config: config,
          ),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withValues(alpha: 0.5),
        border: Border.all(
          color: config.themeColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500 * scale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labels,
                SizedBox(height: 16 * scale),
                toggle,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: labels),
              SizedBox(width: 16 * scale),
              toggle,
            ],
          );
        },
      ),
    );
  }
}
