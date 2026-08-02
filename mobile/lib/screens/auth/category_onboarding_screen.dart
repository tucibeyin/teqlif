import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../services/localization_service.dart';
import 'viewmodels/category_onboarding_view_model.dart';

class CategoryOnboardingScreen extends ConsumerStatefulWidget {
  final bool fromBanner;
  const CategoryOnboardingScreen({super.key, this.fromBanner = false});

  @override
  ConsumerState<CategoryOnboardingScreen> createState() => _CategoryOnboardingScreenState();
}

class _CategoryOnboardingScreenState extends ConsumerState<CategoryOnboardingScreen> {
  final Set<String> _selected = {};

  static const _categories = [
    {'slug': 'electronics', 'icon': Icons.devices_outlined},
    {'slug': 'vehicles',    'icon': Icons.directions_car_outlined},
    {'slug': 'real_estate', 'icon': Icons.home_work_outlined},
    {'slug': 'fashion',     'icon': Icons.checkroom_outlined},
    {'slug': 'sports',      'icon': Icons.sports_soccer_outlined},
    {'slug': 'books',       'icon': Icons.menu_book_outlined},
    {'slug': 'home',        'icon': Icons.home_outlined},
    {'slug': 'other',       'icon': Icons.more_horiz},
  ];

  String _label(TranslationPack loc, String slug) {
    switch (slug) {
      case 'electronics': return loc.t('catElectronics');
      case 'vehicles':    return loc.t('catVehicles');
      case 'real_estate': return loc.t('catRealEstate');
      case 'fashion':     return loc.t('catClothing');
      case 'sports':      return loc.t('catSports');
      case 'books':       return loc.t('catBooks');
      case 'home':        return loc.t('catHomeLife');
      default:            return loc.t('catOther');
    }
  }

  Future<void> _continue() async {
    if (_selected.length < 3) return;
    
    final success = await ref.read(categoryOnboardingViewModelProvider.notifier).submitCategories(_selected.toList());
    
    if (success && mounted) {
      if (widget.fromBanner) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  Future<void> _skip() async {
    await ref.read(categoryOnboardingViewModelProvider.notifier).skip();
    if (!mounted) return;
    if (widget.fromBanner) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final bg = AppColors.bg(context);
    final enough = _selected.length >= 3;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                loc.t('onboardingTitle'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                loc.t('onboardingSubtitle'),
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15),
              ),
              const SizedBox(height: 32),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final slug = cat['slug'] as String;
                  final icon = cat['icon'] as IconData;
                  final isSelected = _selected.contains(slug);

                  return GestureDetector(
                    onTap: () => setState(() {
                      isSelected ? _selected.remove(slug) : _selected.add(slug);
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kPrimary.withValues(alpha: 0.10)
                            : AppColors.card(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? kPrimary : AppColors.border(context),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 30,
                            color: isSelected ? kPrimary : AppColors.textSecondary(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _label(loc, slug),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? kPrimary : AppColors.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _selected.isNotEmpty && !enough ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    loc.t('onboardingMinHint'),
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: (enough && !ref.watch(categoryOnboardingViewModelProvider).isLoading) ? _continue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kPrimary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: ref.watch(categoryOnboardingViewModelProvider).isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          loc.t('onboardingContinue'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: ref.watch(categoryOnboardingViewModelProvider).isLoading ? null : _skip,
                  child: Text(
                    loc.t('onboardingSkip'),
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
