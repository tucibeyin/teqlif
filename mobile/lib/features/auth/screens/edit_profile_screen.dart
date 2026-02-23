import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers/auth_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _passwordConfirmCtrl;
  
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _passwordCtrl = TextEditingController();
    _passwordConfirmCtrl = TextEditingController();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient().get('/api/profile');
      if (res.statusCode == 200) {
        final data = res.data as Map<String, dynamic>;
        _nameCtrl.text = data['name']?.toString() ?? '';
        _emailCtrl.text = data['email']?.toString() ?? '';
        _phoneCtrl.text = data['phone']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint('Fetch profile detail error: $e');
      setState(() => _error = 'Profil bilgileri yüklenemedi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final messenger = ScaffoldMessenger.of(context);
      
      final password = _passwordCtrl.text;
      final confirm = _passwordConfirmCtrl.text;
      
      if (password.isNotEmpty) {
        if (password.length < 6) {
          setState(() => _error = 'Şifre en az 6 karakter olmalıdır');
          if (mounted) setState(() => _isSaving = false);
          return;
        }
        if (password != confirm) {
          setState(() => _error = 'Şifreler birbiriyle eşleşmiyor');
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }

      final res = await ApiClient().patch('/api/profile', data: {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        if (password.isNotEmpty) 'password': password,
        if (password.isNotEmpty) 'passwordConfirm': confirm,
      });

      if (res.statusCode == 200) {
        // Sync Riverpod user state
        await ref.read(authProvider.notifier).checkAuth();
        
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Profil başarıyla güncellendi ✅', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
          context.pop();
        }
      } else {
        setState(() => _error = res.data['message'] ?? 'Güncelleme başarısız');
      }
    } catch (e) {
      debugPrint('Save profile error: $e');
      setState(() => _error = 'Bir ağ hatası oluştu, tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profilimi Düzenle')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Ad Soyad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(hintText: 'Adınızı girin'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ad boş bırakılamaz' : null,
                    ),
                    const SizedBox(height: 20),
                    const Text('E-Posta Adresi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'ornek@email.com'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'E-posta boş bırakılamaz';
                        if (!v.contains('@')) return 'Geçerli bir e-posta girin';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text('Telefon Numarası', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(hintText: '05XX XXX XX XX (İsteğe bağlı)'),
                    ),
                    const Divider(height: 48, thickness: 1),
                    const Text('Yeni Şifre', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Değiştirmek istemiyorsanız boş bırakın'),
                    ),
                    const SizedBox(height: 20),
                    const Text('Yeni Şifre (Tekrar)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordConfirmCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(hintText: 'Yeni şifrenizi tekrar girin'),
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF00B4CC),
                        foregroundColor: Colors.white,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Değişiklikleri Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}
