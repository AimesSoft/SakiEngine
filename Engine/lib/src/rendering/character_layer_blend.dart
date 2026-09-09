import 'dart:ui' as ui;

/// Draws an aligned layer without changing the authored canvas. YuYuball's
/// GL tuple uses RGB = src * dst + dst * (1-srcAlpha), A = dstAlpha.
/// Compositing the source over opaque white and then modulating reproduces
/// that equation; ordinary Flutter multiply uses a different alpha equation.
void drawCharacterLayerImage(
  ui.Canvas canvas,
  ui.Image image,
  ui.Paint paint,
  String blend,
) {
  if (blend == 'normal') {
    canvas.drawImage(image, ui.Offset.zero, paint);
    return;
  }
  if (blend != 'multiplyPreserveAlpha') {
    throw FormatException('Unknown layer blend: $blend');
  }
  final bounds = ui.Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  canvas.saveLayer(bounds, ui.Paint()..blendMode = ui.BlendMode.modulate);
  canvas.drawRect(bounds, ui.Paint()..color = const ui.Color(0xffffffff));
  canvas.drawImage(image, ui.Offset.zero, paint);
  canvas.restore();
}
