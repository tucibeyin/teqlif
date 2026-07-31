import 'package:flutter/material.dart';
import 'teq_button.dart';

/// Async işlemleri tetikleyen butonlar için self-managing loading guard.
///
/// [onPressed] bir Future döndürür — buton, Future tamamlanana kadar
/// otomatik olarak loading spinner gösterir ve çift tıklamayı önler.
/// Ekranda _loading bool veya setState yönetimine gerek kalmaz.
///
/// Provider state'ine bağlı loading (örn. isMassNotifSending) gereken
/// durumlarda TeqButton + isLoading kullanmaya devam edin.
class TeqAsyncButton extends StatefulWidget {
  final String text;
  final Future<void> Function()? onPressed;
  final TeqButtonType type;
  final TeqButtonSize size;
  final bool isDisabled;
  final IconData? icon;
  final Color? customColor;
  final bool isExpanded;

  const TeqAsyncButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.type = TeqButtonType.primary,
    this.size = TeqButtonSize.medium,
    this.isDisabled = false,
    this.icon,
    this.customColor,
    this.isExpanded = true,
  });

  @override
  State<TeqAsyncButton> createState() => _TeqAsyncButtonState();
}

class _TeqAsyncButtonState extends State<TeqAsyncButton> {
  bool _loading = false;

  Future<void> _handlePress() async {
    if (_loading || widget.onPressed == null) return;
    setState(() => _loading = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TeqButton(
      text: widget.text,
      onPressed: widget.onPressed != null ? _handlePress : null,
      type: widget.type,
      size: widget.size,
      isLoading: _loading,
      isDisabled: widget.isDisabled,
      icon: widget.icon,
      customColor: widget.customColor,
      isExpanded: widget.isExpanded,
    );
  }
}
