import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import 'reset_password_screen.dart';
import '../../ui_library/components/inputs/teq_text_field.dart';
import '../../ui_library/components/buttons/teq_button.dart';
import '../../ui_library/components/overlays/teq_snackbar.dart';
import '../../ui_library/components/overlays/teq_toast.dart';
import '../../core/app_exception.dart';
import '../../core/error_display.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();

    try {
      final lang = AppLocalizations.of(context)!.localeName;
      await AuthService.requestPasswordReset(email, lang: lang);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: email)),
      );
    } catch (e) {
      if (mounted) {
        if (e is AppException) {
          ErrorDisplay.fromException(context, e);
        } else {
          TeqToast.error(AppLocalizations.of(context)!.errorGenericRetry);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_reset,
                      size: 48,
                      color: kPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l.forgotPassword,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.resetPasswordDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TeqTextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    hintText: AppLocalizations.of(context)!.hintExampleEmail,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'E-posta boş olamaz';
                      if (!v.contains('@')) return 'Geçerli bir e-posta girin';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  TeqButton(
                    text: l.sendResetCode,
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
