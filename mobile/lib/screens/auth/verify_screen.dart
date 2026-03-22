import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/push_notification_service.dart';
import '../../utils/error_helper.dart';

class VerifyScreen extends StatefulWidget {
  final String email;
  const VerifyScreen({super.key, required this.email});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  String? _success;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.length != 6) {
      showErrorSnackbar(context, Exception('6 haneli kodu giriniz'));
      return;
    }
    setState(() { _loading = true; _success = null; });
    try {
      await AuthService.verify(
        email: widget.email,
        code: _codeCtrl.text.trim(),
      );
      PushNotificationService.initialize();
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _resending = true; _success = null; });
    try {
      final msg = await AuthService.resendCode(widget.email);
      if (mounted) setState(() => _success = msg);
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('E-posta Doğrulama')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 48, color: kPrimary),
            const SizedBox(height: 16),
            const Text(
              'Kodunu gir',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.email} adresine 6 haneli doğrulama kodu gönderdik.',
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
                  : const Text('Doğrula'),
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
                      child: const Text(
                        'Kodu tekrar gönder',
                        style: TextStyle(color: kPrimary),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
