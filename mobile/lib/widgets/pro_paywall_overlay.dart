import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/localization_service.dart';

/// Blurred paywall overlay for PRO tool screens.
/// Wrap in a Stack — it uses Positioned.fill.
class ProPaywallOverlay extends ConsumerWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String descKey;

  const ProPaywallOverlay({
    super.key,
    required this.icon,
    required this.gradientColors,
    required this.descKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: AppColors.bg(context).withValues(alpha: 0.65),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.card(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                          alpha: AppColors.isDark(context) ? 0.5 : 0.12),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      loc.t('proUpgradeTitle'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      loc.t(descKey),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary(context),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradientColors),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ElevatedButton(
                          onPressed: () => launchUrl(
                            Uri.parse('https://www.teqlif.com/pro-plan.html'),
                            mode: LaunchMode.inAppWebView,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            loc.t('proUpgradeBtn'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder shown behind the paywall blur for locked PRO screens.
class ProLockedPlaceholder extends StatelessWidget {
  const ProLockedPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Row(children: [
          Expanded(child: _skel(context, height: 88)),
          const SizedBox(width: 10),
          Expanded(child: _skel(context, height: 88)),
          const SizedBox(width: 10),
          Expanded(child: _skel(context, height: 88)),
        ]),
        const SizedBox(height: 14),
        _skel(context, height: 160),
        const SizedBox(height: 14),
        _skel(context, height: 72),
        const SizedBox(height: 10),
        _skel(context, height: 72),
        const SizedBox(height: 10),
        _skel(context, height: 72),
        const SizedBox(height: 14),
        _skel(context, height: 120),
        const SizedBox(height: 10),
        _skel(context, height: 72),
        const SizedBox(height: 10),
        _skel(context, height: 72),
      ],
    );
  }

  Widget _skel(BuildContext context, {required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
    );
  }
}
