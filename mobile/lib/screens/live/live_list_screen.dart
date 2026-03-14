import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/stream.dart';
import '../../services/storage_service.dart';
import '../../services/stream_service.dart';
import '../../services/auth_service.dart';
import 'host_stream_screen.dart';
import 'viewer_stream_screen.dart';

class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});

  @override
  State<LiveListScreen> createState() => _LiveListScreenState();
}

class _LiveListScreenState extends State<LiveListScreen> {
  List<StreamOut> _streams = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

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

  static const _categories = [
    ('elektronik', '📱 Elektronik'),
    ('giyim', '👗 Giyim'),
    ('ev', '🛋 Ev & Bahçe'),
    ('vasita', '🚗 Vasıta'),
    ('spor', '⚽ Spor'),
    ('kitap', '📚 Kitap & Müzik'),
    ('diger', '📦 Diğer'),
  ];

  Future<void> _showStartDialog() async {
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
                items: _categories
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final joinData = await StreamService.joinStream(stream.id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewerStreamScreen(joinToken: joinData),
        ),
      ).then((_) => _load());
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Yayına katılınamadı')),
      );
    }
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
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.videocam_outlined, color: kPrimary),
            label: const Text(
              'Yayın Başlat',
              style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600),
            ),
            onPressed: _showStartDialog,
          ),
        ],
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
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _streams.length,
                        itemBuilder: (_, i) => _StreamCard(
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

class _StreamCard extends StatelessWidget {
  final StreamOut stream;
  final VoidCallback onTap;

  const _StreamCard({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPrimaryDark, kPrimaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(Icons.videocam, color: Colors.white38, size: 28),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'CANLI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stream.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${stream.host.username}',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.visibility_outlined,
                            size: 14, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Text(
                          '${stream.viewerCount} izleyici',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB)),
            ],
          ),
        ),
      ),
    );
  }
}
