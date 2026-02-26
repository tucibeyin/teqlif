import 'package:flutter/material.dart';
import '../../../core/constants/categories.dart';

/// Gayrimenkul gibi gruplu kategorileri disabled header + sub-items olarak
/// gösteren DropdownButtonFormField. Diğer kategoriler düz item olarak eklenir.
class GroupedCategoryDropdown extends StatelessWidget {
  final String? value;
  final String label;
  final void Function(String?)? onChanged;

  const GroupedCategoryDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Ana Kategori',
  });

  @override
  Widget build(BuildContext context) {
    final groupedSlugs =
        categoryGroups.expand((g) => g.members).toSet();

    // DropdownMenuItem listesini oluştur
    final items = <DropdownMenuItem<String>>[];

    for (final group in categoryGroups) {
      // Disabled "header" satırı (seçilemiyor)
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__header__${group.slug}',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Text(group.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                group.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ));

      // Grup üyeleri — girintili
      for (final slug in group.members) {
        final root = categoryTree.firstWhere((r) => r.slug == slug,
            orElse: () => categoryTree.first);
        items.add(DropdownMenuItem<String>(
          value: root.slug,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Text(root.icon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(root.name,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF0F1923))),
              ],
            ),
          ),
        ));
      }
    }

    // Grupta olmayan kategoriler — düz liste
    for (final root
        in categoryTree.where((r) => !groupedSlugs.contains(r.slug))) {
      items.add(DropdownMenuItem<String>(
        value: root.slug,
        child: Row(
          children: [
            Text(root.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(root.name,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF0F1923))),
          ],
        ),
      ));
    }

    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: items,
      onChanged: onChanged,
    );
  }
}
