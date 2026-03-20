import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../config/api.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import 'messages_screen.dart';
import 'follow_list_screen.dart';
import 'listing_detail_screen.dart';

const _starColor = Color(0xFFF59E0B);

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
  Map<String, dynamic>? _ratingSummary;

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

      try {
        final headers = await _authHeaders();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/listings?user_id=$userId'),
          headers: headers,
        );
        if (resp.statusCode == 200) listings = jsonDecode(resp.body) as List;
      } catch (_) {}

      if (!isOwn && info != null) {
        isFollowing = (data['is_following'] as bool?) ?? false;
      }

      try {
        final headers = await _authHeaders();
        final resp = await http.get(
          Uri.parse('$kBaseUrl/ratings/$userId/summary'),
          headers: headers,
        );
        if (resp.statusCode == 200 && mounted) {
          final summary = jsonDecode(resp.body) as Map<String, dynamic>;
          if (mounted) setState(() => _ratingSummary = summary);
        }
      } catch (_) {}
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

  Future<void> _loadRatingSummary() async {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    try {
      final headers = await _authHeaders();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ratings/$userId/summary'),
        headers: headers,
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() => _ratingSummary = jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (_) {}
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
      final fresh = await NotificationService.getUserByUsername(widget.username);
      if (mounted && fresh != null) setState(() => _user = fresh);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  void _showRatingForm() {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    final existingRating = _ratingSummary?['my_rating'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RatingFormSheet(
        userId: userId,
        authHeaders: _authHeaders,
        existingScore: existingRating?['score'] as int?,
        existingComment: existingRating?['comment'] as String?,
        onSaved: () {
          Navigator.pop(ctx);
          _loadRatingSummary();
        },
      ),
    );
  }

  void _showRatingsList() {
    if (_user == null) return;
    final userId = _user!['id'] as int;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RatingsListSheet(
        userId: userId,
        summary: _ratingSummary,
        authHeaders: _authHeaders,
      ),
    );
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
    final hasMyRating = _ratingSummary?['my_rating'] != null;
    final avgRaw = _ratingSummary?['average'];
    final hasRating = avgRaw != null;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            child: Column(
              children: [
                // Avatar
                _buildAvatar(fullName, initial),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '@${widget.username}',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                ),
                const SizedBox(height: 12),

                // Rating badge
                _buildRatingBadge(hasRating, avgRaw),
                const SizedBox(height: 12),

                // Stats row
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface(context),
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
                    icon: _isFollowing
                        ? Icons.person_remove_outlined
                        : Icons.person_add_outlined,
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
                  if (_isFollowing) ...[
                    const SizedBox(height: 8),
                    _actionButton(
                      label: hasMyRating ? 'Puanı Güncelle' : 'Puan Ver',
                      icon: hasMyRating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      primary: false,
                      onPressed: _showRatingForm,
                    ),
                  ],
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

        // Listings grid
        if (_listings.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Henüz ilan yok',
                  style: TextStyle(
                      color: AppColors.textTertiary(context), fontSize: 14),
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
                                errorBuilder: (c, __, ___) => Container(
                                  color: AppColors.surfaceVariant(c),
                                  child: Icon(Icons.image_outlined,
                                      size: 28, color: AppColors.border(c)),
                                ),
                              )
                            : Builder(
                                builder: (c) => Container(
                                  color: AppColors.surfaceVariant(c),
                                  child: Icon(Icons.image_outlined,
                                      size: 28, color: AppColors.border(c)),
                                ),
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

  Widget _buildAvatar(String fullName, String initial) {
    final imgUrl = _user?['profile_image_url'] as String?;
    if (imgUrl != null) {
      return CircleAvatar(
        radius: 44,
        backgroundColor: kPrimary.withOpacity(0.15),
        backgroundImage: NetworkImage(imgUrl),
      );
    }
    return CircleAvatar(
      radius: 44,
      backgroundColor: kPrimary.withOpacity(0.15),
      child: Text(
        initial,
        style: const TextStyle(
            fontSize: 36, fontWeight: FontWeight.bold, color: kPrimary),
      ),
    );
  }

  Widget _buildRatingBadge(bool hasRating, dynamic avgRaw) {
    if (!hasRating) {
      return Text(
        'Henüz değerlendirme yok',
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
      );
    }
    final avg = (avgRaw as num).toDouble();
    final count = _ratingSummary!['count'] as int;
    final filled = avg.round().clamp(0, 5);

    return GestureDetector(
      onTap: _showRatingsList,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border(context), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${'★' * filled}${'☆' * (5 - filled)}',
              style: const TextStyle(
                  color: _starColor, fontSize: 16, letterSpacing: 1),
            ),
            const SizedBox(width: 6),
            Text(
              avg.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 5),
            Text(
              '($count puan)',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context)),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 16, color: AppColors.textTertiary(context)),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, dynamic count) => Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(context))),
            ],
          ),
        ),
      );

  Widget _divider() => Builder(
        builder: (context) => Container(
          width: 1,
          height: 36,
          color: AppColors.border(context),
        ),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    VoidCallback? onPressed,
  }) {
    return Builder(
      builder: (context) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                primary ? kPrimary : AppColors.surfaceVariant(context),
            foregroundColor:
                primary ? Colors.white : AppColors.textPrimary(context),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

// ── Rating form bottom sheet ─────────────────────────────────────────────────

class _RatingFormSheet extends StatefulWidget {
  final int userId;
  final Future<Map<String, String>> Function() authHeaders;
  final int? existingScore;
  final String? existingComment;
  final VoidCallback onSaved;

  const _RatingFormSheet({
    required this.userId,
    required this.authHeaders,
    this.existingScore,
    this.existingComment,
    required this.onSaved,
  });

  @override
  State<_RatingFormSheet> createState() => _RatingFormSheetState();
}

class _RatingFormSheetState extends State<_RatingFormSheet> {
  int _selected = 0;
  bool _saving = false;
  late final TextEditingController _commentCtrl;

  static const _labels = [
    '',
    'Çok kötü',
    'Kötü',
    'Orta',
    'İyi',
    'Mükemmel'
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.existingScore ?? 0;
    _commentCtrl = TextEditingController(text: widget.existingComment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected == 0) return;
    setState(() => _saving = true);
    try {
      final headers = await widget.authHeaders();
      final comment = _commentCtrl.text.trim();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/ratings/${widget.userId}'),
        headers: headers,
        body: jsonEncode({
          'score': _selected,
          'comment': comment.isEmpty ? null : comment,
        }),
      );
      if (resp.statusCode == 200) {
        widget.onSaved();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Puan kaydedilemedi')),
          );
          setState(() => _saving = false);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.existingScore != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              isUpdate ? 'Puanı Güncelle' : 'Puan Ver',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 22),

          // Star picker
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final v = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _selected = v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    v <= _selected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _starColor,
                    size: 46,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            _selected > 0 ? _labels[_selected] : 'Bir yıldız seçin',
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  _selected > 0 ? FontWeight.w600 : FontWeight.normal,
              color: _selected > 0
                  ? _starColor
                  : AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 18),

          // Comment field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _commentCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'Neden bu puanı veriyorsunuz? (isteğe bağlı)',
                hintStyle: TextStyle(
                    color: AppColors.textTertiary(context), fontSize: 14),
                filled: true,
                fillColor: AppColors.inputFill(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
                counterStyle: TextStyle(
                    color: AppColors.textTertiary(context), fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: AppColors.border(context)),
                    ),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_selected == 0 || _saving) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kPrimary.withOpacity(0.4),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Kaydet',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ratings list bottom sheet ────────────────────────────────────────────────

class _RatingsListSheet extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? summary;
  final Future<Map<String, String>> Function() authHeaders;

  const _RatingsListSheet({
    required this.userId,
    required this.summary,
    required this.authHeaders,
  });

  @override
  State<_RatingsListSheet> createState() => _RatingsListSheetState();
}

class _RatingsListSheetState extends State<_RatingsListSheet> {
  List<dynamic>? _ratings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    try {
      final headers = await widget.authHeaders();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/ratings/${widget.userId}'),
        headers: headers,
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _ratings = jsonDecode(resp.body) as List;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = [
        'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgRaw = widget.summary?['average'];
    final count = widget.summary?['count'] as int? ?? 0;
    final avg = avgRaw != null ? (avgRaw as num).toDouble() : null;
    final filled = avg != null ? avg.round().clamp(0, 5) : 0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Text(
              'Değerlendirmeler',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),

          // Summary bar
          if (avg != null) ...[
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    avg.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: _starColor,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${'★' * filled}${'☆' * (5 - filled)}',
                        style: const TextStyle(
                            color: _starColor,
                            fontSize: 20,
                            letterSpacing: 2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$count değerlendirme',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          Divider(height: 1, color: AppColors.divider(context)),

          // Ratings list
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: kPrimary))
                : (_ratings == null || _ratings!.isEmpty)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Henüz değerlendirme yok',
                            style: TextStyle(
                                color: AppColors.textTertiary(context)),
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        itemCount: _ratings!.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: AppColors.divider(context)),
                        itemBuilder: (_, i) {
                          final r =
                              _ratings![i] as Map<String, dynamic>;
                          final rater =
                              r['rater'] as Map<String, dynamic>;
                          final raterName =
                              (rater['full_name'] as String?) ??
                                  (rater['username'] as String?) ??
                                  '?';
                          final raterInitial = raterName.isNotEmpty
                              ? raterName[0].toUpperCase()
                              : '?';
                          final imgUrl =
                              rater['profile_image_url'] as String?;
                          final score = r['score'] as int;
                          final comment = r['comment'] as String?;
                          final date = (r['updated_at'] as String?) ??
                              (r['created_at'] as String?);

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // Rater avatar
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      kPrimary.withOpacity(0.12),
                                  backgroundImage: imgUrl != null
                                      ? NetworkImage(imgUrl)
                                      : null,
                                  child: imgUrl == null
                                      ? Text(
                                          raterInitial,
                                          style: const TextStyle(
                                            color: kPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              raterName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '${'★' * score}${'☆' * (5 - score)}',
                                            style: const TextStyle(
                                                color: _starColor,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      if (comment != null &&
                                          comment.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          comment,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary(
                                                context),
                                          ),
                                        ),
                                      ],
                                      if (date != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatDate(date),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textTertiary(
                                                context),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
