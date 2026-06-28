import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';

class CategoryOnboardingScreen extends StatefulWidget {
  final bool fromBanner;
  const CategoryOnboardingScreen({super.key, this.fromBanner = false});

  @override
  State<CategoryOnboardingScreen> createState() =>
      _CategoryOnboardingScreenState();
}

class _CategoryOnboardingScreenState extends State<CategoryOnboardingScreen> {
  final Set<String> _selected = {};
  bool _loading = false;

  static const _categories = [
    {'slug': 'elektronik', 'icon': Icons.devices_outlined},
    {'slug': 'vasita',     'icon': Icons.directions_car_outlined},
    {'slug': 'emlak',      'icon': Icons.home_work_outlined},
    {'slug': 'giyim',      'icon': Icons.checkroom_outlined},
    {'slug': 'spor',       'icon': Icons.sports_soccer_outlined},
    {'slug': 'kitap',      'icon': Icons.menu_book_outlined},
    {'slug': 'ev',         'icon': Icons.home_outlined},
    {'slug': 'diger',      'icon': Icons.more_horiz},
  ];

  String _label(AppLocalizations l, String slug) {
    switch (slug) {
      case 'elektronik': return l.catElectronics;
      case 'vasita':     return l.catVehicles;
      case 'emlak':      return l.catRealEstate;
      case 'giyim':      return l.catClothing;
      case 'spor':       return l.catSports;
      case 'kitap':      return l.catBooks;
      case 'ev':         return l.catHomeLife;
      default:           return l.catOther;
    }
  }

  Future<void> _continue() async {
    if (_selected.length < 3) return;
    setState(() => _loading = true);
    try {
      await AuthService.seedOnboardingInterests(_selected.toList());
    } catch (_) {
      // API hatası olsa bile devam et — feed popüler ilanlarla açılır
    }
    // API başarılı olsun ya da olmasın, onboarding'i tamamlanmış işaretle.
    // Önceden try içindeydi, API hatası alınca prefs hiç yazılmıyor
    // ve banner bir daha kapanmıyordu.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    if (widget.fromBanner) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _skip() {
    SharedPreferences.getInstance().then((p) => p.setBool('onboarding_done', false));
    if (widget.fromBanner) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l   = AppLocalizations.of(context)!;
    final bg  = AppColors.bg(context);
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

              // Başlık
              Text(
                l.onboardingTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.onboardingSubtitle,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 32),

              // Kategori grid
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
                    final cat      = _categories[i];
                    final slug     = cat['slug'] as String;
                    final icon     = cat['icon'] as IconData;
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
                            color: isSelected
                                ? kPrimary
                                : AppColors.border(context),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 30,
                              color: isSelected
                                  ? kPrimary
                                  : AppColors.textSecondary(context),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _label(l, slug),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? kPrimary
                                    : AppColors.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // Alt butonlar
              const SizedBox(height: 16),

              // İpucu (seçim yetersizse)
              AnimatedOpacity(
                opacity: _selected.isNotEmpty && !enough ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l.onboardingMinHint,
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
                  onPressed: (enough && !_loading) ? _continue : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: kPrimary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          l.onboardingContinue,
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
                  onPressed: _loading ? null : _skip,
                  child: Text(
                    l.onboardingSkip,
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 14,
                    ),
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
