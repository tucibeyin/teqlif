import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/theme.dart';
import '../config/api.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'messages_screen.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String username;
  final int? userId;
  const PublicProfileScreen({super.key, required this.username, this.userId});
  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Map<String, dynamic>? _user;
  List<dynamic> _listings = [];
  bool _loading = true;
  bool _isOwnProfile = false;
  bool _isFollowing = false;
  bool _followLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    final data = await NotificationService.getUserByUsername(widget.username);
    final info = await StorageService.getUserInfo();
    final isOwn = info != null && info['username'] == widget.username;

    List<dynamic> listings = [];
    bool isFollowing = false;

    if (data != null) {
      final userId = data['id'] as int;
      // Fetch listings
      try {
        final headers = await _authHeaders();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/listings?user_id=$userId'),
          headers: headers,
        );
        if (resp.statusCode == 200) listings = jsonDecode(resp.body) as List;
      } catch (_) {}

      // is_following is now included in the profile response
      if (!isOwn && info != null && data != null) {
        isFollowing = (data['is_following'] as bool?) ?? false;
      }
    }

    if (mounted) {
      setState(() {
        _user = data;
        _listings = listings;
        _isOwnProfile = isOwn;
        _isFollowing = isFollowing;
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    setState(() => _followLoading = true);
    try {
      final headers = await _authHeaders();
      if (_isFollowing) {
        await http.delete(Uri.parse('$kBaseUrl/follows/$userId'), headers: headers);
        setState(() => _isFollowing = false);
      } else {
        await http.post(Uri.parse('$kBaseUrl/follows/$userId'), headers: headers);
        setState(() => _isFollowing = true);
      }
      // Refresh counts
      final fresh = await NotificationService.getUserByUsername(widget.username);
      if (mounted && fresh != null) setState(() => _user = fresh);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _user == null
              ? const Center(child: Text('Kullanıcı bulunamadı'))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final fullName = (_user!['full_name'] as String?) ?? widget.username;
    final userId = (_user!['id'] as int?) ?? widget.userId ?? 0;
    final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
    final listingCount = _user!['listing_count'] ?? 0;
    final followerCount = _user!['follower_count'] ?? 0;
    final followingCount = _user!['following_count'] ?? 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 44,
                  backgroundColor: kPrimary.withOpacity(0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: kPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${widget.username}',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
                const SizedBox(height: 20),
                // Stats row
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _statCell('İlanlar', listingCount)),
                      _divider(),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FollowListScreen(
                                userId: userId,
                                type: FollowListType.followers,
                                title: 'Takipçiler',
                              ),
                            ),
                          ),
                          child: _statCell('Takipçi', followerCount),
                        ),
                      ),
                      _divider(),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FollowListScreen(
                                userId: userId,
                                type: FollowListType.following,
                                title: 'Takip Edilenler',
                              ),
                            ),
                          ),
                          child: _statCell('Takip', followingCount),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Action buttons
                if (_isOwnProfile) ...[
                  _actionButton(
                    label: 'Profili Düzenle',
                    icon: Icons.edit_outlined,
                    primary: false,
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profil düzenleme yakında')),
                    ),
                  ),
                ] else if (userId != 0) ...[
                  _actionButton(
                    label: _isFollowing ? 'Takip Ediliyor' : 'Takip Et',
                    icon: _isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
                    primary: !_isFollowing,
                    onPressed: _followLoading ? null : _toggleFollow,
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    label: 'Mesaj Gönder',
                    icon: Icons.chat_bubble_outline,
                    primary: false,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DirectChatScreen(
                          otherUserId: userId,
                          displayName: fullName,
                          otherHandle: widget.username,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'İlanları (${_listings.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        if (_listings.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Henüz ilan yok',
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final listing = Map<String, dynamic>.from(_listings[i]);
                  final imgs = listing['image_urls'] as List? ?? [];
                  final raw = imgs.isNotEmpty
                      ? imgs[0] as String
                      : listing['image_url'] as String?;
                  final photo = raw != null ? imgUrl(raw) : null;
                  final price = listing['price'];
                  final priceStr = price != null
                      ? () {
                          final s = (price as num).toInt().toString();
                          final buf = StringBuffer();
                          for (int j = 0; j < s.length; j++) {
                            if (j > 0 && (s.length - j) % 3 == 0) buf.write('.');
                            buf.write(s[j]);
                          }
                          return '${buf.toString()} ₺';
                        }()
                      : '';
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        photo != null
                            ? Image.network(
                                photo,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFF3F4F6),
                                  child: const Icon(Icons.image_outlined,
                                      size: 28, color: Color(0xFFD1D5DB)),
                                ),
                              )
                            : Container(
                                color: const Color(0xFFF3F4F6),
                                child: const Icon(Icons.image_outlined,
                                    size: 28, color: Color(0xFFD1D5DB)),
                              ),
                        if (priceStr.isNotEmpty)
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
                                priceStr,
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
                },
                childCount: _listings.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _statCell(String label, dynamic count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              '$count',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: const Color(0xFFE5E7EB),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? kPrimary : const Color(0xFFF1F5F9),
          foregroundColor: primary ? Colors.white : const Color(0xFF334155),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
      ),
    );
  }

}
