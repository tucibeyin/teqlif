import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../ui_library/components/cards/teq_card.dart';

class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);

    // Web versiyonundaki 5 ana kategoriye göre listeler hazırlıyoruz
    final categories = [
      _FaqCategory(
        title: loc.t('faqCatAccount'),
        icon: const Icon(Icons.person_outline),
        items: [
          _FaqItem(question: loc.t('faqQAccountSignup'), answer: loc.t('faqAAccountSignup')),
          _FaqItem(question: loc.t('faqQAccountEmail'), answer: loc.t('faqAAccountEmail')),
          _FaqItem(
            question: loc.t('faqQAccountProfile'),
            answer: loc.t('faqAAccountProfile'),
          ),
          _FaqItem(
            question: loc.t('faqQAccountPassword'),
            answer: loc.t('faqAAccountPassword'),
          ),
          _FaqItem(question: loc.t('faqQAccountDelete'), answer: loc.t('faqAAccountDelete')),
        ],
      ),
      _FaqCategory(
        title: loc.t('faqCatExplore'),
        icon: const Icon(Icons.explore_outlined),
        items: [
          _FaqItem(
            question: loc.t('faqQExploreSellers'),
            answer: loc.t('faqAExploreSellers'),
          ),
          _FaqItem(
            question: loc.t('faqQExploreStreamers'),
            answer: loc.t('faqAExploreStreamers'),
          ),
          _FaqItem(
            question: loc.t('faqQExploreListings'),
            answer: loc.t('faqAExploreListings'),
          ),
          _FaqItem(
            question: loc.t('faqQExploreLiveMessages'),
            answer: loc.t('faqAExploreLiveMessages'),
          ),
        ],
      ),
      _FaqCategory(
        title: loc.t('faqCatBadges'),
        icon: const FaIcon(FontAwesomeIcons.shieldHalved),
        items: [
          _FaqItem(
            question: loc.t('faqQBadgesVerified'),
            answer: loc.t('faqABadgesVerified'),
          ),
          _FaqItem(question: loc.t('faqQBadgesPro'), answer: loc.t('faqABadgesPro')),
          _FaqItem(question: loc.t('faqQBadgesTrusted'), answer: loc.t('faqABadgesTrusted')),
          _FaqItem(
            question: loc.t('faqQBadgesSponsored'),
            answer: loc.t('faqABadgesSponsored'),
          ),
          _FaqItem(question: loc.t('faqQBadgesTuci'), answer: loc.t('faqABadgesTuci')),
        ],
      ),
      _FaqCategory(
        title: loc.t('faqCatLive'),
        icon: const Icon(Icons.sensors),
        items: [
          _FaqItem(question: loc.t('faqQLiveHost'), answer: loc.t('faqALiveHost')),
          _FaqItem(question: loc.t('faqQLiveViewer'), answer: loc.t('faqALiveViewer')),
          _FaqItem(question: loc.t('faqQLiveHype'), answer: loc.t('faqALiveHype')),
        ],
      ),
      _FaqCategory(
        title: loc.t('faqCatAI'),
        icon: const Icon(Icons.auto_awesome),
        items: [
          _FaqItem(question: loc.t('faqQAIInsights'), answer: loc.t('faqAAIInsights')),
          _FaqItem(question: loc.t('faqQAIPrice'), answer: loc.t('faqAAIPrice')),
          _FaqItem(question: loc.t('faqQAILead'), answer: loc.t('faqAAILead')),
          _FaqItem(question: loc.t('faqQAIRadar'), answer: loc.t('faqAAIRadar')),
        ],
      ),
      _FaqCategory(
        title: loc.t('faqCatIcons'),
        icon: const Icon(Icons.grid_view_rounded),
        items: [
          _FaqItem(
            question: loc.t('faqIconNameVerified'),
            answer: loc.t('faqIconVerified'),
            icon: const FaIcon(FontAwesomeIcons.circleCheck, size: 20),
          ),
          _FaqItem(
            question: loc.t('faqIconNamePro'),
            answer: loc.t('faqIconPro'),
            icon: const FaIcon(FontAwesomeIcons.crown, size: 20),
          ),
          _FaqItem(
            question: loc.t('faqIconNameTuci'),
            answer: loc.t('faqIconTuci'),
            icon: const Icon(Icons.monetization_on),
          ),
          _FaqItem(
            question: loc.t('faqIconNameBlast'),
            answer: loc.t('faqIconBlast'),
            icon: const Icon(Icons.rocket_launch),
          ),
          _FaqItem(
            question: loc.t('faqIconNameAutoBid'),
            answer: loc.t('faqIconAutoBid'),
            icon: const Icon(Icons.gavel),
          ),
          _FaqItem(
            question: loc.t('faqIconNameSales'),
            answer: loc.t('faqIconSales'),
            icon: const Icon(Icons.auto_graph_outlined),
          ),
          _FaqItem(
            question: loc.t('faqIconNameListings'),
            answer: loc.t('faqIconListings'),
            icon: const Icon(Icons.bar_chart_outlined),
          ),
          _FaqItem(
            question: loc.t('faqIconNameMarket'),
            answer: loc.t('faqIconMarket'),
            icon: const Icon(Icons.insights_outlined),
          ),
          _FaqItem(
            question: loc.t('faqIconNameTime'),
            answer: loc.t('faqIconTime'),
            icon: const Icon(Icons.schedule_outlined),
          ),
          _FaqItem(
            question: loc.t('faqIconNameConversion'),
            answer: loc.t('faqIconConversion'),
            icon: const Icon(Icons.pie_chart_outline),
          ),
          _FaqItem(
            question: loc.t('faqIconNameRadar'),
            answer: loc.t('faqIconRadar'),
            icon: const Icon(Icons.radar),
          ),
          _FaqItem(
            question: loc.t('faqIconNameRetargeting'),
            answer: loc.t('faqIconRetargeting'),
            icon: const Icon(Icons.mark_email_unread_outlined),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('profileFaq'))),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return TeqCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: EdgeInsets.zero,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: index == 0, // İlk kategori açık gelsin
                leading: IconTheme(
                  data: IconThemeData(
                    color: Theme.of(context).primaryColor,
                    size: 22,
                  ),
                  child: cat.icon,
                ),
                title: _buildAnswerWithIcons(
                  context,
                  cat.title,
                  customStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                children: cat.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 0),
                        title: Row(
                          children: [
                            if (item.icon != null) ...[
                              IconTheme(
                                data: IconThemeData(
                                  color: Theme.of(context).primaryColor,
                                  size: 20,
                                ),
                                child: item.icon!,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: _buildAnswerWithIcons(
                                context,
                                item.question,
                                customStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildAnswerWithIcons(context, item.answer),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FaqCategory {
  final String title;
  final Widget icon;
  final List<_FaqItem> items;

  _FaqCategory({required this.title, required this.icon, required this.items});
}

class _FaqItem {
  final String question;
  final String answer;
  final Widget? icon;

  _FaqItem({required this.question, required this.answer, this.icon});
}

Widget _buildAnswerWithIcons(
  BuildContext context,
  String text, {
  TextStyle? customStyle,
}) {
  final TextStyle style =
      customStyle ??
      TextStyle(
        fontSize: 13,
        color: Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
        height: 1.5,
      );

  final Map<String, Widget Function(Color)> tokenIconMap = {
    'VERIFIED': (c) => FaIcon(FontAwesomeIcons.circleCheck, size: 16, color: c),
    'PRO': (c) => FaIcon(FontAwesomeIcons.crown, size: 16, color: c),
    'TUCI': (c) => Icon(Icons.monetization_on, size: 16, color: c),
    'BLAST': (c) => Icon(Icons.rocket_launch, size: 16, color: c),
    'HOTDEMAND': (c) =>
        Icon(Icons.local_fire_department_outlined, size: 16, color: c),
    'AUTOBID': (c) => Icon(Icons.gavel, size: 16, color: c),
  };

  final Map<String, Color> tokenColorMap = {
    'VERIFIED': Colors.blue,
    'PRO': Colors.amber,
    'TUCI': Colors.orange,
    'BLAST': Colors.redAccent,
    'HOTDEMAND': Colors.red,
    'AUTOBID': Colors.deepPurple,
  };

  final regex = RegExp(r'\[ICON_([A-Z_]+)\]');

  final List<InlineSpan> spans = [];
  int lastMatchEnd = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > lastMatchEnd) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
    }

    final String token = match.group(1)!;
    final Widget Function(Color)? iconBuilder = tokenIconMap[token];
    final Color iconColor =
        tokenColorMap[token] ?? Theme.of(context).primaryColor;

    if (iconBuilder != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: iconBuilder(iconColor),
          ),
        ),
      );
    }

    lastMatchEnd = match.end;
  }

  if (lastMatchEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastMatchEnd)));
  }

  return Text.rich(TextSpan(children: spans), style: style);
}
