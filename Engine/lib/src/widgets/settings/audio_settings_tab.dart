import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/utils/music_manager.dart';
import 'package:sakiengine/src/widgets/game_style_switch.dart';
import 'package:sakiengine/src/widgets/game_style_slider.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class AudioSettingsTab extends StatelessWidget {
  final bool musicEnabled;
  final double musicVolume;
  final double soundVolume;
  final Function(bool) onMusicEnabledChanged;
  final Function(double) onMusicVolumeChanged;
  final Function(double) onSoundVolumeChanged;

  const AudioSettingsTab({
    super.key,
    required this.musicEnabled,
    required this.musicVolume,
    required this.soundVolume,
    required this.onMusicEnabledChanged,
    required this.onMusicVolumeChanged,
    required this.onSoundVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final scale = context.scaleFor(ComponentType.ui);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideLayout = constraints.maxWidth > constraints.maxHeight;

        if (isWideLayout) {
          return _buildDualColumn(config, scale, constraints, context);
        } else {
          return _buildSingleColumn(config, scale, context);
        }
      },
    );
  }

  Widget _buildSingleColumn(SakiEngineConfig config, double scale, BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(32 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMusicEnabledToggle(config, scale, context),
            SizedBox(height: 40 * scale),
            _buildMusicVolumeSlider(config, scale, context),
            SizedBox(height: 40 * scale),
            _buildSoundVolumeSlider(config, scale, context),
            SizedBox(height: 40 * scale),
          ],
        ),
      ),
    );
  }

  Widget _buildDualColumn(SakiEngineConfig config, double scale, BoxConstraints constraints, BuildContext context) {
    return Stack(
      children: [
        // 主要内容区域
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左列 - 音乐设置
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 32 * scale,
                    top: 32 * scale,
                    bottom: 32 * scale,
                    right: 32 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMusicEnabledToggle(config, scale, context),
                      SizedBox(height: 40 * scale),
                      _buildMusicVolumeSlider(config, scale, context),
                      SizedBox(height: 40 * scale),
                    ],
                  ),
                ),
              ),
            ),

            // 右列间距
            SizedBox(width: 0),

            // 右列 - 音效设置
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 32 * scale,
                    top: 32 * scale,
                    bottom: 32 * scale,
                    right: 32 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSoundVolumeSlider(config, scale, context),
                      SizedBox(height: 40 * scale),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // 固定的中间分割线
        Positioned.fill(
          child: Align(
            alignment: Alignment.center,
            child: Container(
              width: 1 * scale,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    config.themeColors.primary.withOpacity(0.3),
                    config.themeColors.primary.withOpacity(0.6),
                    config.themeColors.primary.withOpacity(0.3),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMusicEnabledToggle(SakiEngineConfig config, double scale, BuildContext context) {
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.5),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            musicEnabled ? Icons.music_note : Icons.music_off,
            color: config.themeColors.primary,
            size: 24 * scale,
          ),
          SizedBox(width: 16 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localization.t('settings.musicEnabled.title'),
                  style: config.reviewTitleTextStyle.copyWith(
                    fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                    color: config.themeColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  localization.t('settings.musicEnabled.description'),
                  style: config.dialogueTextStyle.copyWith(
                    fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                    color: config.themeColors.primary.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 16 * scale),
          GameStyleSwitch(
            value: musicEnabled,
            onChanged: onMusicEnabledChanged,
            scale: scale,
            config: config,
          ),
        ],
      ),
    );
  }

  Widget _buildMusicVolumeSlider(SakiEngineConfig config, double scale, BuildContext context) {
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.5),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_up,
                color: config.themeColors.primary,
                size: 24 * scale,
              ),
              SizedBox(width: 16 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization.t('settings.musicVolume.title'),
                      style: config.reviewTitleTextStyle.copyWith(
                        fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                        color: config.themeColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      localization.t('settings.musicVolume.description'),
                      style: config.dialogueTextStyle.copyWith(
                        fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                        color: config.themeColors.primary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16 * scale),
          GameStyleSlider(
            value: musicVolume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            scale: scale,
            config: config,
            onChanged: onMusicVolumeChanged,
            showValue: false,
          ),
          SizedBox(height: 8 * scale),
          Text(
            localization.t('settings.common.currentVolume', params: {
              'value': (musicVolume * 100).round().toString(),
            }),
            style: config.dialogueTextStyle.copyWith(
              fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.5,
              color: config.themeColors.primary.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundVolumeSlider(SakiEngineConfig config, double scale, BuildContext context) {
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: config.themeColors.surface.withOpacity(0.5),
        border: Border.all(
          color: config.themeColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.volume_down,
                color: config.themeColors.primary,
                size: 24 * scale,
              ),
              SizedBox(width: 16 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localization.t('settings.soundVolume.title'),
                      style: config.reviewTitleTextStyle.copyWith(
                        fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.7,
                        color: config.themeColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      localization.t('settings.soundVolume.description'),
                      style: config.dialogueTextStyle.copyWith(
                        fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                        color: config.themeColors.primary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16 * scale),
          GameStyleSlider(
            value: soundVolume,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            scale: scale,
            config: config,
            onChanged: onSoundVolumeChanged,
            showValue: false,
          ),
          SizedBox(height: 8 * scale),
          Text(
            localization.t('settings.common.currentVolume', params: {
              'value': (soundVolume * 100).round().toString(),
            }),
            style: config.dialogueTextStyle.copyWith(
              fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.5,
              color: config.themeColors.primary.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
