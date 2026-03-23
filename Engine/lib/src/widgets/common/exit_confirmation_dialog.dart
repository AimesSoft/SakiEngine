import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:flutter/services.dart';
import 'package:sakiengine/src/widgets/confirm_dialog.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import '../../utils/platform_window_manager_io.dart' if (dart.library.html) '../../utils/platform_window_manager_web.dart';

class ExitConfirmationDialog {
  static Future<bool> showExitConfirmation(BuildContext context, {bool hasProgress = true}) async {
    final localization = LocalizationManager();
    final title = localization.t('dialog.exit.title');
    final content = hasProgress
        ? localization.t('dialog.exit.contentWithProgress')
        : localization.t('dialog.exit.contentSimple');

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return ConfirmDialog(
          title: title,
          content: content,
          onConfirm: () => Navigator.of(context).pop(true),
        );
      },
    );
    return shouldExit ?? false;
  }

  static Future<void> showExitConfirmationAndDestroy(BuildContext context) async {
    final localization = LocalizationManager();
    final title = localization.t('dialog.exit.title');
    final content = localization.t('dialog.exit.contentSimple');

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return ConfirmDialog(
          title: title,
          content: content,
          onConfirm: () => Navigator.of(context).pop(true),
        );
      },
    );
    
    if (shouldExit == true) {
      // 修复Windows关闭游戏的bug：直接销毁窗口，避免重复触发onWindowClose
      try {
        await PlatformWindowManager.destroy();
      } catch (e) {
        // 如果销毁失败，使用系统退出
        SystemNavigator.pop();
      }
    }
  }
}
