import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final info = await StorageService.getUserInfo();
      if (info != null && mounted) {
        setState(() {
          _user = User(
            id: info['id'] as int,
            email: info['email'] as String,
            username: info['username'] as String,
            fullName: info['full_name'] as String,
            isVerified: true,
          );
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (mounted) Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesabım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _user == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Oturum açılmamış'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            Navigator.of(context).pushReplacementNamed('/login'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(160, 44),
                        ),
                        child: const Text('Giriş Yap'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    // Avatar + Name
                    Container(
                      padding: const EdgeInsets.all(24),
                      color: Colors.white,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundColor: kPrimaryBg,
                            child: Text(
                              _user!.fullName.isNotEmpty
                                  ? _user!.fullName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: kPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _user!.fullName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${_user!.username}',
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _user!.email,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MenuSection(
                      title: 'İlanlarım',
                      items: [
                        _MenuItem(
                          icon: Icons.list_alt_outlined,
                          label: 'Aktif İlanlarım',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.archive_outlined,
                          label: 'Pasif İlanlarım',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.favorite_outline,
                          label: 'Favorilerim',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _MenuSection(
                      title: 'Hesap',
                      items: [
                        _MenuItem(
                          icon: Icons.person_outline,
                          label: 'Profili Düzenle',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.lock_outline,
                          label: 'Şifre Değiştir',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.notifications_outlined,
                          label: 'Bildirim Ayarları',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      child: ListTile(
                        leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                        title: const Text(
                          'çıkış yap',
                          style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                        ),
                        onTap: _logout,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final String title;
  final List<_MenuItem> items;
  const _MenuSection({required this.title, required this.items});

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
              title,
              style: const TextStyle(
                fontSize: 12,
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

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF374151)),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB)),
      onTap: onTap,
    );
  }
}
