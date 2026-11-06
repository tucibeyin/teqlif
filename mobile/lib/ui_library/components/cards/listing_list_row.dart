import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

/// Izgara yerine liste görünümde ilan satırı.
///
/// Kullanım:
/// ```dart
/// ListingListRow(
///   title: listing['title'],
///   price: '1.200 ₺',
///   imageUrl: resolvedUrl,
///   location: 'İstanbul',
///   category: 'Elektronik',
///   subcategory: 'Telefon',
///   isSponsored: false,
///   onTap: () { ... },
/// )
/// ```
class ListingListRow extends StatelessWidget {
  final String? title;
  final String? price;
  final String? imageUrl;
  final String? location;
  final String? category;
  final String? subcategory;
  final bool isSponsored;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ListingListRow({
    super.key,
    this.title,
    this.price,
    this.imageUrl,
    this.location,
    this.category,
    this.subcategory,
    this.isSponsored = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? TeqColors.textSecondaryDark
        : TeqColors.textSecondaryLight;
    final dividerColor = isDark ? TeqColors.dividerDark : TeqColors.dividerLight;

    // Lokasyon + kategori alt satırı
    final parts = <String>[
      if (location != null && location!.isNotEmpty) location!,
      if (category != null && category!.isNotEmpty)
        (subcategory != null && subcategory!.isNotEmpty)
            ? '$category › $subcategory'
            : category!,
    ];
    final metaLine = parts.join('  ·  ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              TeqSpacing.m, TeqSpacing.s, TeqSpacing.m, TeqSpacing.s,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Thumbnail ──────────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(TeqSpacing.radiusM),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => _Placeholder(),
                            errorWidget: (_, _, _) => _Placeholder(),
                          )
                        : _Placeholder(),
                  ),
                ),
                const SizedBox(width: TeqSpacing.s),
                // ── Metin bloğu ────────────────────────────────────
                Expanded(
                  child: SizedBox(
                    height: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Başlık
                        Text(
                          title ?? '',
                          style: TeqTypography.labelMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Fiyat
                        if (price != null && price!.isNotEmpty)
                          Text(
                            price!,
                            style: const TextStyle(
                              color: TeqColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        // Lokasyon + Kategori
                        if (metaLine.isNotEmpty)
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 11,
                                color: textSecondary,
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  metaLine,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textSecondary,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                // ── Sponsorlu badge ────────────────────────────────
                if (isSponsored)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: TeqSpacing.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TeqSpacing.xxs,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: TeqColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(TeqSpacing.radiusS),
                      ),
                      child: Text(
                        'S',
                        style: const TextStyle(
                          color: TeqColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Divider(height: 1, indent: 16 + 72 + 12.0, color: dividerColor),
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF3F4F6),
      child: const Icon(Icons.image_outlined, color: Color(0xFF9CA3AF), size: 28),
    );
  }
}
