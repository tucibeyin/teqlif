import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Uygulamanın standart arama alanı.
///
/// Kullanım:
///   - [hintText]   : `loc.t('someSearchHintKey')` — OTA/ARB üzerinden caller'dan gelir.
///   - [controller] : verilirse içerik varken temizle (×) ikonu gösterilir.
///   - [prefixIcon] : varsayılan [Icons.search]; farklı bağlamlarda özelleştirilebilir.
class TeqSearchField extends StatelessWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final IconData prefixIcon;

  const TeqSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.prefixIcon = Icons.search,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle:
            TextStyle(color: AppColors.textTertiary(context), fontSize: 14),
        prefixIcon:
            Icon(prefixIcon, size: 20, color: AppColors.textTertiary(context)),
        suffixIcon: controller != null
            ? AnimatedBuilder(
                animation: controller!,
                builder: (context, child) => controller!.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            size: 18,
                            color: AppColors.textTertiary(context)),
                        onPressed: () {
                          controller!.clear();
                          onChanged('');
                        },
                      )
                    : const SizedBox.shrink(),
              )
            : null,
        filled: true,
        fillColor: AppColors.card(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
