import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/price_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'purchase_detail_screen.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _purchases = [];

  @override
  void initState() {
    super.initState();
    _loadPurchases();
  }

  Future<void> _loadPurchases() async {
    try {
      final purchases = await AuthService.getMyPurchases();
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _loading = false;
        });
      }
    } catch (e, st) {
      log('Error loading purchases: $e', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.purchaseLoadError),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.settingsMyPurchases),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _purchases.isEmpty
              ? Center(
                  child: Text(
                    l.purchaseEmptyState,
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  color: kPrimary,
                  onRefresh: _loadPurchases,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _purchases.length,
                    itemBuilder: (context, index) {
                      final item = _purchases[index];
                      final itemName = item['item_name'] as String? ?? l.purchaseUnknownItem;
                      final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
                      final seller = item['seller_username'] as String? ?? l.purchaseUnknownSeller;
                      final category = item['category'] as String?;
                      final thumbnailUrl = item['thumbnail_url'] as String? ?? item['image_url'] as String?;
                      final isBuyItNow = (item['is_bought_it_now'] as bool?) ?? false;
                      final endedAt = item['ended_at'] as String?;

                      return Card(
                        color: AppColors.card(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PurchaseDetailScreen(purchase: item),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: imgUrl(thumbnailUrl),
                                memCacheWidth: 600,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) => _placeholderBox(),
                                          placeholder: (_, _) => _placeholderBox(),
                                        )
                                      : _placeholderBox(),
                                ),
                                const SizedBox(width: 12),
                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemName,
                                        style: TextStyle(
                                          color: AppColors.textPrimary(context),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '@$seller',
                                        style: TextStyle(
                                          color: AppColors.textSecondary(context),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (category != null) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: kPrimary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                category,
                                                style: const TextStyle(color: kPrimary, fontSize: 11),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isBuyItNow
                                                  ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                                                  : const Color(0xFFF97316).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isBuyItNow ? 'Hemen Al' : 'Teklif',
                                              style: TextStyle(
                                                color: isBuyItNow
                                                    ? const Color(0xFF16A34A)
                                                    : const Color(0xFFF97316),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (endedAt != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatDate(endedAt),
                                          style: TextStyle(
                                            color: AppColors.textTertiary(context),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Price + chevron
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      fmtPrice(price),
                                      style: const TextStyle(
                                        color: Color(0xFF4ADE80),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Icon(Icons.chevron_right, color: AppColors.iconSecondary(context)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.card(context).withValues(alpha: 0.5),
      child: Icon(Icons.shopping_bag_outlined, color: AppColors.iconSecondary(context), size: 32),
    );
  }
}
