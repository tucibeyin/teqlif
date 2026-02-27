import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/user.dart';
import '../../../core/providers/auth_provider.dart';

class VerifyProfileScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> profileData;

  const VerifyProfileScreen({super.key, required this.profileData});

  @override
  ConsumerState<VerifyProfileScreen> createState() => _VerifyProfileScreenState();
}

class _VerifyProfileScreenState extends ConsumerState<VerifyProfileScreen> {
  final _codeCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Lütfen 6 haneli doğrulama kodunu girin.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await ApiClient().patch('/api/profile', data: {
        ...widget.profileData,
        'verificationCode': code,
      });

      if (res.statusCode == 200) {
        // Parse the updated user from response
        final userData = res.data['user'] as Map<String, dynamic>;
        final updatedUser = UserModel.fromJson(userData);
        
        // Sync user state immediately for Dashboard
        await ref.read(authProvider.notifier).updateUserState(updatedUser);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil başarıyla güncellendi ✅'),
              backgroundColor: Colors.green,
            ),
          );
          // Go back to profile (pop verification, then previous screen will pop too or we go home)
          // Since we navigated from EditProfile, popping here takes us back to EditProfile.
          // But EditProfile should also probably pop if it was waiting.
          // Better: go to dashboard or home to refresh everything.
          context.go('/dashboard');
        }
      } else {
        setState(() => _error = res.data['message'] ?? 'Doğrulama başarısız.');
      }
    } catch (e) {
      debugPrint('Profile verify error: $e');
      setState(() => _error = 'Bir hata oluştu. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doğrulama')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'E-postanızı Doğrulayın',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Profil değişikliklerini onaylamak için e-posta adresinize gönderdiğimiz 6 haneli kodu lütfen aşağıya girin.',
                style: TextStyle(color: Color(0xFF9AAAB8), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              TextFormField(
                controller: _codeCtrl,
                maxLength: 6,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 32, letterSpacing: 12, fontWeight: FontWeight.bold, color: Color(0xFF00B4CC)),
                decoration: const InputDecoration(
                  labelText: 'Doğrulama Kodu',
                  labelStyle: TextStyle(letterSpacing: 0, fontSize: 14),
                  counterText: '',
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00B4CC), width: 2)),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4CC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Onayla ve Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : () => context.pop(),
                child: const Text('İptal Et', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
