import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Projenin dark/light temasına uygun renkleri döndürür.
Color _base(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E293B) // slate-800
        : const Color(0xFFE2E8F0); // slate-200

Color _highlight(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF334155) // slate-700
        : const Color(0xFFF8FAFC); // slate-50

/// Herhangi bir boyutta / şekilde kullanılabilen temel shimmer kutusu.
///
/// - `CachedNetworkImage.placeholder` yerine kullanmak için: `ShimmerBox()`
/// - Belirli boyut için: `ShimmerBox(width: 120, height: 80)`
/// - Yuvarlatılmış köşe için: `ShimmerBox(borderRadius: BorderRadius.circular(8))`
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final base = _base(context);
    final highlight = _highlight(context);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: base, borderRadius: borderRadius),
      ),
    );
  }
}

/// Proje genelinde ilan grid'i için iskelet kart.
///
/// Gerçek [_GridItem] tasarımını yansıtır:
/// - Üst kısım: resim alanı (kare, flex 3)
/// - Alt kısım: başlık satırı + fiyat satırı
class ShimmerGridCard extends StatelessWidget {
  const ShimmerGridCard({super.key});

  @override
  Widget build(BuildContext context) {
    final base = _base(context);
    final highlight = _highlight(context);
    final bg = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF1F5F9);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        color: bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resim alanı
            Expanded(
              flex: 3,
              child: Container(color: base),
            ),
            // Başlık + fiyat satırları
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 9,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 8,
                    width: 48,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
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
}

/// Tam ekran / büyük alan yükleyici için tek shimmer kart (liste satırı vb.).
///
/// Solda kare küçük resim, sağda iki satır metin içerir.
class ShimmerListRow extends StatelessWidget {
  const ShimmerListRow({super.key});

  @override
  Widget build(BuildContext context) {
    final base = _base(context);
    final highlight = _highlight(context);

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Küçük kare resim
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 100,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
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
}
