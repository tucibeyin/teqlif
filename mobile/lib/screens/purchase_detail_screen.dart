import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/price_formatter.dart';
import 'listing_detail_screen.dart';
import 'public_profile_screen.dart';
import '../../services/listing_service.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'messages_screen.dart';

class PurchaseDetailScreen extends StatelessWidget {
  final Map<String, dynamic> purchase;

  const PurchaseDetailScreen({super.key, required this.purchase});

  String _formatDate(String? iso) {
    if (iso == null) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemName = purchase['item_name'] as String? ?? l.purchaseUnknownItem;
    final sellerUsername = purchase['seller_username'] as String? ?? l.purchaseUnknownSeller;
    final sellerId = purchase['seller_id'] as int?;
    final finalPrice = (purchase['final_price'] as num?)?.toDouble() ?? 0.0;
    final startPrice = (purchase['start_price'] as num?)?.toDouble();
    final bidCount = purchase['bid_count'] as int?;
    final isBuyItNow = (purchase['is_bought_it_now'] as bool?) ?? false;
    final startedAt = purchase['started_at'] as String?;
    final endedAt = purchase['ended_at'] as String?;
    final category = purchase['category'] as String?;
    final listingId = purchase['listing_id'] as int?;
    final proofImageUrl = purchase['proof_image_url'] as String?;
    final thumbnailUrl = purchase['thumbnail_url'] as String? ?? purchase['image_url'] as String?;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.purchaseDetailTitle),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image section
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imgUrl(thumbnailUrl),
                                memCacheWidth: 600,
                  height: 220,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _imagePlaceholder(),
                  placeholder: (_, _) => _imagePlaceholder(),
                ),
              )
            else
              _imagePlaceholder(),

            const SizedBox(height: 16),

            // Item details card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (category != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(category, style: const TextStyle(color: kPrimary, fontSize: 12)),
                    ),
                  Text(
                    '${l.purchaseSeller}: @$sellerUsername',
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15),
                  ),
                  const Divider(height: 24),
                  _infoRow(context, 'Satış Fiyatı', fmtPrice(finalPrice), valueColor: const Color(0xFF4ADE80)),
                  if (startPrice != null)
                    _infoRow(context, 'Başlangıç Fiyatı', fmtPrice(startPrice)),
                  _infoRow(
                    context,
                    'Satış Türü',
                    isBuyItNow ? 'Hemen Al' : 'Açık Artırma',
                    valueColor: isBuyItNow
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFF97316),
                  ),
                  if (!isBuyItNow && bidCount != null)
                    _infoRow(context, 'Teklif Sayısı', '$bidCount'),
                  if (startedAt != null)
                    _infoRow(context, 'Başlangıç', _formatDate(startedAt)),
                  if (endedAt != null)
                    _infoRow(context, 'Bitiş', _formatDate(endedAt)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Satıcı Profiline Git
            ElevatedButton.icon(
              icon: const Icon(Icons.person, color: Colors.white),
              label: Text(l.purchaseViewSeller, style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(username: sellerUsername)),
                );
              },
            ),
            const SizedBox(height: 10),

            // Satıcıya Mesaj Gönder
            if (sellerId != null)
              ElevatedButton.icon(
                icon: const Icon(Icons.message_rounded, color: Colors.white),
                label: const Text('Satıcıya Mesaj Gönder', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6B21A8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DirectChatScreen(
                        otherUserId: sellerId,
                        displayName: sellerUsername,
                        otherHandle: sellerUsername,
                        listingId: listingId,
                        contextPurchase: purchase,
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 10),

            // İlanı Görüntüle
            if (listingId != null)
              OutlinedButton.icon(
                icon: Icon(Icons.article, color: AppColors.textSecondary(context)),
                label: Text(l.purchaseViewListing, style: TextStyle(color: AppColors.textPrimary(context))),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.border(context)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );
                  final listing = await ListingService.getListingById(listingId);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (listing != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: listing)),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.purchaseListingNotFound)),
                    );
                  }
                },
              ),

            const SizedBox(height: 24),

            // Satış Kanıt Görseli
            if (proofImageUrl != null && proofImageUrl.isNotEmpty) ...[
              Text(
                l.purchaseProofImage,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imgUrl(proofImageUrl),
                                memCacheWidth: 600,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    height: 200,
                    color: Colors.black26,
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 50)),
                  ),
                  placeholder: (_, _) => Container(
                    height: 200,
                    color: Colors.black12,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.shopping_bag_outlined, color: Colors.white38, size: 60),
      ),
    );
  }
}
