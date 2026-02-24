import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/auth_provider.dart';

enum RegisterStep { register, verify, success }

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  RegisterStep _step = RegisterStep.register;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(authProvider.notifier).register(
        _nameCtrl.text.trim(), _emailCtrl.text.trim(), _passwordCtrl.text);

    if (result == 'pending_verification' && mounted) {
      setState(() => _step = RegisterStep.verify);
    } else if (result == 'success' && mounted) {
      setState(() => _step = RegisterStep.success);
    } else if (mounted) {
      final error = ref.read(authProvider).error;
      messenger.showSnackBar(SnackBar(content: Text(error ?? 'Kayıt başarısız.')));
    }
  }

  Future<void> _verify() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();

    if (code.length != 6) {
      messenger.showSnackBar(const SnackBar(content: Text('6 haneli doğrulama kodunu girin.')));
      return;
    }

    final success = await ref.read(authProvider.notifier).verifyEmail(email, code);

    if (success && mounted) {
      if (mounted) setState(() => _step = RegisterStep.success);
    } else if (mounted) {
      final error = ref.read(authProvider).error;
      messenger.showSnackBar(SnackBar(content: Text(error ?? 'Doğrulama başarısız.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authProvider).isLoading;
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıt Ol'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildBody(isLoading),
        ),
      ),
    );
  }

  Widget _buildBody(bool isLoading) {
    if (_step == RegisterStep.success) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          const Center(child: Text('🎉', style: TextStyle(fontSize: 64))),
          const SizedBox(height: 24),
          Text(
            'Hoş Geldin, ${_nameCtrl.text.trim().split(' ').first}!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hesabınız başarıyla onaylandı. Yeni hesabınızla giriş yapabilirsiniz.',
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

    if (_step == RegisterStep.verify) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text(
            'E-postanızı Doğrulayın',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${_emailCtrl.text.trim()} adresine 6 haneli bir doğrulama kodu gönderdik. Lütfen kodu aşağıya girin.',
            style: const TextStyle(color: Color(0xFF9AAAB8)),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _codeCtrl,
            maxLength: 6,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: 'Doğrulama Kodu',
              counterText: '',
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isLoading ? null : _verify,
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Hesabı Onayla'),
            ),
          ),
        ],
      );
    }

    // Default: register mode
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'teqlif',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w900,
              fontSize: 36,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [Color(0xFF00B4CC), Color(0xFF008FA3)],
                ).createShader(const Rect.fromLTWH(0, 0, 180, 45)),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Ad Soyad',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-posta',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Şifre',
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: isLoading ? null : _register,
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Kayıt Ol'),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: const Text('Zaten hesabın var mı? Giriş yap'),
          ),
        ),
      ],
    );
  }
}
