import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_exception.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/locale_provider.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/storage_service.dart';
import 'register_screen.dart';
import 'verify_screen.dart';
import 'forgot_password_screen.dart';
import '../../ui_library/components/inputs/teq_text_field.dart';
import '../../ui_library/components/buttons/teq_button.dart';
import '../../ui_library/components/overlays/teq_snackbar.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });
    try {
      await AuthService.login(
        identifier: _identifierCtrl.text.trim(),
        password: _passCtrl.text,
      );

      // Giriş yapıldıktan sonra kullanıcının DB'deki locale bilgisini çek ve senkronize et
      try {
        final user = await AuthService.me();
        if (user.locale != null && user.locale!.isNotEmpty && mounted) {
          ref
              .read(localeProvider.notifier)
              .setLocaleLocally(Locale(user.locale!));
        }
      } catch (_) {}

      PushNotificationService.initialize();
      if (!mounted) return;
      // Biyometrik henüz etkin değilse ve cihaz destekliyorsa teklif et
      final alreadyEnabled = await StorageService.isBiometricEnabled();
      if (!alreadyEnabled && await BiometricService.isAvailable() && mounted) {
        await _offerBiometric();
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (e is AppException && e.code == 'EMAIL_NOT_VERIFIED' && mounted) {
        final email =
            e.extra['email']?.toString() ?? _identifierCtrl.text.trim();
        try {
          await AuthService.resendCode(email);
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VerifyScreen(email: email, resent: true),
            ),
          );
        }
      } else if (mounted) {
        TeqSnackBar.show(
          context,
          message: e.toString(),
          type: TeqSnackBarType.error,
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _offerBiometric() async {
    final l = AppLocalizations.of(context)!;
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Text('🔒 ', style: TextStyle(fontSize: 20)),
            Text(l.profileFaceId),
          ],
        ),
        content: Text(l.loginFaceIdDesc, style: const TextStyle(fontSize: 14)),
        actions: [
          TeqButton.text(
            text: l.btnNotNow,
            onPressed: () => Navigator.pop(context, false),
            customColor: const Color(0xFF6B7280),
            isExpanded: false,
          ),
          TeqButton(
            text: l.btnEnable,
            onPressed: () => Navigator.pop(context, true),
            isExpanded: false,
          ),
        ],
      ),
    );
    if (enable == true) {
      await StorageService.setBiometricEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'teqlif',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: kPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        l.loginWelcome,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.loginSubtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TeqTextField(
                              controller: _identifierCtrl,
                              keyboardType: TextInputType.visiblePassword,
                              labelText: l.fieldLoginIdentifier,
                              validator: (v) => v == null || v.isEmpty
                                  ? l.fieldLoginIdentifierHint
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TeqTextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              keyboardType: TextInputType.visiblePassword,
                              labelText: l.fieldPassword,
                              suffixIcon: IconButton(
                                key: const Key('login_btn_password_visibility'),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? l.fieldPasswordHint
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TeqButton.text(
                                text: l.forgotPassword,
                                isExpanded: false,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                            TeqButton(
                              text: l.btnLogin,
                              isLoading: _loading,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            l.loginNoAccount,
                            style: TextStyle(
                              color: AppColors.textSecondary(context),
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            key: const Key('login_link_kayit_ol'),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterScreen(),
                              ),
                            ),
                            child: Text(
                              l.loginRegisterLink,
                              style: const TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.language_outlined,
                        size: 14,
                        color: AppColors.textSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        l.settingsLanguage,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'tr',
                        label: Text(AppLocalizations.of(context)!.langTR),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(AppLocalizations.of(context)!.langEN),
                      ),
                      ButtonSegment(
                        value: 'ar',
                        label: Text(AppLocalizations.of(context)!.langAR),
                      ),
                      ButtonSegment(
                        value: 'ru',
                        label: Text(AppLocalizations.of(context)!.langRU),
                      ),
                    ],
                    selected: {currentLocale.languageCode},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (selection) {
                      ref
                          .read(localeProvider.notifier)
                          .setLocale(Locale(selection.first));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
