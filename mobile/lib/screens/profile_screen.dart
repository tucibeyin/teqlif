import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await StorageService.getUserInfo();
      if (!mounted) return;
      final username = info?['username'] as String?;
      Map<String, dynamic>? profile;
      if (username != null) {
        profile = await NotificationService.getUserByUsername(username);
      }
      final userId = (profile ?? info)?['id'] as int?;
      List<dynamic> listings = [];
      if (userId != null) {
        final token = await StorageService.getToken();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/listings?user_id=$userId'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        );
        if (resp.statusCode == 200) listings = jsonDecode(resp.body) as List;
      }
      if (mounted) {
        setState(() {
          _user = profile ?? info;
          _listings = listings;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }


  String _buildImageUrl(String url) {
    if (url.startsWith('http')) return url;
    final origin = kBaseUrl.replaceFirst(RegExp(r'/api.*'), '');
    return '$origin$url';
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden Seç'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Kameradan Çek'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    final token = await StorageService.getToken();
    if (token == null) return;

    try {
      final file = File(picked.path);
      final uploadReq = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
      uploadReq.headers['Authorization'] = 'Bearer $token';
      uploadReq.files.add(await http.MultipartFile.fromPath('file', file.path));
      final uploadStream = await uploadReq.send();
      final uploadBody = await uploadStream.stream.bytesToString();
      if (uploadStream.statusCode != 200) throw Exception('Upload failed');
      final imageUrl = (jsonDecode(uploadBody) as Map)['url'] as String;

      final patchResp = await http.patch(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'profile_image_url': imageUrl}),
      );
      if (patchResp.statusCode != 200) throw Exception('Patch failed');
      final updatedUser = jsonDecode(patchResp.body) as Map<String, dynamic>;
      await StorageService.saveUserInfo(
        id: updatedUser['id'] as int,
        email: updatedUser['email'] as String,
        username: updatedUser['username'] as String,
        fullName: updatedUser['full_name'] as String,
      );
      if (mounted) setState(() => _user = updatedUser);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf yüklenemedi. Tekrar deneyin.')),
      );
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    final fullName = _user?['full_name'] ?? _user?['username'] ?? 'Kullanıcı';
    final username = _user?['username'] ?? '';
    final email = _user?['email'] ?? '';
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: Text(
          '@$username',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kPrimary,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Profil başlık bölümü ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        GestureDetector(
                          onTap: _pickAndUploadAvatar,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: kPrimaryBg,
                                backgroundImage: (_user?['profile_image_url'] as String?)?.isNotEmpty == true
                                    ? NetworkImage(_buildImageUrl(_user!['profile_image_url'] as String))
                                    : null,
                                child: (_user?['profile_image_url'] as String?)?.isNotEmpty == true
                                    ? null
                                    : Text(
                                        initial,
                                        style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w700,
                                          color: kPrimary,
                                        ),
                                      ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: kPrimary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        // İstatistikler
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(count: _listings.length, label: 'İlan'),
                              GestureDetector(
                                onTap: _user?['id'] != null
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FollowListScreen(
                                              userId: _user!['id'] as int,
                                              type: FollowListType.followers,
                                              title: 'Takipçiler',
                                            ),
                                          ),
                                        )
                                    : null,
                                child: _StatItem(
                                  count: (_user?['follower_count'] as int?) ?? 0,
                                  label: 'Takipçi',
                                ),
                              ),
                              GestureDetector(
                                onTap: _user?['id'] != null
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => FollowListScreen(
                                              userId: _user!['id'] as int,
                                              type: FollowListType.following,
                                              title: 'Takip Edilenler',
                                            ),
                                          ),
                                        )
                                    : null,
                                child: _StatItem(
                                  count: (_user?['following_count'] as int?) ?? 0,
                                  label: 'Takip',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Ad ve email
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Profili Düzenle butonu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _EditProfileScreen(user: _user),
                        ),
                      ).then((_) => _load()),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 36),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        foregroundColor: const Color(0xFF1A1A1A),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Profili Düzenle'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Separator
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                ],
              ),
            ),
            // ── İlanlar grid ──
            _listings.isEmpty
                ? const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.grid_off_outlined,
                              size: 52, color: Color(0xFFD1D5DB)),
                          SizedBox(height: 12),
                          Text(
                            'Henüz ilan yok',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'İlk ilanını ver!',
                            style: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ListingGridItem(listing: _listings[i]),
                      childCount: _listings.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 2,
                      mainAxisSpacing: 2,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _ListingGridItem extends StatelessWidget {
  final dynamic listing;
  const _ListingGridItem({required this.listing});

  String _fmt(dynamic price) {
    if (price == null) return '';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context) {
    final imgs = listing['image_urls'] as List? ?? [];
    final _raw = imgs.isNotEmpty
        ? imgs[0] as String
        : listing['image_url'] as String?;
    final imageUrl = _raw != null ? imgUrl(_raw) : null;
    final price = _fmt(listing['price']);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ListingDetailScreen(
              listing: Map<String, dynamic>.from(listing)),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl != null
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),
          if (price.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 14, 5, 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF3F4F6),
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 28, color: Color(0xFFD1D5DB)),
        ),
      );
}

// ── Ayarlar ekranı ────────────────────────────────────────────────────────────

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final available = await BiometricService.isAvailable();
    final enabled = await StorageService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Açarken bir kez doğrula
      final ok = await BiometricService.authenticate(
        reason: 'Face ID\'yi etkinleştirmek için doğrulayın',
      );
      if (!ok) return;
    }
    await StorageService.setBiometricEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final passCtrl = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Hesabı Kalıcı Olarak Sil',
            style: TextStyle(color: Color(0xFFEF4444), fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu işlem geri alınamaz. Tüm verileriniz 30 gün içinde kalıcı olarak silinecektir.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Şifreniz',
                  hintText: 'Onaylamak için şifrenizi girin',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 38),
              ),
              onPressed: () async {
                if (passCtrl.text.isEmpty) {
                  setS(() => error = 'Şifrenizi girin.');
                  return;
                }
                try {
                  await AuthService.deleteAccount(passCtrl.text);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
                  }
                } on ApiException catch (e) {
                  setS(() => error = e.message);
                } catch (_) {
                  setS(() => error = 'Hesap silinemedi. Şifrenizi kontrol edin.');
                }
              },
              child: const Text('Hesabı Sil', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      backgroundColor: const Color(0xFFF9FAFB),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _SettingsSection(
            title: 'İlanlarım',
            items: [
              _SettingsTile(
                icon: Icons.list_alt_outlined,
                label: 'Aktif İlanlarım',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _MyListingsScreen(active: true))),
              ),
              _SettingsTile(
                icon: Icons.archive_outlined,
                label: 'Pasif İlanlarım',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _MyListingsScreen(active: false))),
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: 'Favorilerim',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _FavoritesScreen())),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: 'Hesap',
            items: [
              _SettingsTile(
                icon: Icons.lock_outline,
                label: 'Şifre Değiştir',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Bildirim Ayarları',
                onTap: () {},
              ),
              if (_biometricAvailable)
                SwitchListTile(
                  secondary: const Icon(Icons.face_outlined,
                      color: Color(0xFF374151)),
                  title: const Text('Face ID ile Giriş',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    _biometricEnabled ? 'Açık' : 'Kapalı',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  value: _biometricEnabled,
                  activeColor: kPrimary,
                  onChanged: _toggleBiometric,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _SettingsSection(
            title: 'Destek',
            items: [
              _SettingsTile(
                icon: Icons.help_outline,
                label: 'Destek Merkezi',
                onTap: () async {
                  final uri = Uri.parse('https://teqlif.com/support.html');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                label: 'Kullanım Şartları & EULA',
                onTap: () async {
                  final uri = Uri.parse('https://teqlif.com/kullanim-sartlari.html');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                label: 'Gizlilik Politikası',
                onTap: () async {
                  final uri = Uri.parse('https://teqlif.com/gizlilik-politikasi');
                  if (await canLaunchUrl(uri)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  title: const Text(
                    'Hesabı Sil',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => _showDeleteAccountDialog(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                  title: const Text(
                    'Çıkış Yap',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    final nav = Navigator.of(context);
                    await AuthService.logout();
                    nav.pushNamedAndRemoveUntil('/login', (_) => false);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _SettingsSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.5,
              ),
            ),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingsTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF374151)),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing:
          const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
      onTap: onTap,
    );
  }
}

// ── Profil düzenle ekranı ──────────────────────────────────────────────────

class _EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? user;
  const _EditProfileScreen({required this.user});

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.user?['full_name'] ?? '');
    _usernameCtrl = TextEditingController(
        text: widget.user?['username'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty || username.isEmpty) {
      setState(() => _error = 'Tüm alanları doldurun');
      return;
    }
    setState(() { _saving = true; _error = null; });
    // TODO: API call when PATCH /auth/me is available
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              'Kaydet',
              style: TextStyle(
                color: _saving ? Colors.grey : kPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Avatar büyük
            CircleAvatar(
              radius: 44,
              backgroundColor: kPrimaryBg,
              child: Text(
                (_nameCtrl.text.isNotEmpty
                        ? _nameCtrl.text[0]
                        : '?')
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Ad Soyad'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(labelText: 'Kullanıcı Adı'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Aktif / Pasif ilanlarım ekranı ────────────────────────────────────────────

class _MyListingsScreen extends StatefulWidget {
  final bool active;
  const _MyListingsScreen({required this.active});

  @override
  State<_MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<_MyListingsScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final activeParam = widget.active ? 'true' : 'false';
      final resp = await http.get(
        Uri.parse('$kBaseUrl/listings/my?active=$activeParam'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _listings = jsonDecode(resp.body) as List);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(dynamic listing) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = listing['id'];
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) await _load();
    } catch (_) {}
  }

  Future<void> _delete(dynamic listing) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İlanı Sil'),
        content: const Text('Bu ilanı kalıcı olarak silmek istiyor musunuz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = listing['id'];
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/listings/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) await _load();
    } catch (_) {}
  }

  String _fmt(dynamic price) {
    if (price == null) return '';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.active ? 'Aktif İlanlarım' : 'Pasif İlanlarım')),
      backgroundColor: const Color(0xFFF9FAFB),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _listings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.active ? Icons.list_alt_outlined : Icons.archive_outlined,
                          size: 52, color: const Color(0xFFD1D5DB)),
                      const SizedBox(height: 12),
                      Text(
                        widget.active ? 'Aktif ilan yok' : 'Pasif ilan yok',
                        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _listings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final l = _listings[i];
                      final imgs = l['image_urls'] as List? ?? [];
                      final rawImg = imgs.isNotEmpty ? imgs[0] as String : l['image_url'] as String?;
                      final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? Image.network(imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _imgPlaceholder())
                                : _imgPlaceholder(),
                          ),
                          title: Text(l['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(_fmt(l['price']),
                              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  widget.active ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: widget.active ? const Color(0xFF6B7280) : kPrimary,
                                  size: 22,
                                ),
                                tooltip: widget.active ? 'Pasife Al' : 'Aktif Yap',
                                onPressed: () => _toggle(l),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 22),
                                tooltip: 'Sil',
                                onPressed: () => _delete(l),
                              ),
                            ],
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(
                                  listing: Map<String, dynamic>.from(l)),
                            ),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 60, height: 60,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.image_outlined, color: Color(0xFFD1D5DB)),
      );
}

// ── Favorilerim ekranı ─────────────────────────────────────────────────────────

class _FavoritesScreen extends StatefulWidget {
  const _FavoritesScreen();

  @override
  State<_FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<_FavoritesScreen> {
  List<dynamic> _listings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final resp = await http.get(
        Uri.parse('$kBaseUrl/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _listings = jsonDecode(resp.body) as List);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavorite(dynamic listing) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.delete(
        Uri.parse('$kBaseUrl/favorites/${listing['id']}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await _load();
    } catch (_) {}
  }

  String _fmt(dynamic price) {
    if (price == null) return '';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorilerim')),
      backgroundColor: const Color(0xFFF9FAFB),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _listings.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 52, color: Color(0xFFD1D5DB)),
                      SizedBox(height: 12),
                      Text('Henüz favori ilan yok',
                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _listings.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final l = _listings[i];
                      final imgs = l['image_urls'] as List? ?? [];
                      final rawImg = imgs.isNotEmpty ? imgs[0] as String : l['image_url'] as String?;
                      final imageUrl = rawImg != null ? imgUrl(rawImg) : null;
                      return Card(
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl != null
                                ? Image.network(imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _imgPlaceholder())
                                : _imgPlaceholder(),
                          ),
                          title: Text(l['title'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fmt(l['price']),
                                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                              Text('@${(l['user'] as Map?)?['username'] ?? ''}',
                                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.favorite, color: Colors.red, size: 22),
                            tooltip: 'Favoriden Çıkar',
                            onPressed: () => _removeFavorite(l),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(
                                  listing: Map<String, dynamic>.from(l)),
                            ),
                          ).then((_) => _load()),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 60, height: 60,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.image_outlined, color: Color(0xFFD1D5DB)),
      );
}
