import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';

class GlobalKeyboardAccessory extends StatefulWidget {
  final Widget child;

  const GlobalKeyboardAccessory({super.key, required this.child});

  @override
  State<GlobalKeyboardAccessory> createState() => _GlobalKeyboardAccessoryState();
}

class _GlobalKeyboardAccessoryState extends State<GlobalKeyboardAccessory> {
  TextEditingController? _activeController;
  bool _isObscure = false;
  bool _isNumeric = false;

  final _accessoryBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    final primaryFocus = FocusManager.instance.primaryFocus;

    if (primaryFocus != null && primaryFocus.context != null) {
      final state = primaryFocus.context!.findAncestorStateOfType<EditableTextState>() ??
                    _findEditableInContext(primaryFocus.context!);

      if (state != null) {
        final keyboardType = state.widget.keyboardType;
        final isNumeric = keyboardType.index == TextInputType.number.index ||
                          keyboardType.index == TextInputType.phone.index;

        if (_activeController != state.widget.controller ||
            _isNumeric != isNumeric) {
          setState(() {
            _activeController = state.widget.controller;
            _isObscure = state.widget.obscureText;
            _isNumeric = isNumeric;
          });
        }
        return;
      } else {
        if (_activeController != null) {
          primaryFocus.unfocus();
        }
      }
    }

    if (_activeController != null) {
      setState(() {
        _activeController = null;
        _isObscure = false;
        _isNumeric = false;
      });
    }
  }

  EditableTextState? _findEditableInContext(BuildContext context) {
    EditableTextState? found;
    context.visitChildElements((element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
      } else {
        found = _findEditableInContext(element);
      }
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        final barBox = _accessoryBarKey.currentContext?.findRenderObject() as RenderBox?;
        if (barBox != null) {
          final localPos = barBox.globalToLocal(event.position);
          if (barBox.size.contains(localPos)) return;
        }
        final primaryFocus = FocusManager.instance.primaryFocus;
        if (primaryFocus != null && primaryFocus.hasFocus) {
          primaryFocus.unfocus();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(
                left: MediaQuery.of(context).viewInsets.left,
                top: MediaQuery.of(context).viewInsets.top,
                right: MediaQuery.of(context).viewInsets.right,
                bottom: MediaQuery.of(context).viewInsets.bottom +
                    ((_activeController != null && _isNumeric && MediaQuery.of(context).viewInsets.bottom > 0) ? 44.0 : 0.0),
              ),
            ),
            child: widget.child,
          ),
          if (_activeController != null && _isNumeric)
            _AccessoryBar(
              key: _accessoryBarKey,
              controller: _activeController!,
              isObscure: _isObscure,
              isNumeric: _isNumeric,
            ),
        ],
      ),
    );
  }
}

class _AccessoryBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isObscure;
  final bool isNumeric;

  const _AccessoryBar({
    super.key,
    required this.controller,
    this.isObscure = false,
    this.isNumeric = false,
  });

  @override
  State<_AccessoryBar> createState() => _AccessoryBarState();
}

class _AccessoryBarState extends State<_AccessoryBar> {
  final _scrollCtrl = ScrollController();

  static const _textStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToCursor);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollToCursor);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final text = widget.controller.text;
      final cursorOffset = widget.controller.selection.baseOffset;
      if (cursorOffset < 0) return;

      final textBefore = text.substring(0, cursorOffset.clamp(0, text.length));
      final tp = TextPainter(
        text: TextSpan(text: textBefore, style: _textStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();

      final cursorX = tp.width;
      final viewportWidth = _scrollCtrl.position.viewportDimension;
      final currentScroll = _scrollCtrl.offset;

      if (cursorX < currentScroll) {
        _scrollCtrl.jumpTo((cursorX - 8).clamp(0.0, double.infinity));
      } else if (cursorX > currentScroll + viewportWidth - 12) {
        _scrollCtrl.jumpTo(cursorX - viewportWidth + 12);
      }
    });
  }

  void _onTapDown(TapDownDetails details) {
    final text = widget.controller.text;
    if (text.isEmpty) return;

    final scrollOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    final adjustedPos = Offset(
      details.localPosition.dx + scrollOffset,
      details.localPosition.dy,
    );

    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    final pos = tp.getPositionForOffset(adjustedPos);
    widget.controller.selection = TextSelection.collapsed(offset: pos.offset);
  }

  void _dismiss() => FocusManager.instance.primaryFocus?.unfocus();

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight <= 0) return const SizedBox.shrink();

    final isDark = AppColors.isDark(context);
    final l = AppLocalizations.of(context)!;

    return Positioned(
      bottom: keyboardHeight,
      left: 0,
      right: 0,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface(context).withValues(alpha: isDark ? 0.72 : 0.88),
                border: Border(
                  top: BorderSide(
                    color: AppColors.border(context).withValues(alpha: 0.4),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: widget.isNumeric
                    ? _buildNumericBar(context, l)
                    : _buildTextBar(context, l),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Numeric bar: tutar/sayı girişi için (teklif, fiyat, miktar) ─────────────
  Widget _buildNumericBar(BuildContext context, AppLocalizations l) {
    return Row(
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            final display = value.text.isEmpty ? l.kbdAmountHint : value.text;
            final isEmpty = value.text.isEmpty;
            return Expanded(
              child: Text(
                display,
                style: _textStyle.copyWith(
                  fontSize: 15,
                  fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                  color: isEmpty
                      ? AppColors.textTertiary(context)
                      : AppColors.textPrimary(context),
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _dismiss,
          style: FilledButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              decoration: TextDecoration.none,
            ),
          ),
          child: Text(l.kbdConfirm),
        ),
      ],
    );
  }

  // ── Text bar: genel metin girişi için (profil, yorum, arama...) ─────────────
  Widget _buildTextBar(BuildContext context, AppLocalizations l) {
    return Row(
      children: [
        Expanded(
          child: widget.isObscure
              ? const SizedBox.shrink()
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _onTapDown,
                  child: SizedBox(
                    height: 28,
                    child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.controller,
                        builder: (context, value, _) {
                          if (value.text.isEmpty) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AppLocalizations.of(context)!.kbdTypingHint,
                                style: _textStyle.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.textTertiary(context),
                                ),
                              ),
                            );
                          }

                          final cursorPos = value.selection.baseOffset
                              .clamp(0, value.text.length);
                          final textBefore = value.text.substring(0, cursorPos);
                          final textAfter = value.text.substring(cursorPos);

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                textBefore,
                                style: _textStyle.copyWith(
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              Container(
                                width: 1.5,
                                height: 18,
                                color: kPrimary,
                              ),
                              Text(
                                textAfter,
                                style: _textStyle.copyWith(
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        TextButton(
          key: const Key('keyboard_accessory_btn_kapat'),
          onPressed: _dismiss,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.textSecondary(context),
          ),
          child: Text(
            l.kbdDismiss,
            style: const TextStyle(
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
