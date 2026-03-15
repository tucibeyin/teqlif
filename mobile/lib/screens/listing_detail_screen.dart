import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../services/storage_service.dart';
import 'public_profile_screen.dart';
import 'messages_screen.dart';

// teqlif.com/api → teqlif.com
const String _kBaseHost = 'https://teqlif.com';

String _imgUrl(String path) {
  if (path.startsWith('http')) return path;
  return '$_kBaseHost$path';
}

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

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    final imgs = widget.listing['image_urls'] as List? ?? [];
    _images = imgs.cast<String>().map(_imgUrl).toList();
    if (_images.isEmpty && widget.listing['image_url'] != null) {
      _images.add(_imgUrl(widget.listing['image_url'] as String));
    }
    _loadMyId();
  }

  Future<void> _loadMyId() async {
    final info = await StorageService.getUserInfo();
    if (mounted) setState(() => _myUserId = info?['id'] as int?);
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

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final user = listing['user'] as Map<String, dynamic>?;
    final isMine = _myUserId != null && user?['id'] == _myUserId;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Text(
          listing['title'] ?? '',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGallery(),

            // Başlık & Fiyat
            Container(
              color: Colors.white,
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
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          listing['location'],
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
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
                color: Colors.white,
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Açıklama',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      listing['description'],
                      style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF444444),
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // İlan Bilgileri
            Container(
              color: Colors.white,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('İlan Bilgileri',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
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
                  color: Colors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: kPrimaryBg,
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
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.grey, size: 20),
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
      return Container(
        height: 260,
        color: const Color(0xFFF3F4F6),
        child: const Center(
          child: Icon(Icons.image_outlined,
              size: 64, color: Color(0xFFD1D5DB)),
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
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        color: const Color(0xFFF3F4F6),
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFFF3F4F6),
                  child: const Icon(Icons.broken_image_outlined,
                      size: 48, color: Color(0xFFD1D5DB)),
                ),
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

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ],
        ),
      );

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
