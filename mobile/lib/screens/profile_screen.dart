import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';
import 'notification_settings_screen.dart';
import 'blocked_users_screen.dart';

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
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.surface(context),
        title: Text(
          '@$username',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            key: const Key('profile_btn_ayarlar'),
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
                          backgroundColor: AppColors.primaryBg(context),
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
                        const SizedBox(width: 20),
                        // İstatistikler
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatItem(count: _listings.length, label: 'İlan'),
                              GestureDetector(
                                key: const Key('profile_stat_takipci'),
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
                                key: const Key('profile_stat_takip'),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Profili Düzenle butonu
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: OutlinedButton(
                      key: const Key('profile_btn_profil_duzenle'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _EditProfileScreen(user: _user),
                        ),
                      ).then((_) => _load()),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 36),
                        side: BorderSide(color: AppColors.border(context)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        foregroundColor: AppColors.textPrimary(context),
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
                  Divider(height: 1, color: AppColors.divider(context)),
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
                      (ctx, i) => _ListingGridItem(
                        key: Key('profile_listing_${_listings[i]['id']}'),
                        listing: _listings[i],
                      ),
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
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
        ),
      ],
    );
  }
}

class _ListingGridItem extends StatelessWidget {
  final dynamic listing;
  const _ListingGridItem({super.key, required this.listing});

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
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (_, __, ___) => _placeholder(context),
                )
              : _placeholder(context),
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

  Widget _placeholder(BuildContext context) => Container(
        color: AppColors.surfaceVariant(context),
        child: Center(
          child: Icon(Icons.image_outlined,
              size: 28, color: AppColors.border(context)),
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

  Future<void> _showChangePasswordDialog(BuildContext context) async {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    bool codeSent = false;
    bool loading = false;
    String? error;

    final token = await StorageService.getToken();
    if (token == null || !mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card(ctx),
          title: Text(
            'Şifre Değiştir',
            style: TextStyle(
                color: AppColors.textPrimary(ctx),
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: currentPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: 'Mevcut Şifre',
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifre',
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: InputDecoration(
                    labelText: 'Yeni Şifre (Tekrar)',
                    labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                  ),
                ),
                if (codeSent) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: codeCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'E-posta Doğrulama Kodu',
                      labelStyle: TextStyle(color: AppColors.textSecondary(ctx)),
                      counterText: '',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: Color(0xFFEF4444), fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text('İptal',
                  style: TextStyle(color: AppColors.textSecondary(ctx))),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      setS(() {
                        error = null;
                        loading = true;
                      });

                      // Temel validasyon
                      if (currentPassCtrl.text.isEmpty ||
                          newPassCtrl.text.isEmpty ||
                          confirmPassCtrl.text.isEmpty) {
                        setS(() {
                          error = 'Tüm alanları doldurun.';
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text.length < 8) {
                        setS(() {
                          error = 'Yeni şifre en az 8 karakter olmalı.';
                          loading = false;
                        });
                        return;
                      }
                      if (newPassCtrl.text != confirmPassCtrl.text) {
                        setS(() {
                          error = 'Yeni şifreler eşleşmiyor.';
                          loading = false;
                        });
                        return;
                      }

                      if (!codeSent) {
                        // Doğrulama kodunu gönder
                        try {
                          final resp = await http.post(
                            Uri.parse('$kBaseUrl/auth/change-password/send-code'),
                            headers: {'Authorization': 'Bearer $token'},
                          );
                          if (resp.statusCode == 200) {
                            setS(() {
                              codeSent = true;
                              loading = false;
                            });
                          } else {
                            final msg = jsonDecode(resp.body)['detail'] as String?;
                            setS(() {
                              error = msg ?? 'Kod gönderilemedi.';
                              loading = false;
                            });
                          }
                        } catch (_) {
                          setS(() {
                            error = 'Bağlantı hatası.';
                            loading = false;
                          });
                        }
                      } else {
                        // Kodu doğrula ve şifreyi değiştir
                        if (codeCtrl.text.trim().length != 6) {
                          setS(() {
                            error = 'Doğrulama kodunu girin.';
                            loading = false;
                          });
                          return;
                        }
                        try {
                          final resp = await http.post(
                            Uri.parse('$kBaseUrl/auth/change-password/confirm'),
                            headers: {
                              'Content-Type': 'application/json',
                              'Authorization': 'Bearer $token',
                            },
                            body: jsonEncode({
                              'current_password': currentPassCtrl.text,
                              'new_password': newPassCtrl.text,
                              'code': codeCtrl.text.trim(),
                            }),
                          );
                          if (resp.statusCode == 200) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Şifreniz başarıyla değiştirildi.')),
                              );
                            }
                          } else {
                            final msg = jsonDecode(resp.body)['detail'] as String?;
                            setS(() {
                              error = msg ?? 'İşlem başarısız.';
                              loading = false;
                            });
                          }
                        } catch (_) {
                          setS(() {
                            error = 'Bağlantı hatası.';
                            loading = false;
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      codeSent ? 'Şifremi Değiştir' : 'Kodu Gönder',
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
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
                enableSuggestions: false,
                autocorrect: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
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
      backgroundColor: AppColors.bg(context),
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
                onTap: () => _showChangePasswordDialog(context),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                label: 'Bildirim Ayarları',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.block_outlined,
                label: 'Engellenen Kullanıcılar',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BlockedUsersScreen(),
                  ),
                ),
              ),
              if (_biometricAvailable)
                SwitchListTile(
                  key: const Key('settings_switch_face_id'),
                  secondary: Icon(Icons.face_outlined,
                      color: AppColors.iconColor(context)),
                  title: Text('Face ID ile Giriş',
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
                  subtitle: Text(
                    _biometricEnabled ? 'Açık' : 'Kapalı',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary(context)),
                  ),
                  value: _biometricEnabled,
                  activeColor: kPrimary,
                  onChanged: _toggleBiometric,
                ),
              SwitchListTile(
                key: const Key('settings_switch_karanlik_mod'),
                secondary: Icon(Icons.dark_mode_outlined, color: AppColors.iconColor(context)),
                title: Text('Karanlık Mod', style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
                subtitle: Text(
                  ThemeProvider.instance.isDark ? 'Açık' : 'Kapalı',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
                value: ThemeProvider.instance.isDark,
                activeColor: kPrimary,
                onChanged: (_) async {
                  await ThemeProvider.instance.toggle();
                  if (mounted) setState(() {});
                },
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
            color: AppColors.surface(context),
            child: Column(
              children: [
                ListTile(
                  key: const Key('settings_tile_hesabi_sil'),
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
                  key: const Key('settings_tile_cikis_yap'),
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
      color: AppColors.surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary(context),
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
      leading: Icon(icon, color: AppColors.iconColor(context)),
      title: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context))),
      trailing: Icon(Icons.chevron_right, color: AppColors.border(context), size: 20),
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
  String? _profileImageUrl;

  // Username availability check
  String? _usernameStatus; // null | 'checking' | 'available' | 'taken'
  Timer? _usernameDebounce;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user?['full_name'] ?? '');
    _usernameCtrl = TextEditingController(text: widget.user?['username'] ?? '');
    _profileImageUrl = widget.user?['profile_image_url'] as String?;
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final val = _usernameCtrl.text.trim();
    _usernameDebounce?.cancel();
    if (val == (widget.user?['username'] ?? '')) {
      setState(() => _usernameStatus = null);
      return;
    }
    if (val.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(val)) {
      setState(() => _usernameStatus = null);
      return;
    }
    setState(() => _usernameStatus = 'checking');
    _usernameDebounce = Timer(const Duration(milliseconds: 600), () => _checkUsername(val));
  }

  Future<void> _checkUsername(String val) async {
    try {
      final excludeId = widget.user?['id'] as int?;
      final params = {'username': val};
      if (excludeId != null) params['exclude_id'] = excludeId.toString();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/auth/check-username').replace(queryParameters: params),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _usernameStatus = (data['available'] as bool) ? 'available' : 'taken');
      }
    } catch (_) {
      if (mounted) setState(() => _usernameStatus = null);
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

    setState(() => _saving = true);
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
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
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
      if (mounted) setState(() => _profileImageUrl = imageUrl);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf yüklenemedi. Tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    if (name.isEmpty || username.isEmpty) {
      setState(() => _error = 'Tüm alanları doldurun');
      return;
    }
    if (username.length < 3 || !RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(() => _error = 'Kullanıcı adı geçersiz. Sadece küçük harf, rakam ve _ kullanılabilir.');
      return;
    }
    if (_usernameStatus == 'taken') {
      setState(() => _error = 'Bu kullanıcı adı zaten alınmış');
      return;
    }
    if (_usernameStatus == 'checking') {
      setState(() => _error = 'Kullanıcı adı kontrol ediliyor, lütfen bekleyin...');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('No token');
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/auth/me'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'full_name': name, 'username': username}),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body);
        throw Exception(body['detail'] ?? 'Hata');
      }
      final updatedUser = jsonDecode(resp.body) as Map<String, dynamic>;
      await StorageService.saveUserInfo(
        id: updatedUser['id'] as int,
        email: updatedUser['email'] as String,
        username: updatedUser['username'] as String,
        fullName: updatedUser['full_name'] as String,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = (_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : '?').toUpperCase();
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
            // Avatar
            GestureDetector(
              onTap: _saving ? null : _pickAndUploadAvatar,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primaryBg(context),
                    backgroundImage: (_profileImageUrl?.isNotEmpty == true)
                        ? NetworkImage(_buildImageUrl(_profileImageUrl!))
                        : null,
                    child: (_profileImageUrl?.isNotEmpty == true)
                        ? null
                        : Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: kPrimary,
                            ),
                          ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    ),
                  ),
                ],
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
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Kullanıcı Adı',
                helperText: 'Küçük harf, rakam ve _ kullanılabilir',
                helperStyle: const TextStyle(fontSize: 11),
                suffixIcon: _usernameStatus == 'checking'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _usernameStatus == 'available'
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        : _usernameStatus == 'taken'
                            ? const Icon(Icons.cancel, color: Colors.red, size: 20)
                            : null,
              ),
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
      backgroundColor: AppColors.bg(context),
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
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    placeholder: (_, __) => const SizedBox(
                                      width: 60, height: 60,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                    ),
                                    errorWidget: (_, __, ___) => _imgPlaceholder())
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

  Widget _imgPlaceholder() => Builder(
        builder: (context) => Container(
          width: 60, height: 60,
          color: AppColors.surfaceVariant(context),
          child: Icon(Icons.image_outlined, color: AppColors.border(context)),
        ),
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
      backgroundColor: AppColors.bg(context),
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
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 60, height: 60, fit: BoxFit.cover,
                                    placeholder: (_, __) => const SizedBox(
                                      width: 60, height: 60,
                                      child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)),
                                    ),
                                    errorWidget: (_, __, ___) => _imgPlaceholder())
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

