import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../models/recording.dart';
import '../../services/localization_service.dart';
import 'participants/bids_sub_tab.dart';
import 'participants/chat_sub_tab.dart';
import 'participants/gifts_sub_tab.dart';
import 'participants/overall_sub_tab.dart';
import 'participants/shopping_sub_tab.dart';

class ParticipantsTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final double? durationSecs;
  final TranslationPack loc;

  const ParticipantsTab({
    super.key,
    required this.participants,
    required this.loc,
    this.durationSecs,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    final subTabLabels = [
      loc.t('recordingParticipantTabOverall'),
      loc.t('recordingParticipantTabBids'),
      loc.t('recordingParticipantTabShopping'),
      loc.t('recordingParticipantTabGifts'),
      loc.t('recordingParticipantTabChat'),
    ];

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _SubTabBar(labels: subTabLabels),
          Expanded(
            child: TabBarView(
              physics: const ClampingScrollPhysics(),
              children: [
                OverallSubTab(
                  participants: participants,
                  loc: loc,
                  durationSecs: durationSecs,
                ),
                BidsSubTab(participants: participants, loc: loc),
                ShoppingSubTab(participants: participants, loc: loc),
                GiftsSubTab(participants: participants, loc: loc),
                ChatSubTab(participants: participants, loc: loc),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTabBar extends StatelessWidget {
  final List<String> labels;
  const _SubTabBar({required this.labels});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface(context),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: kPrimary,
        labelColor: kPrimary,
        unselectedLabelColor: AppColors.textSecondary(context),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        indicatorSize: TabBarIndicatorSize.label,
        tabs: labels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }
}
