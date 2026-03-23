import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';

class ControlSettingsTab extends StatelessWidget {
  const ControlSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final config = SakiEngineConfig();
    final textScale = context.scaleFor(ComponentType.text);
    final localization = LocalizationManager();

    return Center(
      child: Text(
        localization.t('settings.controls.placeholder'),
        style: config.reviewTitleTextStyle.copyWith(
          fontSize: config.reviewTitleTextStyle.fontSize! * textScale * 0.8,
          color: config.themeColors.primary.withOpacity(0.6),
        ),
      ),
    );
  }
}
