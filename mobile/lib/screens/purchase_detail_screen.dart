import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/price_formatter.dart';
import 'listing_detail_screen.dart';
import 'public_profile_screen.dart';
import '../../services/listing_service.dart';

class PurchaseDetailScreen extends StatelessWidget {
  final Map<String, dynamic> purchase;

  const PurchaseDetailScreen({super.key, required this.purchase});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final itemName = purchase['item_name'] ?? 'Bilinmeyen Ürün';
    final sellerUsername = purchase['seller_username'] ?? 'Bilinmeyen Satıcı';
    final price = (purchase['final_price'] as num?)?.toDouble() ?? 0.0;
    final proofImageUrl = purchase['proof_image_url'] as String?;
    final listingId = purchase['listing_id'] as int?;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(l.purchaseDetailTitle),
        backgroundColor: const Color(0xFF0F172A),
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
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l.purchaseSeller}: @$sellerUsername',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
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
            
            // Satıcı Profiline Git butonu
            ElevatedButton.icon(
              icon: const Icon(Icons.person, color: Colors.white),
              label: Text(l.purchaseViewSeller, style: const TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366f1),
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
            const SizedBox(height: 12),
            
            // İlanı Görüntüle butonu
            if (listingId != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.article, color: Colors.white70),
                label: Text(l.purchaseViewListing, style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF475569)),
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
                      const SnackBar(content: Text('İlan bulunamadı.')),
                    );
                  }
                },
              ),

            const SizedBox(height: 24),

            // Satış Kanıt Görseli
            if (proofImageUrl != null && proofImageUrl.isNotEmpty) ...[
              Text(
                l.purchaseProofImage,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  proofImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: Colors.black26,
                    child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 50)),
                  ),
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
