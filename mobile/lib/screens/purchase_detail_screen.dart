import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/price_formatter.dart';
import 'listing_detail_screen.dart';
import 'public_profile_screen.dart';
import '../../services/listing_service.dart';
import '../../services/category_service.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'messages_screen.dart';
import '../../ui_library/components/cards/teq_card.dart';
import '../../ui_library/components/buttons/teq_button.dart';

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
    final sellerUsername =
        purchase['seller_username'] as String? ?? l.purchaseUnknownSeller;
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
    final thumbnailUrl =
        purchase['thumbnail_url'] as String? ??
        purchase['image_url'] as String?;

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
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imgUrl(thumbnailUrl),
                  height: 220,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => _imagePlaceholder(),
                  placeholder: (_, _) => _imagePlaceholder(),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Row(
                children: [
                  const Icon(
                    Icons.hide_image_outlined,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l.noListingPhoto,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Item details card
            TeqCard(
              padding: const EdgeInsets.all(16),
              color: AppColors.card(context),
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
                    FutureBuilder<List<(String, String)>>(
                      future: CategoryService.getCategories(
                        locale: Localizations.localeOf(context).languageCode,
                      ),
                      builder: (context, snap) {
                        final label =
                            snap.data
                                ?.firstWhere(
                                  (p) => p.$1 == category,
                                  orElse: () => (category, category),
                                )
                                .$2 ??
                            category;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: kPrimary,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  Text(
                    '${l.purchaseSeller}: @$sellerUsername',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 15,
                    ),
                  ),
                  const Divider(height: 24),
                  _infoRow(
                    context,
                    AppLocalizations.of(context)!.competitorRadarSalePrice,
                    fmtPrice(finalPrice),
                    valueColor: const Color(0xFF4ADE80),
                  ),
                  if (startPrice != null)
                    _infoRow(context, l.saleStartPrice, fmtPrice(startPrice)),
                  _infoRow(
                    context,
                    l.saleType,
                    isBuyItNow ? l.saleTypeBuyNow : l.saleTypeAuction,
                    valueColor: isBuyItNow
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFF97316),
                  ),
                  if (!isBuyItNow && bidCount != null)
                    _infoRow(context, l.saleBidCount, '$bidCount'),
                  if (startedAt != null)
                    _infoRow(
                      context,
                      AppLocalizations.of(context)!.notificationStart,
                      _formatDate(startedAt),
                    ),
                  if (endedAt != null)
                    _infoRow(
                      context,
                      AppLocalizations.of(context)!.notificationEnd,
                      _formatDate(endedAt),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Satıcı Profiline Git
            TeqButton(
              icon: Icons.person,
              text: l.purchaseViewSeller,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PublicProfileScreen(username: sellerUsername),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),

            // Satıcıya Mesaj Gönder
            if (sellerId != null)
              TeqButton(
                icon: Icons.message_rounded,
                text: AppLocalizations.of(context)!.actionSendMessageToSeller,
                customColor: const Color(0xFF6B21A8),
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
              SizedBox(
                width: double.infinity,
                child: TeqButton.outline(
                  isExpanded: true,
                  onPressed: () async {
                    final listing = await ListingService.getListingById(
                      listingId,
                    );
                    if (!context.mounted) return;
                    if (listing != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListingDetailScreen(listing: listing),
                        ),
                      );
                    } else {
                      TeqSnackBar.show(context, message: l.purchaseListingNotFound);
                    }
                  },
                  text: l.purchaseViewListing,
                  icon: Icons.article,
                ),
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
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    height: 200,
                    color: Colors.black26,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 50,
                      ),
                    ),
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

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 14,
            ),
          ),
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
        child: Icon(
          Icons.shopping_bag_outlined,
          color: Colors.white38,
          size: 60,
        ),
      ),
    );
  }
}
