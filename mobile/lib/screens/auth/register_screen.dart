import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../core/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../widgets/phone_input_field.dart';
import 'verify_screen.dart';
import '../../ui_library/components/inputs/teq_text_field.dart';
import '../../ui_library/components/buttons/teq_button.dart';
import '../../ui_library/components/overlays/teq_snackbar.dart';
import '../../ui_library/components/overlays/teq_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  String? _phoneE164; // E.164 formatında telefon (+90532...)

  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _eulaAccepted = false;

  // Username availability check
  String? _usernameStatus; // null | 'checking' | 'available' | 'taken'
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
    try {
      final body = await apiCall(
        () => http.get(
          Uri.parse(
            '$kBaseUrl/auth/check-username',
          ).replace(queryParameters: {'username': val}),
        ),
      );
      if (!mounted) return;
      setState(
        () => _usernameStatus = (body['available'] as bool)
            ? 'available'
            : 'taken',
      );
    } catch (e) {
      LoggerService.instance.warning(
        'RegisterScreen',
        'Kullanıcı adı kontrolü başarısız: $e',
      );
      if (mounted) setState(() => _usernameStatus = null);
    }
  }

  void _showPhoneInfoDialog(BuildContext context, dynamic l) {
    TeqDialog.show(
      context: context,
      title: '🔒 ${l.phoneInfoTitle}',
      message: l.phoneInfoBody,
      primaryButtonText: l.phoneInfoGotIt,
      onPrimaryPressed: () => Navigator.of(context).pop(),
    );
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri))
      launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaAccepted) {
      final l = AppLocalizations.of(context)!;
      TeqSnackBar.show(
        context,
        message: l.validTermsRequired,
        type: TeqSnackBarType.error,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final referralCode = _referralCtrl.text.trim();
      await AuthService.register(
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        password: _passCtrl.text,
        phone: _phoneE164,
        referredBy: referralCode.isEmpty ? null : referralCode,
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyScreen(email: _emailCtrl.text.trim()),
          ),
        );
      }
    } catch (e) {
      if (mounted)
        TeqSnackBar.show(
          context,
          message: e.toString().replaceAll('Exception: ', ''),
          type: TeqSnackBarType.error,
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(title: Text(l.registerTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.registerSubtitle,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l.registerJoin,
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
                      controller: _fullNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 100,
                      labelText: l.fieldFullName,
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldFullNameHint;
                        if (v.trim().length < 2) return l.validFullNameMin;
                        if (v.length > 100) return l.validFullNameMax;
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _usernameCtrl,
                      maxLength: 50,
                      labelText: l.fieldUsername,
                      helperText: l.fieldUsernameSubtitle,
                      suffixIcon: _usernameStatus == 'checking'
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _usernameStatus == 'available'
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            )
                          : _usernameStatus == 'taken'
                          ? const Icon(
                              Icons.cancel,
                              color: Colors.red,
                              size: 20,
                            )
                          : null,
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldUsernameHint;
                        if (v.length < 3) return l.validUsernameMin;
                        if (v.length > 50) return l.validUsernameMax;
                        if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
                          return l.validUsernameChars;
                        }
                        if (_usernameStatus == 'taken')
                          return l.validUsernameTaken;
                        if (_usernameStatus == 'checking')
                          return l.usernameChecking;
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 255,
                      labelText: l.fieldEmail,
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldEmailHint;
                        if (v.length > 255) return l.validEmailMax;
                        if (!RegExp(
                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                        ).hasMatch(v)) {
                          return l.validEmailInvalid;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // ── Telefon Numarası (İsteğe Bağlı) ──────────────────────
                    Row(
                      children: [
                        Text(
                          l.fieldPhone,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _showPhoneInfoDialog(context, l),
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
                      prefixIcon: const Icon(
                        Icons.card_giftcard_outlined,
                        size: 20,
                      ),
                      helperText: 'Bir arkadaşın seni davet ettiyse kodunu gir',
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      labelText: l.fieldPassword,
                      suffixIcon: IconButton(
                        key: const Key('register_btn_password_visibility'),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldPasswordHint;
                        if (v.length < 8) return l.validPasswordMin;
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TeqTextField(
                      controller: _passConfirmCtrl,
                      obscureText: _obscureConfirm,
                      keyboardType: TextInputType.visiblePassword,
                      labelText: l.fieldPasswordConfirm,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty)
                          return l.fieldPasswordConfirmHint;
                        if (v != _passCtrl.text) return l.validPasswordMismatch;
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // EULA onay
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          key: const Key('register_checkbox_eula'),
                          value: _eulaAccepted,
                          activeColor: kPrimary,
                          onChanged: (v) =>
                              setState(() => _eulaAccepted = v ?? false),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: GestureDetector(
                            key: const Key('register_gesture_eula_text'),
                            onTap: () =>
                                setState(() => _eulaAccepted = !_eulaAccepted),
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
                                        key: const Key(
                                          'register_link_kullanim_sartlari',
                                        ),
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
                                      text:
                                          '\'nı okudum, kabul ediyorum. Uygunsuz içeriklere sıfır tolerans politikasını anladım.',
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
                      text: l.registerTitle,
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
                    l.registerHaveAccount,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                  GestureDetector(
                    key: const Key('register_link_giris_yap'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      l.registerLoginLink,
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
