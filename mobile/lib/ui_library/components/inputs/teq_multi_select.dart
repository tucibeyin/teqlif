import 'package:flutter/material.dart';
import '../../foundation/teq_colors.dart';
import '../../foundation/teq_spacing.dart';
import '../../foundation/teq_typography.dart';

/// A chip-based multi-select input for the Teqlif design system.
///
/// Options with [isExclusive] = true behave as a "none of the above" toggle:
/// selecting one clears all others, and selecting any non-exclusive option
/// clears the exclusive selection.
class TeqMultiSelect extends StatelessWidget {
  const TeqMultiSelect({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.optional = false,
    this.validator,
  });

  final String label;
  final List<TeqMultiSelectOption> options;
  final Set<String> selected;
  final void Function(Set<String>) onChanged;
  final bool optional;
  final String? Function(Set<String>)? validator;

  void _toggle(TeqMultiSelectOption opt) {
    if (opt.isExclusive) {
      onChanged({opt.value});
      return;
    }
    final next = Set<String>.from(selected);
    if (next.contains(opt.value)) {
      next.remove(opt.value);
    } else {
      // Remove exclusive options (e.g. Hatasız)
      for (final o in options) {
        if (o.isExclusive) next.remove(o.value);
      }
      // Remove options in the same mutual-exclusion group
      if (opt.exclusionGroup != null) {
        for (final o in options) {
          if (o.exclusionGroup == opt.exclusionGroup) next.remove(o.value);
        }
      }
      next.add(opt.value);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = TeqColors.primary;
    final selectedBg = TeqColors.primaryBg;
    final unselectedBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF4F4F5);
    final unselectedBorder = isDark ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);

    return FormField<Set<String>>(
      initialValue: selected,
      validator: validator != null ? (_) => validator!(selected) : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TeqTypography.labelSmall.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            SizedBox(height: TeqSpacing.xs),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: options.map((opt) {
                final isSelected = selected.contains(opt.value);
                return GestureDetector(
                  onTap: () => _toggle(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedBg : unselectedBg,
                      border: Border.all(
                        color: isSelected ? selectedColor : unselectedBorder,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(Icons.check, size: 14, color: selectedColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected
                                ? selectedColor
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  state.errorText!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class TeqMultiSelectOption {
  const TeqMultiSelectOption({
    required this.value,
    required this.label,
    this.isExclusive = false,
    this.exclusionGroup,
  });

  final String value;
  final String label;
  final bool isExclusive;
  // Options sharing the same exclusionGroup are mutually exclusive with each other.
  final String? exclusionGroup;
}
