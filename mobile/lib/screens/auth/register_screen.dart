import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../services/localization_service.dart';
import '../../widgets/phone_input_field.dart';
import 'verify_screen.dart';
import '../../ui_library/components/inputs/teq_text_field.dart';
import '../../ui_library/components/buttons/teq_button.dart';
import '../../ui_library/components/overlays/teq_snackbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ui_library/components/overlays/teq_dialog.dart';
import 'viewmodels/register_view_model.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  String? _phoneE164;

  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _eulaAccepted = false;

  String? _usernameStatus;
  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    _referralCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final val = _usernameCtrl.text.trim();
    _usernameDebounce?.cancel();
    if (val.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(val)) {
      setState(() => _usernameStatus = null);
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _checkUsername(val),
    );
  }

  Future<void> _checkUsername(String val) async {
    final status = await ref.read(registerViewModelProvider.notifier).checkUsername(val);
    if (mounted) setState(() => _usernameStatus = status);
  }

  void _showPhoneInfoDialog() {
    final loc = ref.read(localizationProvider);
    TeqDialog.show(
      context: context,
      title: '🔒 ${loc.t('phoneInfoTitle')}',
      message: loc.t('phoneInfoBody'),
      primaryButtonText: loc.t('phoneInfoGotIt'),
      onPrimaryPressed: () => Navigator.of(context).pop(),
    );
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaAccepted) {
      TeqSnackBar.show(
        message: ref.read(localizationProvider).t('validTermsRequired'),
        type: TeqSnackBarType.error,
      );
      return;
    }
    
    final referralCode = _referralCtrl.text.trim();
    final success = await ref.read(registerViewModelProvider.notifier).register(
      email: _emailCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      fullName: _fullNameCtrl.text.trim(),
      password: _passCtrl.text,
      phone: _phoneE164,
      referredBy: referralCode.isEmpty ? null : referralCode,
    );

    if (success && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyScreen(email: _emailCtrl.text.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(title: Text(loc.t('registerTitle'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.t('registerSubtitle'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                loc.t('registerJoin'),
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 28),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TeqTextField(
                      controller: _fullNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 100,
                      labelText: loc.t('fieldFullName'),
                      validator: (v) {
                        if (v == null || v.isEmpty) return loc.t('fieldFullNameHint');
                        if (v.trim().length < 2) return loc.t('validFullNameMin');
                        if (v.length > 100) return loc.t('validFullNameMax');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _usernameCtrl,
                      maxLength: 50,
                      labelText: loc.t('fieldUsername'),
                      helperText: loc.t('fieldUsernameSubtitle'),
                      suffixIcon: _usernameStatus == 'checking'
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _usernameStatus == 'available'
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : _usernameStatus == 'taken'
                                  ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                                  : null,
                      validator: (v) {
                        if (v == null || v.isEmpty) return loc.t('fieldUsernameHint');
                        if (v.length < 3) return loc.t('validUsernameMin');
                        if (v.length > 50) return loc.t('validUsernameMax');
                        if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) return loc.t('validUsernameChars');
                        if (_usernameStatus == 'taken') return loc.t('validUsernameTaken');
                        if (_usernameStatus == 'checking') return loc.t('usernameChecking');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 255,
                      labelText: loc.t('fieldEmail'),
                      validator: (v) {
                        if (v == null || v.isEmpty) return loc.t('fieldEmailHint');
                        if (v.length > 255) return loc.t('validEmailMax');
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                          return loc.t('validEmailInvalid');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          loc.t('fieldPhone'),
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _showPhoneInfoDialog,
                          child: Icon(
                            Icons.help_outline_rounded,
                            size: 15,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    PhoneInputField(
                      key: const Key('register_input_telefon'),
                      onChanged: (e164) => setState(() => _phoneE164 = e164),
                      onReset: () => setState(() => _phoneE164 = null),
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _referralCtrl,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 12,
                      labelText: 'Davet Kodu (isteğe bağlı)',
                      prefixIcon: const Icon(Icons.card_giftcard_outlined, size: 20),
                      helperText: 'Bir arkadaşın seni davet ettiyse kodunu gir',
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      labelText: loc.t('fieldPassword'),
                      suffixIcon: IconButton(
                        key: const Key('register_btn_password_visibility'),
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return loc.t('fieldPasswordHint');
                        if (v.length < 8) return loc.t('validPasswordMin');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _passConfirmCtrl,
                      obscureText: _obscureConfirm,
                      keyboardType: TextInputType.visiblePassword,
                      labelText: loc.t('fieldPasswordConfirm'),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return loc.t('fieldPasswordConfirmHint');
                        if (v != _passCtrl.text) return loc.t('validPasswordMismatch');
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          key: const Key('register_checkbox_eula'),
                          value: _eulaAccepted,
                          activeColor: kPrimary,
                          onChanged: (v) => setState(() => _eulaAccepted = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: GestureDetector(
                            key: const Key('register_gesture_eula_text'),
                            onTap: () => setState(() => _eulaAccepted = !_eulaAccepted),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary(context),
                                  ),
                                  children: [
                                    const TextSpan(text: 'teqlif '),
                                    WidgetSpan(
                                      child: GestureDetector(
                                        key: const Key('register_link_kullanim_sartlari'),
                                        onTap: () => _openUrl(
                                          'https://www.teqlif.com/kullanim-sartlari.html',
                                        ),
                                        child: const Text(
                                          'Kullanım Şartları ve EULA',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: kPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const TextSpan(
                                      text: '\'nı okudum, kabul ediyorum. Uygunsuz içeriklere sıfır tolerans politikasını anladım.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TeqButton(
                      text: loc.t('registerTitle'),
                      isLoading: ref.watch(registerViewModelProvider).isLoading,
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
                    loc.t('registerHaveAccount'),
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
                  ),
                  GestureDetector(
                    key: const Key('register_link_giris_yap'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      loc.t('registerLoginLink'),
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
    );
  }
}
