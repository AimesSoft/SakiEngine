import 'package:flutter/material.dart';
import 'package:sakiengine/src/config/project_info_manager.dart';
import 'package:sakiengine/src/localization/localization_manager.dart';
import 'package:sakiengine/src/utils/scaling_manager.dart';
import 'package:sakiengine/src/widgets/common/overlay_scaffold.dart';

class AboutScreen extends StatefulWidget {
  final VoidCallback onClose;
  final bool useOverlayScaffold;
  final bool showHeader;
  final bool showFooter;

  const AboutScreen({
    super.key,
    required this.onClose,
    this.useOverlayScaffold = true,
    this.showHeader = true,
    this.showFooter = false,
  });

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<_AboutInfo> _aboutInfoFuture;
  late final Listenable _aboutListenable;

  @override
  void initState() {
    super.initState();
    _aboutInfoFuture = _loadAboutInfo();
    _aboutListenable = LocalizationManager();
  }

  Future<_AboutInfo> _loadAboutInfo() async {
    final infoManager = ProjectInfoManager();
    final appName = await infoManager.getAppName();
    final projectName = await infoManager.getProjectName();
    return _AboutInfo(appName: appName, projectName: projectName);
  }

  Widget _buildContent() {
    return FutureBuilder<_AboutInfo>(
      future: _aboutInfoFuture,
      builder: (context, snapshot) {
        final localization = LocalizationManager();
        final info = snapshot.data ??
            _AboutInfo(appName: 'SakiEngine', projectName: 'SakiEngine');

        final uiScale = context.scaleFor(ComponentType.ui);
        final textScale = context.scaleFor(ComponentType.text);
        final titleStyle = Theme.of(context).textTheme.headlineSmall;
        final bodyStyle = Theme.of(context).textTheme.bodyLarge;

        return SingleChildScrollView(
          padding: EdgeInsets.all(24.0 * uiScale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.appName,
                style: titleStyle?.copyWith(
                  fontSize: (titleStyle.fontSize ?? 32.0) * textScale,
                  color: Colors.white,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12.0 * uiScale),
              Text(
                localization.t('about.poweredBy'),
                style: bodyStyle?.copyWith(
                  fontSize: (bodyStyle.fontSize ?? 18.0) * textScale,
                  color: Colors.white.withValues(alpha: 0.86),
                ),
              ),
              SizedBox(height: 20.0 * uiScale),
              Text(
                localization.t('about.description'),
                style: bodyStyle?.copyWith(
                  fontSize: (bodyStyle.fontSize ?? 18.0) * textScale,
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.5,
                ),
              ),
              SizedBox(height: 16.0 * uiScale),
              Text(
                localization.t(
                  'about.projectName',
                  params: {'name': info.projectName},
                ),
                style: bodyStyle?.copyWith(
                  fontSize: (bodyStyle.fontSize ?? 16.0) * textScale,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              SizedBox(height: 6.0 * uiScale),
              Text(
                localization.t('about.engineName'),
                style: bodyStyle?.copyWith(
                  fontSize: (bodyStyle.fontSize ?? 16.0) * textScale,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _aboutListenable,
      builder: (context, child) {
        final localization = LocalizationManager();
        final content = _buildContent();

        if (!widget.useOverlayScaffold) {
          return content;
        }

        return OverlayScaffold(
          title: localization.t('about.title'),
          showHeader: widget.showHeader,
          content: content,
          footer: widget.showFooter ? const SizedBox.shrink() : null,
          onClose: (_) => widget.onClose(),
        );
      },
    );
  }
}

class _AboutInfo {
  final String appName;
  final String projectName;

  const _AboutInfo({
    required this.appName,
    required this.projectName,
  });
}
