import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/price_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alışverişler yüklenemedi: $e')),
        );
      }
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
                    'Henüz alışverişiniz bulunmuyor.',
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _purchases.length,
                  itemBuilder: (context, index) {
                    final item = _purchases[index];
                    final itemName = item['item_name'] ?? 'Bilinmeyen Ürün';
                    final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
                    
                    return Card(
                      color: AppColors.card(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PurchaseDetailScreen(purchase: item),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(
                          itemName,
                          style: TextStyle(color: AppColors.textPrimary(context), fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '@${item['seller_username'] ?? 'Bilinmeyen Satıcı'}',
                          style: TextStyle(color: AppColors.textSecondary(context)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              fmtPrice(price),
                              style: const TextStyle(
                                color: Color(0xFF4ADE80),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_right, color: AppColors.iconSecondary(context)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
