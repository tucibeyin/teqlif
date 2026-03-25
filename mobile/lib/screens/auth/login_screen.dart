import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/storage_service.dart';
import '../../utils/error_helper.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; });
    try {
      await AuthService.login(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
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
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() { _loading = false; });
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
        content: Text(
          l.loginFaceIdDesc,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            key: const Key('login_biometric_btn_simdi_degil'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.btnNotNow, style: const TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            key: const Key('login_biometric_btn_etkinlestir'),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.btnEnable, style: const TextStyle(color: Colors.white)),
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
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Center(
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
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  l.loginSubtitle,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                ),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const Key('login_input_email'),
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(labelText: l.fieldEmail),
                        validator: (v) =>
                            v == null || v.isEmpty ? l.fieldEmailHint : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('login_input_password'),
                        controller: _passCtrl,
                        obscureText: _obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        smartDashesType: SmartDashesType.disabled,
                        smartQuotesType: SmartQuotesType.disabled,
                        decoration: InputDecoration(
                          labelText: l.fieldPassword,
                          suffixIcon: IconButton(
                            key: const Key('login_btn_password_visibility'),
                            icon: Icon(_obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? l.fieldPasswordHint : null,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('login_btn_submit'),
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
                            : Text(l.btnLogin),
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
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
                    ),
                    GestureDetector(
                      key: const Key('login_link_kayit_ol'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen()),
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
      ),
    );
  }
}
