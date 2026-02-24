import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

enum ForgotPasswordStep { request, reset, success }

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  ForgotPasswordStep _step = ForgotPasswordStep.request;

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestReset() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    final success = await ref.read(authProvider.notifier).requestPasswordReset(email);

    if (success && mounted) {
      setState(() => _step = ForgotPasswordStep.reset);
    } else if (mounted) {
      final error = ref.read(authProvider).error;
      messenger.showSnackBar(SnackBar(content: Text(error ?? 'Bir hata oluştu.')));
    }
  }

  Future<void> _resetPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPassword = _newPasswordCtrl.text;

    if (code.length != 6 || newPassword.length < 6) {
      messenger.showSnackBar(const SnackBar(content: Text('Geçerli bir kod ve en az 6 karakterli şifre girin.')));
      return;
    }

    final success = await ref.read(authProvider.notifier).resetPassword(email, code, newPassword);

    if (success && mounted) {
      setState(() => _step = ForgotPasswordStep.success);
    } else if (mounted) {
      final error = ref.read(authProvider).error;
      messenger.showSnackBar(SnackBar(content: Text(error ?? 'Şifre sıfırlama başarısız.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Şifremi Unuttum'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildBody(isLoading),
        ),
      ),
    );
  }

  Widget _buildBody(bool isLoading) {
    if (_step == ForgotPasswordStep.success) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          const Center(child: Text('✅', style: TextStyle(fontSize: 64))),
          const SizedBox(height: 24),
          Text(
            'Şifreniz Sıfırlandı!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Yeni şifrenizle hemen hesabınıza giriş yapabilirsiniz.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF9AAAB8)),
          ),
          const SizedBox(height: 48),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Giriş Yap'),
            ),
          ),
        ],
      );
    }

    if (_step == ForgotPasswordStep.reset) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text(
            'Şifre Belirleme',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_emailCtrl.text.trim()} adresine gönderdiğimiz 6 haneli doğrulama kodunu ve yeni şifrenizi girin.',
            style: const TextStyle(color: Color(0xFF9AAAB8)),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _codeCtrl,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Doğrulama Kodu',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _newPasswordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Yeni Şifre',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : _resetPassword,
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Şifreyi Kaydet'),
            ),
          ),
        ],
      );
    }

    // Default: request
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Text(
          'Şifrenizi Mi Unuttunuz?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Hesabınıza kayıtlı e-posta adresinizi girin, size bir sıfırlama kodu gönderelim.',
          style: TextStyle(color: Color(0xFF9AAAB8)),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-posta',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: isLoading ? null : _requestReset,
            child: isLoading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Bağlantıyı Gönder'),
          ),
        ),
      ],
    );
  }
}
