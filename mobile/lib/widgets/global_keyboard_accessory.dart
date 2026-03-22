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
      onPointerDown: (_) {
        // We use Listener instead of GestureDetector to ensure we catch the tap
        // even if it's handled by other widgets (like buttons or scrollables).
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
            _AccessoryBar(controller: _activeController!, isObscure: _isObscure),
        ],
      ),
    );
  }
}

class _AccessoryBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isObscure;

  const _AccessoryBar({required this.controller, this.isObscure = false});

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
                          : ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, value, _) {
                                final text = value.text.isEmpty ? 'Yazılıyor...' : value.text;
                                return Text(
                                  text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    decoration: TextDecoration.none,
                                    fontStyle: value.text.isEmpty ? FontStyle.italic : FontStyle.normal,
                                    color: value.text.isEmpty
                                        ? AppColors.textTertiary(context)
                                        : AppColors.textPrimary(context),
                                    fontSize: 13,
                                    fontWeight: value.text.isEmpty ? FontWeight.normal : FontWeight.w500,
                                  ),
                                );
                              },
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


