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

  // Accessory bar kendi FocusNode'u — focus buraya geçince _handleFocusChange
  // yeni bir controller aramaz, mevcut _activeController korunur.
  final _accessoryFocusNode = FocusNode();

  // Accessory bar'ın ekran konumunu tespit etmek için key
  final _accessoryBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    _accessoryFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final primaryFocus = FocusManager.instance.primaryFocus;

    // Accessory bar TextField'a geçince mevcut state'i koru
    if (primaryFocus == _accessoryFocusNode) return;

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
        if (primaryFocus != null &&
            primaryFocus.hasFocus &&
            primaryFocus != _accessoryFocusNode) {
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
              focusNode: _accessoryFocusNode,
            ),
        ],
      ),
    );
  }
}

class _AccessoryBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isObscure;
  final FocusNode focusNode;

  const _AccessoryBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.isObscure = false,
  });

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
                      child: isObscure
                          ? const SizedBox.shrink()
                          : TextField(
                              controller: controller,
                              focusNode: focusNode,
                              maxLines: 1,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.none,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Yazılıyor...',
                                hintStyle: TextStyle(
                                  color: AppColors.textTertiary(context),
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              cursorColor: kPrimary,
                              cursorWidth: 1.5,
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
