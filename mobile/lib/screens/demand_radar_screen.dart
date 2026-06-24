import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/analytics_service.dart';

class DemandRadarScreen extends StatefulWidget {
  final bool isPremium;
  const DemandRadarScreen({super.key, required this.isPremium});

  @override
  State<DemandRadarScreen> createState() => _DemandRadarScreenState();
}

class _DemandRadarScreenState extends State<DemandRadarScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final data = await AnalyticsService.getDemandRadar(days: _days);
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
        title: const Text('Talep Radar'),
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
    final topQueries = (_data?['top_queries'] as List? ?? []).cast<Map<String, dynamic>>();
    final byCategory = (_data?['by_category'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [7, 30].map((d) {
              final active = _days == d;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: d == 7 ? 6 : 0, left: d == 30 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () { if (_days != d) { setState(() => _days = d); _load(); } },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFF59E0B) : AppColors.card(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? const Color(0xFFF59E0B) : AppColors.border(context)),
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
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
            ),
            child: const Text(
              '🔍 Platform genelinde kullanıcıların en çok aradığı ürünler. '
              'Bu talepler için ilan açarak satışlarınızı artırın.',
              style: TextStyle(fontSize: 12, color: Color(0xFFF59E0B), fontWeight: FontWeight.w500),
            ),
          ),

          if (topQueries.isEmpty && byCategory.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Column(
                  children: [
                    Icon(Icons.search_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz arama verisi yok.\nKullanıcılar arama yaptıkça bu kısım dolacak.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (topQueries.isNotEmpty) ...[
              Text(
                '🔥 En Çok Aranan',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: topQueries.asMap().entries.map((e) {
                    final q = e.value;
                    final rank = e.key + 1;
                    final isLast = e.key == topQueries.length - 1;
                    final maxCount = (topQueries.first['count'] as int? ?? 1);
                    final count = q['count'] as int? ?? 0;
                    final fill = maxCount > 0 ? count / maxCount : 0.0;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                child: Text(
                                  rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '$rank.',
                                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary(context)),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      q['query'] as String? ?? '—',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(3),
                                      child: LinearProgressIndicator(
                                        value: fill,
                                        backgroundColor: AppColors.border(context),
                                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast) const Divider(height: 1),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (byCategory.isNotEmpty) ...[
              Text(
                '📂 Kategori Bazlı Arama',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary(context)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: byCategory.map((c) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.card(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c['category'] as String? ?? 'diğer',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary(context)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${c['count']}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
