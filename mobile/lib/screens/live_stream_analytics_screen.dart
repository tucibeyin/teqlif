import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';

class LiveStreamAnalyticsScreen extends StatefulWidget {
  final int streamId;
  const LiveStreamAnalyticsScreen({super.key, required this.streamId});

  @override
  State<LiveStreamAnalyticsScreen> createState() => _LiveStreamAnalyticsScreenState();
}

class _LiveStreamAnalyticsScreenState extends State<LiveStreamAnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/analytics/seller-report/${widget.streamId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          setState(() {
            _data = jsonDecode(resp.body) as Map<String, dynamic>;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proToolStreamAnalyticsTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_outlined, size: 48, color: AppColors.textSecondary(context)),
                      const SizedBox(height: 16),
                      Text(l.proLoadError, style: TextStyle(color: AppColors.textSecondary(context))),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _fetchAnalytics, child: Text(l.btnRetry)),
                    ],
                  ),
                )
              : _buildDashboard(context),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final d = _data!;
    final revenue = d['auction_summary']?['total_revenue'] ?? 0.0;
    final recommendation = d['recommendation'] as String? ?? '';
    final duration = d['duration_minutes'] as int? ?? 0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Revenue Card (Gradient & Glassmorphism)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1E293B).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(l.analyticsRevenue.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text(
                        '${revenue.toStringAsFixed(2)} TUCi',
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(l.analyticsDuration(duration), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Recommendation Alert
                if (recommendation.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.tips_and_updates, color: Color(0xFFD97706), size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.analyticsAiRecommendation, style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(recommendation, style: const TextStyle(color: Color(0xFFB45309), fontSize: 13, height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Audience Quality Grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _MetricCard(title: l.analyticsUniqueViewers, value: '${d['unique_viewers'] ?? 0}', icon: Icons.people_alt, color: Colors.blue),
                    _MetricCard(title: l.analyticsPeakViewers, value: '${d['peak_viewers'] ?? 0}', icon: Icons.show_chart, color: Colors.purple),
                    _MetricCard(title: l.analyticsAvgBudget, value: d['avg_budget'] != null ? '${d['avg_budget']} ₺' : '-', icon: Icons.account_balance_wallet, color: Colors.green),
                    _MetricCard(title: l.analyticsHesitation, value: '${d['hesitation_count'] ?? 0}', icon: Icons.psychology_alt, color: Colors.orange),
                  ],
                ),

                const SizedBox(height: 24),

                // Reach Section
                Text(l.analyticsFeedReach, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _ReachStat(title: l.analyticsFeedImpressions, value: '${d['swipe_impressions'] ?? 0}', icon: Icons.swipe)),
                    const SizedBox(width: 12),
                    Expanded(child: _ReachStat(title: l.analyticsFeedReach, value: '${d['swipe_reach'] ?? 0}', icon: Icons.radar)),
                  ],
                ),
                
                const SizedBox(height: 32),
                Text(l.analyticsItemsSold, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
        ),
        _buildAuctionList(l, d['auction_summary']?['items'] as List? ?? []),
      ],
    );
  }

  Widget _buildAuctionList(AppLocalizations l, List items) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 32.0),
          child: Center(
            child: Text(l.analyticsNoAuctions, style: TextStyle(color: AppColors.textSecondary(context))),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          final sold = item['sold'] == true;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: sold ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(sold ? Icons.check : Icons.close, color: sold ? Colors.green : Colors.red, size: 20),
              ),
              title: Text(item['item_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(sold ? '${item['winner_username']} (${item['bid_count']} bids)' : 'Unsold'),
              trailing: Text('${item['final_price'] ?? item['start_price']} TUCi', style: TextStyle(fontWeight: FontWeight.bold, color: sold ? Colors.green : AppColors.textSecondary(context))),
            ),
          );
        },
        childCount: items.length,
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _MetricCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context), fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color.shade700)),
        ],
      ),
    );
  }
}

class _ReachStat extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _ReachStat({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}
