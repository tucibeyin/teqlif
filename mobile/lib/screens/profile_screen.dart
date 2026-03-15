import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'follow_list_screen.dart';

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
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: kPrimaryBg,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                            ),
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

  @override
  Widget build(BuildContext context) {
    final imageUrl = listing['image_url'];
    return Container(
      color: const Color(0xFFF3F4F6),
      child: imageUrl != null
          ? Image.network(imageUrl, fit: BoxFit.cover)
          : const Center(
              child: Icon(Icons.image_outlined,
                  size: 28, color: Color(0xFFD1D5DB)),
            ),
    );
  }
}

// ── Ayarlar ekranı ────────────────────────────────────────────────────────────

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

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
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.archive_outlined,
                label: 'Pasif İlanlarım',
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.favorite_outline,
                label: 'Favorilerim',
                onTap: () {},
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
