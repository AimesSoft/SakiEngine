import 'package:flutter/material.dart';
import 'package:sakiengine/src/utils/foundation_compat.dart';
import 'package:sakiengine/src/config/saki_engine_config.dart';
import 'package:sakiengine/src/utils/ui_sound_manager.dart';

class GameStyleDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const GameStyleDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

class GameStyleDropdown<T> extends StatefulWidget {
  final List<GameStyleDropdownItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double scale;
  final double textScale;
  final SakiEngineConfig config;
  final double? width;

  const GameStyleDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.scale,
    required this.textScale,
    required this.config,
    this.width,
  });

  @override
  State<GameStyleDropdown<T>> createState() => _GameStyleDropdownState<T>();
}

class _GameStyleDropdownState<T> extends State<GameStyleDropdown<T>>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final LayerLink _layerLink = LayerLink();
  final _uiSoundManager = UISoundManager();

  GameStyleDropdownItem<T> get _selectedItem {
    final index = widget.items.indexWhere((item) => item.value == widget.value);
    if (index == -1) {
      return widget.items.first;
    }
    return widget.items[index];
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _removeOverlay(immediate: true);
    _animationController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    _uiSoundManager.playButtonClick();
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context, debugRequiredFor: widget);
    if (overlay == null) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _DropdownOverlay<T>(
          link: _layerLink,
          animation: _fadeAnimation,
          config: widget.config,
          scale: widget.scale,
          textScale: widget.textScale,
          width: widget.width,
          items: widget.items,
          selectedValue: _selectedItem.value,
          onSelect: (value) {
            _uiSoundManager.playButtonClick();
            widget.onChanged(value);
            _removeOverlay();
          },
          onDismiss: _removeOverlay,
        );
      },
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _animationController.forward(from: 0);
  }

  void _removeOverlay({bool immediate = false}) {
    if (!_isOpen) return;
    if (immediate) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _isOpen = false;
      return;
    }
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) {
        setState(() => _isOpen = false);
      } else {
        _isOpen = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final scale = widget.scale;
    final textScale = widget.textScale;
    final selectedItem = _selectedItem;

    final baseOpacity = _isOpen ? 0.96 : (_isHovered ? 0.88 : 0.82);
    final double secondaryOpacity =
        ((baseOpacity - 0.12).clamp(0.0, 1.0) as num).toDouble();

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _uiSoundManager.playButtonHover();
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: _toggleDropdown,
          child: Container(
            width: widget.width ?? 180 * scale,
            padding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 12 * scale,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  config.themeColors.background.withOpacity(baseOpacity),
                  config.themeColors.surface.withOpacity(secondaryOpacity),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border.all(
                color: config.themeColors.primary.withOpacity(_isHovered ? 0.6 : 0.35),
                width: 1,
              ),
              boxShadow: [
                if (_isOpen || _isHovered)
                  BoxShadow(
                    color: config.themeColors.primary.withOpacity(_isOpen ? 0.25 : 0.12),
                    blurRadius: 18 * scale,
                    offset: Offset(0, 6 * scale),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedItem.icon != null) ...[
                  Icon(
                    selectedItem.icon,
                    size: 18 * scale,
                    color: config.themeColors.primary,
                  ),
                  SizedBox(width: 12 * scale),
                ],
                Expanded(
                  child: Text(
                    selectedItem.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: config.dialogueTextStyle.copyWith(
                      fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                      color: config.themeColors.primary,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                SizedBox(width: 12 * scale),
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20 * scale,
                    color: config.themeColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownOverlay<T> extends StatelessWidget {
  final LayerLink link;
  final Animation<double> animation;
  final SakiEngineConfig config;
  final double scale;
  final double textScale;
  final double? width;
  final List<GameStyleDropdownItem<T>> items;
  final T selectedValue;
  final ValueChanged<T> onSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.link,
    required this.animation,
    required this.config,
    required this.scale,
    required this.textScale,
    required this.width,
    required this.items,
    required this.selectedValue,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          offset: Offset(0, 52 * scale),
          showWhenUnlinked: false,
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              alignment: Alignment.topCenter,
              child: _buildDropdown(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final dropdownWidth = width ?? 180 * scale;
    final maxHeight = 220 * scale;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: dropdownWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              config.themeColors.background.withOpacity(0.92),
              config.themeColors.surface.withOpacity(0.88),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(
            color: config.themeColors.primary.withOpacity(0.45),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: config.themeColors.primary.withOpacity(0.25),
              blurRadius: 20 * scale,
              offset: Offset(0, 10 * scale),
            ),
          ],
        ),
        child: ClipRect(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: 8 * scale),
            itemCount: items.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 1,
              indent: 16 * scale,
              endIndent: 16 * scale,
              color: config.themeColors.primary.withOpacity(0.08),
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = item.value == selectedValue;

              return _DropdownItem<T>(
                item: item,
                isSelected: isSelected,
                onTap: () => onSelect(item.value),
                scale: scale,
                textScale: textScale,
                config: config,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DropdownItem<T> extends StatefulWidget {
  final GameStyleDropdownItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;
  final double scale;
  final double textScale;
  final SakiEngineConfig config;

  const _DropdownItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.scale,
    required this.textScale,
    required this.config,
  });

  @override
  State<_DropdownItem<T>> createState() => _DropdownItemState<T>();
}

class _DropdownItemState<T> extends State<_DropdownItem<T>> {
  bool _isHovered = false;
  final _uiSoundManager = UISoundManager();

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final textScale = widget.textScale;
    final config = widget.config;

    final baseColor = widget.isSelected
        ? config.themeColors.primary.withOpacity(0.08)
        : (_isHovered
            ? config.themeColors.primary.withOpacity(0.06)
            : Colors.transparent);

    return InkWell(
      onTap: widget.onTap,
      onHover: (value) {
        setState(() => _isHovered = value);
        if (value) {
          _uiSoundManager.playButtonHover();
        }
      },
      child: Container(
        color: baseColor,
        padding: EdgeInsets.symmetric(
          horizontal: 18 * scale,
          vertical: 10 * scale,
        ),
        child: Row(
          children: [
            if (widget.item.icon != null) ...[
              Icon(
                widget.item.icon,
                size: 18 * scale,
                color: config.themeColors.primary,
              ),
              SizedBox(width: 12 * scale),
            ],
            Expanded(
              child: Text(
                widget.item.label,
                style: config.dialogueTextStyle.copyWith(
                  fontSize: config.dialogueTextStyle.fontSize! * textScale * 0.6,
                  color: config.themeColors.primary,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (widget.isSelected)
              Icon(
                Icons.check_rounded,
                size: 18 * scale,
                color: config.themeColors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
