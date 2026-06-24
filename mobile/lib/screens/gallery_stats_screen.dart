import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class GalleryStatsScreen extends StatefulWidget {
  final bool isPremium;
  const GalleryStatsScreen({super.key, required this.isPremium});

  @override
  State<GalleryStatsScreen> createState() => _GalleryStatsScreenState();
}

class _GalleryStatsScreenState extends State<GalleryStatsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final data = await AnalyticsService.getGalleryStats(days: _days);
    if (!mounted) return;
    if (data == null) {
      setState(() { _loading = false; _error = 'Veri yüklenemedi.'; });
    } else {
      setState(() { _loading = false; _data = data; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Galeri Analizi'),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final stats = (_data?['stats'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [30, 7].map((d) {
              final active = _days == d;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 30 ? 6 : 0, left: d == 7 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () { if (_days != d) { setState(() => _days = d); _load(); } },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFEC4899) : AppColors.card(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? const Color(0xFFEC4899) : AppColors.border(context)),
                      ),
                      child: Text(
                        'Son $d Gün',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: active ? Colors.white : AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEC4899).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.2)),
            ),
            child: const Text(
              '📸 İlan galerisinde kullanıcıların kaç fotoğrafa kadar ilerlediğini gösterir. '
              'Yüksek ortalama derinlik = güçlü ilgi sinyali.',
              style: TextStyle(fontSize: 12, color: Color(0xFFEC4899), fontWeight: FontWeight.w500),
            ),
          ),

          if (stats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    Icon(Icons.photo_library_outlined, size: 48, color: AppColors.textSecondary(context)),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz galeri verisi yok.\nKullanıcılar ilan fotoğraflarına baktıkça bu kısım dolacak.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'İlan Bazlı Galeri Derinliği',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 10),
            ...stats.map((s) => _GalleryStatCard(stat: s)),
          ],
        ],
      ),
    );
  }
}

class _GalleryStatCard extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _GalleryStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final avgDepth = (stat['avg_swipe_depth'] as num?)?.toDouble() ?? 0;
    final maxDepth = stat['max_swipe_depth'] as int? ?? 0;
    final views = stat['views'] as int? ?? 0;
    final fill = maxDepth > 0 ? (avgDepth / maxDepth).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat['title'] as String? ?? '—',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$views görüntüleme',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(label: 'Ort. Derinlik', value: '${avgDepth.toStringAsFixed(1)} foto'),
              const SizedBox(width: 8),
              _StatChip(label: 'Maks. Derinlik', value: '$maxDepth foto'),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill,
              backgroundColor: AppColors.border(context),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFEC4899)),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEC4899).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFEC4899))),
          Text(label, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}
