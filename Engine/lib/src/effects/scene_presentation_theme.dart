import 'package:flutter/material.dart';

/// The opaque matte used by scene transitions and uncovered game surfaces.
/// Projects can supply a palette color without changing other games' defaults.
@immutable
class ScenePresentationTheme extends ThemeExtension<ScenePresentationTheme> {
  final Color backdropColor;

  const ScenePresentationTheme({required this.backdropColor});

  static Color backdropColorOf(BuildContext context) =>
      Theme.of(context).extension<ScenePresentationTheme>()?.backdropColor ??
      Colors.black;

  @override
  ScenePresentationTheme copyWith({Color? backdropColor}) =>
      ScenePresentationTheme(
        backdropColor: backdropColor ?? this.backdropColor,
      );

  @override
  ScenePresentationTheme lerp(ScenePresentationTheme? other, double t) =>
      other == null
      ? this
      : ScenePresentationTheme(
          backdropColor: Color.lerp(backdropColor, other.backdropColor, t)!,
        );
}
