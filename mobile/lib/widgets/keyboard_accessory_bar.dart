import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class KeyboardAccessoryBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onClose;
  final String? placeholder;

  const KeyboardAccessoryBar({
    super.key,
    required this.controller,
    this.onClose,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight <= 0) return const SizedBox.shrink();

    return Positioned(
      bottom: keyboardHeight,
      left: 0,
      right: 0,
      child: Material(
        elevation: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            border: Border(
              top: BorderSide(color: AppColors.border(context), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final text = value.text.isEmpty
                        ? (placeholder ?? 'Yazılıyor...')
                        : value.text;
                    return Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontStyle: value.text.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: value.text.isEmpty
                            ? AppColors.textTertiary(context)
                            : AppColors.textPrimary(context),
                        fontSize: 13,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onClose ?? () => FocusScope.of(context).unfocus(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Kapat',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
