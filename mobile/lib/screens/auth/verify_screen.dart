import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/localization_service.dart';
import '../../services/push_notification_service.dart';
import '../../ui_library/components/overlays/teq_toast.dart';
import '../../utils/error_helper.dart';
import 'category_onboarding_screen.dart';

class VerifyScreen extends ConsumerStatefulWidget {
  final String email;
  final bool resent;
  const VerifyScreen({super.key, required this.email, this.resent = false});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  late String? _success;

  @override
  void initState() {
    super.initState();
    _success = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.resent && _success == null) {
      final loc = ref.read(localizationProvider);
      _success = loc.t('authVerifyCodeSentMsg', {'email': widget.email});
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.length != 6) {
      final loc = ref.read(localizationProvider);
      TeqToast.error(loc.t('validVerificationCode'));
      return;
    }
    setState(() { _loading = true; _success = null; });
    try {
      await AuthService.verify(
        email: widget.email,
        code: _codeCtrl.text.trim(),
      );
      PushNotificationService.initialize();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CategoryOnboardingScreen(),
          ),
        );
      }
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _resending = true; _success = null; });
    try {
      final lang = ref.read(localizationProvider).lang;
      final msg = await AuthService.resendCode(widget.email, lang: lang);
      if (mounted) setState(() => _success = msg);
    } catch (e) {
      handleError(e, ref.read(localizationProvider));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(loc.t('verifyEmailTitle'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 48, color: kPrimary),
            const SizedBox(height: 16),
            Text(
              loc.t('authEnterCodeTitle'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              loc.t('authVerifyCodeSentDesc', {'email': widget.email}),
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 28),
            if (_success != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Text(
                  _success!,
                  style: const TextStyle(color: Color(0xFF166534), fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              key: const Key('verify_input_kod'),
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _verify(),
              decoration: const InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(
                  color: Color(0xFFD1D5DB),
                  letterSpacing: 12,
                  fontSize: 28,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const Key('verify_btn_dogrula'),
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(loc.t('btnVerify')),
            ),
            const SizedBox(height: 16),
            Center(
              child: _resending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      key: const Key('verify_btn_kodu_tekrar_gonder'),
                      onPressed: _resend,
                      child: Text(
                        loc.t('authResendCode'),
                        style: const TextStyle(color: kPrimary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
