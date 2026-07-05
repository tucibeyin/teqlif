import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/app_colors.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    
    // Web versiyonundaki 5 ana kategoriye göre listeler hazırlıyoruz
    final categories = [
      _FaqCategory(
        title: l.faqCatAccount,
        icon: Icons.person_outline,
        items: [
          _FaqItem(question: l.faqQAccountSignup, answer: l.faqAAccountSignup),
          _FaqItem(question: l.faqQAccountEmail, answer: l.faqAAccountEmail),
          _FaqItem(question: l.faqQAccountProfile, answer: l.faqAAccountProfile),
          _FaqItem(question: l.faqQAccountPassword, answer: l.faqAAccountPassword),
          _FaqItem(question: l.faqQAccountDelete, answer: l.faqAAccountDelete),
        ],
      ),
      _FaqCategory(
        title: l.faqCatExplore,
        icon: Icons.explore_outlined,
        items: [
          _FaqItem(question: l.faqQExploreSellers, answer: l.faqAExploreSellers),
          _FaqItem(question: l.faqQExploreStreamers, answer: l.faqAExploreStreamers),
          _FaqItem(question: l.faqQExploreListings, answer: l.faqAExploreListings),
          _FaqItem(question: l.faqQExploreLiveMessages, answer: l.faqAExploreLiveMessages),
        ],
      ),
      _FaqCategory(
        title: l.faqCatBadges,
        icon: Icons.verified_outlined,
        items: [
          _FaqItem(question: l.faqQBadgesVerified, answer: l.faqABadgesVerified),
          _FaqItem(question: l.faqQBadgesPro, answer: l.faqABadgesPro),
          _FaqItem(question: l.faqQBadgesTrusted, answer: l.faqABadgesTrusted),
          _FaqItem(question: l.faqQBadgesSponsored, answer: l.faqABadgesSponsored),
          _FaqItem(question: l.faqQBadgesTuci, answer: l.faqABadgesTuci),
        ],
      ),
      _FaqCategory(
        title: l.faqCatLive,
        icon: Icons.sensors,
        items: [
          _FaqItem(question: l.faqQLiveHost, answer: l.faqALiveHost),
          _FaqItem(question: l.faqQLiveViewer, answer: l.faqALiveViewer),
          _FaqItem(question: l.faqQLiveHype, answer: l.faqALiveHype),
        ],
      ),
      _FaqCategory(
        title: l.faqCatAI,
        icon: Icons.auto_awesome,
        items: [
          _FaqItem(question: l.faqQAIInsights, answer: l.faqAAIInsights),
          _FaqItem(question: l.faqQAIPrice, answer: l.faqAAIPrice),
          _FaqItem(question: l.faqQAILead, answer: l.faqAAILead),
          _FaqItem(question: l.faqQAIRadar, answer: l.faqAAIRadar),
        ],
      ),
      _FaqCategory(
        title: l.faqCatIcons,
        icon: Icons.grid_view_rounded,
        items: [
          _FaqItem(question: l.faqIconNameVerified, answer: l.faqIconVerified, icon: Icons.verified),
          _FaqItem(question: l.faqIconNamePro, answer: l.faqIconPro, icon: Icons.workspace_premium),
          _FaqItem(question: l.faqIconNameTuci, answer: l.faqIconTuci, icon: Icons.monetization_on),
          _FaqItem(question: l.faqIconNameBlast, answer: l.faqIconBlast, icon: Icons.rocket_launch),
          _FaqItem(question: l.faqIconNameAutoBid, answer: l.faqIconAutoBid, icon: Icons.gavel),
          _FaqItem(question: l.faqIconNameSales, answer: l.faqIconSales, icon: Icons.auto_graph_outlined),
          _FaqItem(question: l.faqIconNameListings, answer: l.faqIconListings, icon: Icons.bar_chart_outlined),
          _FaqItem(question: l.faqIconNameMarket, answer: l.faqIconMarket, icon: Icons.insights_outlined),
          _FaqItem(question: l.faqIconNameTime, answer: l.faqIconTime, icon: Icons.schedule_outlined),
          _FaqItem(question: l.faqIconNameConversion, answer: l.faqIconConversion, icon: Icons.pie_chart_outline),
          _FaqItem(question: l.faqIconNameRadar, answer: l.faqIconRadar, icon: Icons.radar),
          _FaqItem(question: l.faqIconNameRetargeting, answer: l.faqIconRetargeting, icon: Icons.mark_email_unread_outlined),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileFaq),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: index == 0, // İlk kategori açık gelsin
                leading: Icon(cat.icon, color: Theme.of(context).primaryColor),
                title: Text(
                  cat.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                children: cat.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 0),
                        title: Row(
                          children: [
                            if (item.icon != null) ...[
                              Icon(item.icon, size: 20, color: Theme.of(context).primaryColor),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                item.question,
                                style: const TextStyle(
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
  final IconData icon;
  final List<_FaqItem> items;

  _FaqCategory({required this.title, required this.icon, required this.items});
}

class _FaqItem {
  final String question;
  final String answer;
  final IconData? icon;

  _FaqItem({required this.question, required this.answer, this.icon});
}

Widget _buildAnswerWithIcons(BuildContext context, String text) {
  final TextStyle style = TextStyle(
    fontSize: 13,
    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
    height: 1.5,
  );

  final Map<String, IconData> tokenIconMap = {
    'VERIFIED': Icons.verified,
    'PRO': Icons.workspace_premium,
    'TUCI': Icons.monetization_on,
    'BLAST': Icons.rocket_launch,
    'HOTDEMAND': Icons.local_fire_department_outlined,
    'AUTOBID': Icons.gavel,
  };

  final regex = RegExp(r'\[ICON_([A-Z_]+)\]');

  final List<InlineSpan> spans = [];
  int lastMatchEnd = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > lastMatchEnd) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start)));
    }

    final String token = match.group(1)!;
    final IconData? icon = tokenIconMap[token];

    if (icon != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(icon, size: 14, color: Theme.of(context).primaryColor),
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
