import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_exception.dart';
import '../../services/localization_service.dart';
import '../../utils/error_helper.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
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
import '../../ui_library/components/overlays/teq_toast.dart';
import '../../widgets/language_switch_overlay.dart';

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
  late String _displayedLang;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _displayedLang = ref.read(localeProvider).languageCode;
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _onLangChange(String newLang) async {
    if (_isSwitching || newLang == _displayedLang) return;
    final prevLang = _displayedLang;
    setState(() {
      _isSwitching = true;
      _displayedLang = newLang;
    });
    final ok = await ref.read(localizationProvider.notifier).switchLanguage(newLang);
    if (!mounted) return;
    if (ok) {
      await ref.read(localeProvider.notifier).setLocale(Locale(newLang));
      if (!mounted) return;
      setState(() => _isSwitching = false);
      TeqToast.success(ref.read(localizationProvider).t('langSwitchSuccess'));
    } else {
      setState(() {
        _isSwitching = false;
        _displayedLang = prevLang;
      });
      TeqToast.error(ref.read(localizationProvider).t('langSwitchFailed'));
    }
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

      try {
        final user = await AuthService.me();
        if (user.locale != null && user.locale!.isNotEmpty && mounted) {
          ref.read(localeProvider.notifier).setLocaleLocally(Locale(user.locale!));
        }
      } catch (_) {}

      PushNotificationService.initialize();
      if (!mounted) return;
      final alreadyEnabled = await StorageService.isBiometricEnabled();
      if (!alreadyEnabled && await BiometricService.isAvailable() && mounted) {
        await _offerBiometric();
      }
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (e is AppException && e.code == 'EMAIL_NOT_VERIFIED' && mounted) {
        final email = e.extra['email']?.toString() ?? _identifierCtrl.text.trim();
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
        handleError(e, ref.read(localizationProvider));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _offerBiometric() async {
    final loc = ref.read(localizationProvider);
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Text('🔒 ', style: TextStyle(fontSize: 20)),
            Text(loc.t('profileFaceId')),
          ],
        ),
        content: Text(loc.t('loginFaceIdDesc'), style: const TextStyle(fontSize: 14)),
        actions: [
          TeqButton.text(
            text: loc.t('btnNotNow'),
            onPressed: () => Navigator.pop(context, false),
            customColor: const Color(0xFF6B7280),
            isExpanded: false,
          ),
          TeqButton(
            text: loc.t('btnEnable'),
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
    final loc = ref.watch(localizationProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: LanguageSwitchOverlay(
        isVisible: _isSwitching,
        child: SafeArea(
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
                      loc.t('loginWelcome'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.t('loginSubtitle'),
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
                            labelText: loc.t('fieldLoginIdentifier'),
                            validator: (v) => v == null || v.isEmpty
                                ? loc.t('fieldLoginIdentifierHint')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TeqTextField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            keyboardType: TextInputType.visiblePassword,
                            labelText: loc.t('fieldPassword'),
                            suffixIcon: IconButton(
                              key: const Key('login_btn_password_visibility'),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? loc.t('fieldPasswordHint')
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TeqButton.text(
                              text: loc.t('forgotPassword'),
                              isExpanded: false,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          TeqButton(
                            text: loc.t('btnLogin'),
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
                          loc.t('loginNoAccount'),
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
                            loc.t('loginRegisterLink'),
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
                        loc.t('settingsLanguage'),
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
                      ButtonSegment(value: 'tr', label: Text(loc.t('langTR'))),
                      ButtonSegment(value: 'en', label: Text(loc.t('langEN'))),
                      ButtonSegment(value: 'ar', label: Text(loc.t('langAR'))),
                      ButtonSegment(value: 'ru', label: Text(loc.t('langRU'))),
                    ],
                    selected: {_displayedLang},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (selection) => _onLangChange(selection.first),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
