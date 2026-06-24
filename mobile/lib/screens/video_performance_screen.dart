import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class VideoPerformanceScreen extends StatefulWidget {
  final bool isPremium;
  const VideoPerformanceScreen({super.key, required this.isPremium});

  @override
  State<VideoPerformanceScreen> createState() => _VideoPerformanceScreenState();
}

class _VideoPerformanceScreenState extends State<VideoPerformanceScreen> {
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
    final data = await AnalyticsService.getVideoPerformance(days: _days);
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
        title: const Text('Video Performansı'),
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
                        color: active ? const Color(0xFFEF4444) : AppColors.card(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? const Color(0xFFEF4444) : AppColors.border(context)),
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
              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
            ),
            child: const Text(
              '🎬 İlan detay sayfasındaki videonuzu kullanıcıların ne kadarını izlediğini gösterir. '
              '%80+ tamamlanma oranı çok güçlü bir satın alma sinyalidir.',
              style: TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
            ),
          ),

          if (stats.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    Icon(Icons.videocam_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz video izleme verisi yok.\nKullanıcılar video ilanlarınızı açtıkça bu kısım dolacak.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Video Tamamlanma Oranları',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
            ),
            const SizedBox(height: 10),
            ...stats.map((s) => _VideoStatCard(stat: s)),
          ],
        ],
      ),
    );
  }
}

class _VideoStatCard extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _VideoStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final avgPct = (stat['avg_completion_pct'] as num?)?.toDouble() ?? 0;
    final fullRate = (stat['full_watch_rate_pct'] as num?)?.toDouble() ?? 0;
    final plays = stat['play_count'] as int? ?? 0;

    Color barColor;
    if (avgPct >= 70) barColor = const Color(0xFF22C55E);
    else if (avgPct >= 40) barColor = const Color(0xFFF59E0B);
    else barColor = const Color(0xFFEF4444);

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
                '$plays oynatma',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(label: 'Ort. Tamamlanma', value: '%${avgPct.toStringAsFixed(1)}', color: barColor),
              const SizedBox(width: 8),
              _StatChip(label: 'Tam İzleme (%80+)', value: '%${fullRate.toStringAsFixed(1)}', color: const Color(0xFF8B5CF6)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (avgPct / 100).clamp(0.0, 1.0),
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
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
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 9, color: AppColors.textSecondary(context))),
        ],
      ),
    );
  }
}
