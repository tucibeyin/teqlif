import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/api.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
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
  bool _loading = false;
  String? _error;
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
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/check-username').replace(queryParameters: {'username': val}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _usernameStatus = (data['available'] as bool) ? 'available' : 'taken');
      }
    } catch (_) {
      if (mounted) setState(() => _usernameStatus = null);
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_eulaAccepted) {
      setState(() => _error = 'Kullanım Şartları\'nı kabul etmelisiniz.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.register(
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerifyScreen(email: _emailCtrl.text.trim()),
          ),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Bağlantı hatası. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(title: const Text('Kayıt Ol')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hesap oluştur',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'teqlif\'e katıl',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _fullNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Ad Soyad'),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ad soyad giriniz';
                        if (v.trim().length < 2) return 'Ad soyad en az 2 karakter olmalı';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _usernameCtrl,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Kullanıcı Adı',
                        helperText: 'Küçük harf, rakam ve _ kullanılabilir',
                        helperStyle: const TextStyle(fontSize: 11),
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
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Kullanıcı adı giriniz';
                        if (v.length < 3) return 'En az 3 karakter olmalı';
                        if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
                          return 'Sadece küçük harf, rakam ve _ kullanılabilir';
                        }
                        if (_usernameStatus == 'taken') return 'Bu kullanıcı adı zaten alınmış';
                        if (_usernameStatus == 'checking') return 'Kullanıcı adı kontrol ediliyor...';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'E-posta'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'E-posta giriniz' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Şifre giriniz';
                        if (v.length < 8) return 'En az 8 karakter olmalı';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // EULA onay
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _eulaAccepted,
                          activeColor: kPrimary,
                          onChanged: (v) => setState(() => _eulaAccepted = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: GestureDetector(
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
                          : const Text('Kayıt Ol'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Zaten hesabın var mı? ',
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Giriş yap',
                      style: TextStyle(
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
