import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../core/logger_service.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/error_helper.dart';
import 'verify_screen.dart';

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
  final _phoneCtrl = TextEditingController();
  final _phoneMask = MaskTextInputFormatter(
    mask: '0### ### ## ##',
    filter: {'#': RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  bool _loading = false;
  bool _obscure = true;
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
    _phoneCtrl.dispose();
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
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(val));
  }

  Future<void> _checkUsername(String val) async {
    try {
      final body = await apiCall(
        () => http.get(
          Uri.parse('$kBaseUrl/auth/check-username')
              .replace(queryParameters: {'username': val}),
        ),
      );
      if (!mounted) return;
      setState(() => _usernameStatus = (body['available'] as bool) ? 'available' : 'taken');
    } catch (e) {
      LoggerService.instance.warning('RegisterScreen', 'Kullanıcı adı kontrolü başarısız: $e');
      if (mounted) setState(() => _usernameStatus = null);
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Telefon numarasını E.164 formatına çevirir: 0532... → +90532...
  String _toE164(String masked) {
    final digits = masked.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) return '+90${digits.substring(1)}';
    return '+90$digits';
  }

  /// Telefon numarasını E.164 formatına çevirir: 0532... → +90532...
  String? _toE164(String masked) {
    final digits = masked.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return null;
    return '+90${digits.substring(1)}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaAccepted) {
      final l = AppLocalizations.of(context)!;
      showErrorSnackbar(context, Exception(l.validTermsRequired));
      return;
    }
    setState(() => _loading = true);
    try {
      final phone = _toE164(_phoneCtrl.text.trim());
      await AuthService.register(
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        password: _passCtrl.text,
        phone: phone,
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyScreen(email: _emailCtrl.text.trim()),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
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
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                l.registerJoin,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 28),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      key: const Key('register_input_ad_soyad'),
                      controller: _fullNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 100,
                      decoration: InputDecoration(
                        labelText: l.fieldFullName,
                        counterText: '',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldFullNameHint;
                        if (v.trim().length < 2) return l.validFullNameMin;
                        if (v.length > 100) return l.validFullNameMax;
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('register_input_kullanici_adi'),
                      controller: _usernameCtrl,
                      autocorrect: false,
                      maxLength: 50,
                      decoration: InputDecoration(
                        labelText: l.fieldUsername,
                        helperText: l.fieldUsernameSubtitle,
                        helperStyle: const TextStyle(fontSize: 11),
                        counterText: '',
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
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20)
                                : _usernameStatus == 'taken'
                                    ? const Icon(Icons.cancel,
                                        color: Colors.red, size: 20)
                                    : null,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldUsernameHint;
                        if (v.length < 3) return l.validUsernameMin;
                        if (v.length > 50) return l.validUsernameMax;
                        if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
                          return l.validUsernameChars;
                        }
                        if (_usernameStatus == 'taken') return l.validUsernameTaken;
                        if (_usernameStatus == 'checking') return l.usernameChecking;
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('register_input_email'),
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      maxLength: 255,
                      decoration: InputDecoration(
                        labelText: l.fieldEmail,
                        counterText: '',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldEmailHint;
                        if (v.length > 255) return l.validEmailMax;
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                            .hasMatch(v)) {
                          return l.validEmailInvalid;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // ── Telefon Numarası (İsteğe Bağlı) ──────────────────────
                    TextFormField(
                      key: const Key('register_input_telefon'),
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_phoneMask],
                      decoration: InputDecoration(
                        labelText: l.fieldPhone,
                        hintText: l.fieldPhoneHint,
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        suffixIcon: _phoneCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _phoneCtrl.clear();
                                  _phoneMask.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      // Telefon opsiyonel — validasyon yok
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('register_input_sifre'),
                      controller: _passCtrl,
                      obscureText: _obscure,
                      enableSuggestions: false,
                      autocorrect: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      decoration: InputDecoration(
                        labelText: l.fieldPassword,
                        suffixIcon: IconButton(
                          key: const Key('register_btn_password_visibility'),
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      validator: (v) {
                        if (v == null || v.isEmpty) return l.fieldPasswordHint;
                        if (v.length < 8) return l.validPasswordMin;
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
                                        onTap: () => _openUrl('https://teqlif.com/kullanim-sartlari.html'),
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
                    ElevatedButton(
                      key: const Key('register_btn_submit'),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l.registerTitle),
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
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
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
