import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';

// ── Provider ─────────────────────────────────────────────────────────────────
final auctionHistoryProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ApiClient().get('/api/profile/auctions');
  return res.data as Map<String, dynamic>;
});

// ── Screen ───────────────────────────────────────────────────────────────────
class AuctionHistoryScreen extends ConsumerStatefulWidget {
  const AuctionHistoryScreen({super.key});

  @override
  ConsumerState<AuctionHistoryScreen> createState() => _AuctionHistoryScreenState();
}

class _AuctionHistoryScreenState extends ConsumerState<AuctionHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _openChat(String counterpartyId, String adId) async {
    try {
      final res = await ApiClient().post('/api/conversations', data: {
        'userId': counterpartyId,
        'adId': adId,
      });
      final conversationId = (res.data as Map<String, dynamic>)['id'] as String?;
      if (conversationId != null && mounted) {
        context.push('/messages/$conversationId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konuşma başlatılamadı.')),
        );
      }
    }
  }

  // ── Card ─────────────────────────────────────────────────────────────────
  Widget _buildCard({
    required Map<String, dynamic> ad,
    required String counterpartyName,
    required String counterpartyId,
    required String roleLabel,
    required double finalPrice,
  }) {
    final title = ad['title'] as String? ?? 'İlan';
    final images = (ad['images'] as List<dynamic>?) ?? [];
    final adId = ad['id'] as String? ?? '';
    final thumb = images.isNotEmpty ? imageUrl(images.first.toString()) : null;
    final fmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: thumb != null
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  // Final price badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10b981), Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      fmt.format(finalPrice),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 6),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                      children: [
                        TextSpan(
                          text: '$roleLabel: ',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                        ),
                        TextSpan(text: counterpartyName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Message button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: counterpartyId.isEmpty ? null : () => _openChat(counterpartyId, adId),
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: Text(
                        roleLabel == 'Satıcı' ? 'Satıcıyla İletişime Geç' : 'Alıcıya Mesaj At',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B4CC),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 76, height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(child: Text('🏷️', style: TextStyle(fontSize: 28))),
    );
  }

  Widget _emptyState(String emoji, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 64),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(text, style: const TextStyle(color: Color(0xFF9AAAB8), fontSize: 15)),
          ],
        ),
      ),
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────
  Widget _buildTabContent(Map<String, dynamic> data, bool isWon) {
    final list = (data[isWon ? 'won' : 'sold'] as List<dynamic>?) ?? [];

    if (list.isEmpty) {
      return _emptyState(
        isWon ? '🏅' : '💰',
        isWon ? 'Henüz kazandığınız bir müzayede yok.' : 'Henüz sattığınız bir müzayede yok.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final ad = list[i] as Map<String, dynamic>;
        if (isWon) {
          final seller = ad['user'] as Map<String, dynamic>? ?? {};
          final bids = (ad['bids'] as List<dynamic>?) ?? [];
          final price = bids.isNotEmpty
              ? (double.tryParse(bids.first['amount'].toString()) ?? 0.0)
              : 0.0;
          return _buildCard(
            ad: ad,
            counterpartyName: seller['name'] as String? ?? 'Satıcı',
            counterpartyId: seller['id'] as String? ?? '',
            roleLabel: 'Satıcı',
            finalPrice: price,
          );
        } else {
          final bids = (ad['bids'] as List<dynamic>?) ?? [];
          final bid = bids.isNotEmpty ? bids.first as Map<String, dynamic> : {};
          final buyer = bid['user'] as Map<String, dynamic>? ?? {};
          final price = double.tryParse(bid['amount']?.toString() ?? '0') ?? 0.0;
          return _buildCard(
            ad: ad,
            counterpartyName: buyer['name'] as String? ?? 'Alıcı',
            counterpartyId: buyer['id'] as String? ?? '',
            roleLabel: 'Alıcı',
            finalPrice: price,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(auctionHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: AppBar(
        title: const Text('Müzayede Geçmişim'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          labelColor: const Color(0xFF00B4CC),
          unselectedLabelColor: const Color(0xFF9AAAB8),
          indicatorColor: const Color(0xFF00B4CC),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '🏅 Kazandıklarım'),
            Tab(text: '💰 Sattıklarım'),
          ],
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF00B4CC))),
        error: (e, _) => Center(child: Text('Hata: $e', style: const TextStyle(color: Colors.red))),
        data: (data) => TabBarView(
          controller: _tab,
          children: [
            _buildTabContent(data, true),
            _buildTabContent(data, false),
          ],
        ),
      ),
    );
  }
}
