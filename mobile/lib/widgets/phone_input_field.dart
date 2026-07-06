import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';

/// Ülke kodu dropdown'lı telefon giriş alanı.
/// [onChanged] her geçerli numara değişiminde E.164 formatında (+905...) çağrılır.
/// [onReset] alan temizlendiğinde / geçersiz olduğunda çağrılır.
class PhoneInputField extends StatefulWidget {
  final void Function(String e164) onChanged;
  final void Function()? onReset;
  final String? initialE164; // ör. "+905321234567"
  final String? errorText;

  const PhoneInputField({
    super.key,
    required this.onChanged,
    this.onReset,
    this.initialE164,
    this.errorText,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  String _initialCountry = 'TR';
  String _initialNumber = '';

  @override
  void initState() {
    super.initState();
    final e164 = widget.initialE164;
    if (e164 != null && e164.isNotEmpty) {
      // Basit parse: +90 → TR, geri kalan hane
      if (e164.startsWith('+90')) {
        _initialCountry = 'TR';
        _initialNumber = e164.substring(3);
      } else if (e164.startsWith('+1')) {
        _initialCountry = 'US';
        _initialNumber = e164.substring(2);
      } else if (e164.startsWith('+44')) {
        _initialCountry = 'GB';
        _initialNumber = e164.substring(3);
      } else if (e164.startsWith('+49')) {
        _initialCountry = 'DE';
        _initialNumber = e164.substring(3);
      } else if (e164.startsWith('+966')) {
        _initialCountry = 'SA';
        _initialNumber = e164.substring(4);
      } else if (e164.startsWith('+971')) {
        _initialCountry = 'AE';
        _initialNumber = e164.substring(4);
      } else if (e164.startsWith('+972')) {
        _initialCountry = 'IL';
        _initialNumber = e164.substring(4);
      }
      // bilinmeyen kod → TR varsayılan, hane boş
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = AppColors.bg(context);
    final textColor = AppColors.textPrimary(context);
    final hintColor = AppColors.textSecondary(context);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    return IntlPhoneField(
      initialCountryCode: _initialCountry,
      initialValue: _initialNumber,
      keyboardType: TextInputType.phone,
      style: TextStyle(color: textColor, fontSize: 15),
      dropdownTextStyle: TextStyle(color: textColor, fontSize: 14),
      dropdownIcon: Icon(Icons.arrow_drop_down, color: hintColor, size: 20),
      flagsButtonPadding: const EdgeInsets.only(left: 12, right: 4),
      showDropdownIcon: true,
      autofocus: false,
      invalidNumberMessage: null, // kendi hata mesajımızı kullanacağız
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.phoneInputHint,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        filled: true,
        fillColor: fillColor,
        errorText: widget.errorText,
        errorStyle: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      onChanged: (PhoneNumber number) {
        if (number.number.isEmpty) {
          widget.onReset?.call();
          return;
        }
        try {
          if (number.isValidNumber()) {
            widget.onChanged(number.completeNumber);
          } else {
            widget.onReset?.call();
          }
        } catch (_) {
          widget.onReset?.call();
        }
      },
    );
  }
}
