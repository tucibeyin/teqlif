import 'dart:developer';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/category_service.dart';
import '../../utils/price_formatter.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../config/api.dart';
import 'sale_detail_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _sales = [];
  List<(String, String)>? _categories;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = '';
  DateTimeRange? _dateRange;

  List<Map<String, dynamic>> get _filteredSales {
    var result = _sales;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((item) =>
        (item['item_name'] as String? ?? '').toLowerCase().contains(q)
      ).toList();
    }
    if (_categoryFilter.isNotEmpty) {
      result = result.where((item) => (item['category'] as String?) == _categoryFilter).toList();
    }
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      result = result.where((item) {
        final raw = item['ended_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) {
        if (mounted) setState(() => _categories = cats);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    try {
      final sales = await AuthService.getMySales();
      if (mounted) {
        setState(() {
          _sales = sales;
          _loading = false;
        });
      }
    } catch (e, st) {
      log('Error loading sales: $e', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.saleLoadError),
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

  Widget _buildFilterBar(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: l.searchHintTextListing,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        if (_categories != null && _categories!.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(l.allCategories, style: const TextStyle(fontSize: 12)),
                    selected: _categoryFilter.isEmpty,
                    onSelected: (_) => setState(() => _categoryFilter = ''),
                    selectedColor: kPrimary.withValues(alpha: 0.15),
                    checkmarkColor: kPrimary,
                  ),
                ),
                ..._categories!.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat.$2, style: const TextStyle(fontSize: 12)),
                    selected: _categoryFilter == cat.$1,
                    onSelected: (_) => setState(() =>
                        _categoryFilter = _categoryFilter == cat.$1 ? '' : cat.$1),
                    selectedColor: kPrimary.withValues(alpha: 0.15),
                    checkmarkColor: kPrimary,
                  ),
                )),
              ],
            ),
          ),
        _buildDateRangePicker(l),
        const SizedBox(height: 4),
      ],
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  Widget _buildDateRangePicker(AppLocalizations l) {
    final hasRange = _dateRange != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: InkWell(
        onTap: () async {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            initialDateRange: _dateRange,
            locale: Localizations.localeOf(context),
          );
          if (picked != null) setState(() => _dateRange = picked);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: hasRange ? kPrimary : AppColors.border(context)),
            borderRadius: BorderRadius.circular(8),
            color: hasRange ? kPrimary.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16,
                  color: hasRange ? kPrimary : AppColors.textSecondary(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasRange
                      ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                      : l.filterSelectDate,
                  style: TextStyle(fontSize: 13,
                      color: hasRange ? kPrimary : AppColors.textSecondary(context)),
                ),
              ),
              if (hasRange)
                GestureDetector(
                  onTap: () => setState(() => _dateRange = null),
                  child: Icon(Icons.close, size: 16, color: kPrimary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final filtered = _filteredSales;
    final bool hasFilter = _searchQuery.isNotEmpty || _categoryFilter.isNotEmpty || _dateRange != null;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.settingsMySales),
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _sales.isEmpty
              ? Center(
                  child: Text(
                    l.saleEmptyState,
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
                  ),
                )
              : Column(
                  children: [
                    _buildFilterBar(l),
                    if (hasFilter && filtered.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(l.searchNoResults,
                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 15)),
                        ),
                      )
                    else
                      Expanded(
                        child: RefreshIndicator(
                          color: kPrimary,
                          onRefresh: _loadSales,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final itemName = item['item_name'] as String? ?? l.purchaseUnknownItem;
                              final price = (item['final_price'] as num?)?.toDouble() ?? 0.0;
                              final buyer = item['buyer_username'] as String? ?? l.saleUnknownBuyer;
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
                                        builder: (_) => SaleDetailScreen(sale: item),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: imgUrl(thumbnailUrl),
                                                  width: 72,
                                                  height: 72,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, _, _) => _placeholderBox(),
                                                  placeholder: (_, _) => _placeholderBox(),
                                                )
                                              : _placeholderBox(),
                                        ),
                                        const SizedBox(width: 12),
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
                                                '@$buyer',
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
                                                        _categories?.firstWhere(
                                                          (p) => p.$1 == category,
                                                          orElse: () => (category, category),
                                                        ).$2 ?? category,
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
                                                      isBuyItNow ? l.saleTypeBuyNow : l.saleTypeBid,
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
                      ),
                  ],
                ),
    );
  }

  Widget _placeholderBox() {
    return Container(
      width: 72,
      height: 72,
      color: AppColors.card(context).withValues(alpha: 0.5),
      child: Icon(Icons.storefront_outlined, color: AppColors.iconSecondary(context), size: 32),
    );
  }
}
