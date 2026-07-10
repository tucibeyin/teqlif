import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
        icon: const Icon(Icons.person_outline),
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
        icon: const Icon(Icons.explore_outlined),
        items: [
          _FaqItem(question: l.faqQExploreSellers, answer: l.faqAExploreSellers),
          _FaqItem(question: l.faqQExploreStreamers, answer: l.faqAExploreStreamers),
          _FaqItem(question: l.faqQExploreListings, answer: l.faqAExploreListings),
          _FaqItem(question: l.faqQExploreLiveMessages, answer: l.faqAExploreLiveMessages),
        ],
      ),
      _FaqCategory(
        title: l.faqCatBadges,
        icon: const FaIcon(FontAwesomeIcons.shieldHalved),
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
        icon: const Icon(Icons.sensors),
        items: [
          _FaqItem(question: l.faqQLiveHost, answer: l.faqALiveHost),
          _FaqItem(question: l.faqQLiveViewer, answer: l.faqALiveViewer),
          _FaqItem(question: l.faqQLiveHype, answer: l.faqALiveHype),
        ],
      ),
      _FaqCategory(
        title: l.faqCatAI,
        icon: const Icon(Icons.auto_awesome),
        items: [
          _FaqItem(question: l.faqQAIInsights, answer: l.faqAAIInsights),
          _FaqItem(question: l.faqQAIPrice, answer: l.faqAAIPrice),
          _FaqItem(question: l.faqQAILead, answer: l.faqAAILead),
          _FaqItem(question: l.faqQAIRadar, answer: l.faqAAIRadar),
        ],
      ),
      _FaqCategory(
        title: l.faqCatIcons,
        icon: const Icon(Icons.grid_view_rounded),
        items: [
          _FaqItem(question: l.faqIconNameVerified, answer: l.faqIconVerified, icon: const FaIcon(FontAwesomeIcons.circleCheck, size: 20)),
          _FaqItem(question: l.faqIconNamePro, answer: l.faqIconPro, icon: const FaIcon(FontAwesomeIcons.crown, size: 20)),
          _FaqItem(question: l.faqIconNameTuci, answer: l.faqIconTuci, icon: const Icon(Icons.monetization_on)),
          _FaqItem(question: l.faqIconNameBlast, answer: l.faqIconBlast, icon: const Icon(Icons.rocket_launch)),
          _FaqItem(question: l.faqIconNameAutoBid, answer: l.faqIconAutoBid, icon: const Icon(Icons.gavel)),
          _FaqItem(question: l.faqIconNameSales, answer: l.faqIconSales, icon: const Icon(Icons.auto_graph_outlined)),
          _FaqItem(question: l.faqIconNameListings, answer: l.faqIconListings, icon: const Icon(Icons.bar_chart_outlined)),
          _FaqItem(question: l.faqIconNameMarket, answer: l.faqIconMarket, icon: const Icon(Icons.insights_outlined)),
          _FaqItem(question: l.faqIconNameTime, answer: l.faqIconTime, icon: const Icon(Icons.schedule_outlined)),
          _FaqItem(question: l.faqIconNameConversion, answer: l.faqIconConversion, icon: const Icon(Icons.pie_chart_outline)),
          _FaqItem(question: l.faqIconNameRadar, answer: l.faqIconRadar, icon: const Icon(Icons.radar)),
          _FaqItem(question: l.faqIconNameRetargeting, answer: l.faqIconRetargeting, icon: const Icon(Icons.mark_email_unread_outlined)),
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
                leading: IconTheme(
                  data: IconThemeData(color: Theme.of(context).primaryColor, size: 22),
                  child: cat.icon,
                ),
                title: _buildAnswerWithIcons(
                  context, 
                  cat.title,
                  customStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                              IconTheme(
                                data: IconThemeData(color: Theme.of(context).primaryColor, size: 20),
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

Widget _buildAnswerWithIcons(BuildContext context, String text, {TextStyle? customStyle}) {
  final TextStyle style = customStyle ?? TextStyle(
    fontSize: 13,
    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
    height: 1.5,
  );

  final Map<String, Widget Function(Color)> tokenIconMap = {
    'VERIFIED': (c) => FaIcon(FontAwesomeIcons.circleCheck, size: 16, color: c),
    'PRO':      (c) => FaIcon(FontAwesomeIcons.crown,        size: 16, color: c),
    'TUCI':     (c) => Icon(Icons.monetization_on,           size: 16, color: c),
    'BLAST':    (c) => Icon(Icons.rocket_launch,             size: 16, color: c),
    'HOTDEMAND':(c) => Icon(Icons.local_fire_department_outlined, size: 16, color: c),
    'AUTOBID':  (c) => Icon(Icons.gavel,                     size: 16, color: c),
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
    final Color iconColor = tokenColorMap[token] ?? Theme.of(context).primaryColor;

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
