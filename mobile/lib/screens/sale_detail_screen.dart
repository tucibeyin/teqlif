import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/price_formatter.dart';
import 'listing_detail_screen.dart';
import 'public_profile_screen.dart';
import '../../services/listing_service.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';

class SaleDetailScreen extends StatelessWidget {
  final Map<String, dynamic> sale;

  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemName = sale['item_name'] ?? l.purchaseUnknownItem;
    final buyerUsername = sale['buyer_username'] ?? l.saleUnknownBuyer;
    final price = (sale['final_price'] as num?)?.toDouble() ?? 0.0;
    final proofImageUrl = sale['proof_image_url'] as String?;
    final listingId = sale['listing_id'] as int?;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.saleDetailTitle),
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
            // Ürün bilgileri
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
                    style: TextStyle(color: AppColors.textPrimary(context), fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.saleBuyerLabel}: @$buyerUsername',
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    fmtPrice(price),
                    style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Alıcı Profiline Git butonu
            ElevatedButton.icon(
              icon: const Icon(Icons.person, color: Colors.white),
              label: Text(l.purchaseViewSeller, style: const TextStyle(color: Colors.white)), // Text can stay or change to View Profile
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(username: buyerUsername)),
                );
              },
            ),
            const SizedBox(height: 12),
            
            // Alıcıya Mesaj Gönder butonu
            ElevatedButton.icon(
              icon: const Icon(Icons.message, color: Colors.white),
              label: Text(l.saleMessageBuyer, style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B21A8), // Purple color for messaging
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                // TODO: Direct Message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message feature coming soon.')),
                );
              },
            ),
            const SizedBox(height: 12),
            
            // İlanı Görüntüle butonu
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
                  Navigator.pop(context); // close loading
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
                style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imgUrl(proofImageUrl),
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    height: 200,
                    color: Colors.black26,
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 50)),
                  ),
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Colors.black12,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
