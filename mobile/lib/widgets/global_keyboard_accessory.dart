import 'dart:ui';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';

class GlobalKeyboardAccessory extends StatefulWidget {
  final Widget child;

  const GlobalKeyboardAccessory({super.key, required this.child});

  @override
  State<GlobalKeyboardAccessory> createState() => _GlobalKeyboardAccessoryState();
}

class _GlobalKeyboardAccessoryState extends State<GlobalKeyboardAccessory> {
  TextEditingController? _activeController;
  bool _isObscure = false;

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
        if (_activeController != state.widget.controller) {
          setState(() {
            _activeController = state.widget.controller;
            _isObscure = state.widget.obscureText;
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
        // Accessory bar alanına yapılan tap'ı atla — klavye kapanmasın
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
          widget.child,
          if (_activeController != null)
            _AccessoryBar(
              key: _accessoryBarKey,
              controller: _activeController!,
              isObscure: _isObscure,
            ),
        ],
      ),
    );
  }
}

class _AccessoryBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isObscure;

  const _AccessoryBar({
    super.key,
    required this.controller,
    this.isObscure = false,
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

    // Tap koordinatını scroll offset'e göre düzelt
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

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight <= 0) return const SizedBox.shrink();

    final isDark = AppColors.isDark(context);

    return Positioned(
      bottom: keyboardHeight,
      left: 0,
      right: 0,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface(context).withValues(alpha: isDark ? 0.7 : 0.85),
                border: Border(
                  top: BorderSide(
                    color: AppColors.border(context).withValues(alpha: 0.5),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
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
                                      final isEmpty = value.text.isEmpty;

                                      if (isEmpty) {
                                        return Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Yazılıyor...',
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
                      onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: kPrimary,
                      ),
                      child: const Text(
                        'Kapat',
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
