import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import 'profile_screen.dart';
import 'public_profile_screen.dart';
import 'messages_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> listing;
  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  int _currentImg = 0;
  late final PageController _pageCtrl;
  late final List<String> _images;
  int? _myUserId;
  bool _isFavorited = false;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    final imgs = widget.listing['image_urls'] as List? ?? [];
    _images = imgs.cast<String>().map(imgUrl).toList();
    if (_images.isEmpty && widget.listing['image_url'] != null) {
      _images.add(imgUrl(widget.listing['image_url'] as String));
    }
    _isActive = widget.listing['is_active'] as bool? ?? true;
    _loadMyId();
  }

  Future<void> _loadMyId() async {
    final info = await StorageService.getUserInfo();
    final token = await StorageService.getToken();
    if (!mounted) return;
    setState(() => _myUserId = info?['id'] as int?);
    if (token != null && _myUserId != null) {
      final listingUserId = (widget.listing['user'] as Map?)?['id'];
      if (listingUserId != _myUserId) {
        _loadFavoriteStatus(token);
      }
    }
  }

  Future<void> _loadFavoriteStatus(String token) async {
    final id = widget.listing['id'];
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/favorites/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        setState(() => _isFavorited = data['is_favorited'] as bool? ?? false);
      }
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      if (_isFavorited) {
        await http.delete(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) setState(() => _isFavorited = false);
      } else {
        await http.post(
          Uri.parse('$kBaseUrl/favorites/$id'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (mounted) setState(() => _isFavorited = true);
      }
    } catch (_) {}
  }

  Future<void> _toggleActive() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.patch(
        Uri.parse('$kBaseUrl/listings/$id/toggle'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final newActive = data['is_active'] as bool? ?? !_isActive;
        setState(() => _isActive = newActive);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newActive ? 'İlan aktif yapıldı' : 'İlan pasife alındı')),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _fmt(dynamic price) {
    if (price == null) return 'Fiyat Belirtilmemiş';
    final s = (price as num).toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} ₺';
  }

  void _goToProfile() {
    final user = widget.listing['user'] as Map<String, dynamic>?;
    if (user == null) return;
    // Kendi ilanıysa kendi profil ekranına git (loop'u önle)
    if (_myUserId != null && user['id'] == _myUserId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          username: user['username'] as String,
          userId: user['id'] as int?,
        ),
      ),
    );
  }

  void _openChat() async {
    final user = widget.listing['user'] as Map<String, dynamic>?;
    if (user == null) return;
    final otherId = user['id'] as int?;
    if (otherId == null) return;

    if (_myUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj göndermek için giriş yapmalısınız')),
      );
      return;
    }
    if (_myUserId == otherId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi ilanınıza mesaj gönderemezsiniz')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DirectChatScreen(
          otherUserId: otherId,
          displayName: user['full_name'] as String? ??
              user['username'] as String? ?? '',
          otherHandle: user['username'] as String? ?? '',
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('İlanı Sil'),
        content: const Text('Bu ilanı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteListing(context);
            },
            child: const Text('Evet, Sil', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteListing(BuildContext context) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/listings/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context, true);
      } else {
        final detail = jsonDecode(resp.body)['detail'] ?? 'Bir hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası')),
        );
      }
    }
  }

  void _openReport(BuildContext context) {
    String? selectedReason;
    final noteCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🚩 İlanı Şikayet Et',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedReason,
                hint: const Text('Neden seçin'),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: 'Yanıltıcı ilan', child: Text('Yanıltıcı ilan')),
                  DropdownMenuItem(value: 'Yasadışı ürün', child: Text('Yasadışı ürün')),
                  DropdownMenuItem(value: 'Spam / tekrar ilan', child: Text('Spam / tekrar ilan')),
                  DropdownMenuItem(value: 'Uygunsuz içerik', child: Text('Uygunsuz içerik')),
                  DropdownMenuItem(value: 'Dolandırıcılık şüphesi', child: Text('Dolandırıcılık şüphesi')),
                  DropdownMenuItem(value: 'Diğer', child: Text('Diğer')),
                ],
                onChanged: (v) => setModalState(() => selectedReason = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Ek açıklama (isteğe bağlı)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    if (selectedReason == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Lütfen bir neden seçin')),
                      );
                      return;
                    }
                    final note = noteCtrl.text.trim();
                    final reason = selectedReason! + (note.isNotEmpty ? ': $note' : '');
                    Navigator.pop(ctx);
                    await _submitReport(reason);
                  },
                  child: const Text('Şikayeti Gönder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    final token = await StorageService.getToken();
    if (token == null) return;
    final id = widget.listing['id'];
    try {
      final resp = await http.post(
        Uri.parse('$kBaseUrl/reports'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'listing_id': id, 'reason': reason}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şikayetiniz alındı. Teşekkür ederiz.')),
        );
      } else {
        final detail = jsonDecode(resp.body)['detail'] ?? 'Bir hata oluştu';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final user = listing['user'] as Map<String, dynamic>?;
    final isMine = _myUserId != null && user?['id'] == _myUserId;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        title: Text(
          listing['title'] ?? '',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isMine) ...[
            IconButton(
              icon: Icon(
                _isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: _isActive ? const Color(0xFF6B7280) : kPrimary,
              ),
              tooltip: _isActive ? 'Pasife Al' : 'Aktif Yap',
              onPressed: _toggleActive,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
              tooltip: 'İlanı Sil',
              onPressed: () => _confirmDelete(context),
            ),
          ] else if (_myUserId != null) ...[
            IconButton(
              icon: Icon(
                _isFavorited ? Icons.favorite : Icons.favorite_border,
                color: _isFavorited ? Colors.red : const Color(0xFF9CA3AF),
              ),
              tooltip: _isFavorited ? 'Favoriden Çıkar' : 'Favorile',
              onPressed: _toggleFavorite,
            ),
            IconButton(
              icon: const Icon(Icons.flag_outlined, color: Color(0xFF9CA3AF), size: 22),
              tooltip: 'Şikayet Et',
              onPressed: () => _openReport(context),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGallery(),

            // Başlık & Fiyat
            Container(
              color: AppColors.surface(context),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing['title'] ?? '',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fmt(listing['price']),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: kPrimary,
                    ),
                  ),
                  if (listing['location'] != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.textSecondary(context)),
                        const SizedBox(width: 4),
                        Text(
                          listing['location'],
                          style: TextStyle(
                              color: AppColors.textSecondary(context), fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Açıklama
            if (listing['description'] != null &&
                (listing['description'] as String).isNotEmpty)
              Container(
                color: AppColors.surface(context),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Açıklama',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context))),
                    const SizedBox(height: 8),
                    Text(
                      listing['description'],
                      style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary(context),
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // İlan Bilgileri
            Container(
              color: AppColors.surface(context),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('İlan Bilgileri',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(context))),
                  const SizedBox(height: 12),
                  _infoRow('Kategori', listing['category'] ?? '-'),
                  if (listing['location'] != null)
                    _infoRow('Konum', listing['location']),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Satıcı — tıklanabilir
            if (user != null)
              InkWell(
                onTap: _goToProfile,
                child: Container(
                  color: AppColors.surface(context),
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.primaryBg(context),
                        child: Text(
                          ((user['full_name'] as String?) ??
                                  (user['username'] as String?) ??
                                  '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['full_name'] ?? user['username'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              '@${user['username'] ?? ''}',
                              style: TextStyle(
                                  color: AppColors.textSecondary(context), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: AppColors.textSecondary(context), size: 20),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 90),
          ],
        ),
      ),
      bottomNavigationBar: isMine
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: const Text('Satıcıya Mesaj Gönder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildGallery() {
    if (_images.isEmpty) {
      return Builder(
        builder: (context) => Container(
          height: 260,
          color: AppColors.surfaceVariant(context),
          child: Center(
            child: Icon(Icons.image_outlined,
                size: 64, color: AppColors.border(context)),
          ),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _images.length,
            onPageChanged: (i) => setState(() => _currentImg = i),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _openFullscreen(i),
              child: Image.network(
                _images[i],
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (ctx, child, progress) => progress == null
                    ? child
                    : Container(
                        color: AppColors.surfaceVariant(ctx),
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (ctx, err, stack) {
                  debugPrint('IMG HATA [${_images[i]}]: $err');
                  return Container(
                    color: AppColors.surfaceVariant(ctx),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined,
                            size: 48, color: AppColors.border(ctx)),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _images[i],
                            style: TextStyle(
                                fontSize: 9, color: AppColors.textTertiary(ctx)),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_images.length > 1 && _currentImg > 0)
          Positioned(
            left: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_left, -1)),
          ),
        if (_images.length > 1 && _currentImg < _images.length - 1)
          Positioned(
            right: 8, top: 0, bottom: 0,
            child: Center(child: _arrowBtn(Icons.chevron_right, 1)),
          ),
        if (_images.length > 1)
          Positioned(
            bottom: 10, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_currentImg + 1}/${_images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _arrowBtn(IconData icon, int dir) => GestureDetector(
        onTap: () => _pageCtrl.animateToPage(
          _currentImg + dir,
          duration: const Duration(milliseconds: 250),
          curve: Curves.ease,
        ),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.black45,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _infoRow(String label, String value) => Builder(
        builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13,
                      color: AppColors.textPrimary(context))),
            ),
          ],
        ),
      ));

  void _openFullscreen(int startIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _FullscreenGallery(images: _images, initial: startIndex),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initial;
  const _FullscreenGallery({required this.images, required this.initial});

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current;
  late final PageController _ctrl;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _ctrl = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.images[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
