import 'package:flutter/material.dart';
import '../../config/api.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../public_profile_screen.dart';
import 'host_stream_screen.dart';
import 'swipe_live_screen.dart';

class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});

  @override
  State<LiveListScreen> createState() => LiveListScreenState();
}

class LiveListScreenState extends State<LiveListScreen> {
  List<StreamOut> _streams = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void triggerStartDialog() => _showStartDialog();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final streams = await StreamService.getActiveStreams();
      if (!mounted) return;
      setState(() {
        _streams = streams;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showStartDialog() async {
    final categories = await CategoryService.getCategories();
    final token = await StorageService.getToken();
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yayın başlatmak için giriş yapmalısınız')),
      );
      return;
    }

    final titleController = TextEditingController();
    String? selectedCategory;
    String? errorText;

    final result = await showDialog<(String, String)?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Yayın Başlat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: 'Yayın başlığı',
                  labelText: 'Başlık *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Kategori *',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Kategori seç'),
                items: categories
                    .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
                    .toList(),
                onChanged: (v) => setStateDialog(() => selectedCategory = v),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () {
                final t = titleController.text.trim();
                if (t.isEmpty) {
                  setStateDialog(() => errorText = 'Yayın başlığı zorunludur');
                  return;
                }
                if (selectedCategory == null) {
                  setStateDialog(() => errorText = 'Kategori seçimi zorunludur');
                  return;
                }
                Navigator.pop(ctx, (t, selectedCategory!));
              },
              child: const Text('Başlat', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final (title, category) = result;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final streamToken = await StreamService.startStream(title, category);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HostStreamScreen(streamToken: streamToken, title: title),
        ),
      ).then((_) => _load());
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Yayın başlatılamadı')),
      );
    }
  }

  Future<void> _joinStream(StreamOut stream) async {
    if (!mounted) return;
    final idx = _streams.indexOf(stream);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SwipeLiveScreen(streams: _streams, initialIndex: idx),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Canlı Yayınlar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: const [],
      ),
      body: RefreshIndicator(
        color: kPrimary,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : _error != null
                ? Center(child: Text(_error!))
                : _streams.isEmpty
                    ? const _EmptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _streams.length,
                        itemBuilder: (_, i) => _StreamGridTile(
                          stream: _streams[i],
                          onTap: () => _joinStream(_streams[i]),
                        ),
                      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Column(
          children: [
            Icon(Icons.videocam_off_outlined, size: 56, color: Color(0xFFD1D5DB)),
            SizedBox(height: 12),
            Text(
              'Şu an aktif yayın yok',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
            ),
            SizedBox(height: 4),
            Text(
              'İlk yayını sen başlat!',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ],
    );
  }
}

class _StreamGridTile extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamGridTile({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = stream.thumbnailUrl != null && stream.thumbnailUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square thumbnail area
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Background
                  if (hasThumbnail)
                    Image.network(
                      imgUrl(stream.thumbnailUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _gradientBox(),
                    )
                  else
                    _gradientBox(),
                  // CANLI badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'CANLI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  // Viewer badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '👁 ${stream.viewerCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info section
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stream.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${stream.host.username}',
                    style: const TextStyle(
                      color: kPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientBox() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryDark, kPrimaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.videocam_rounded, color: Colors.white30, size: 36),
      ),
    );
  }

}
