import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/theme.dart';
import '../../models/recording.dart';
import '../../services/localization_service.dart';
import '../../widgets/teq_search_field.dart';
import 'participants/bids_sub_tab.dart';
import 'participants/chat_sub_tab.dart';
import 'participants/gifts_sub_tab.dart';
import 'participants/overall_sub_tab.dart';
import 'participants/shopping_sub_tab.dart';

class ParticipantsTab extends StatefulWidget {
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
  State<ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<ParticipantsTab>
    with TickerProviderStateMixin {
  late final TabController _sub;
  late final AnimationController _hintPulse;
  late final Animation<double> _hintFade;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: 5, vsync: this);
    _sub.addListener(() => setState(() {}));
    _hintPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _hintFade = CurvedAnimation(parent: _hintPulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _hintPulse.dispose();
    _sub.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RecordingParticipantActivity> get _filtered {
    if (_searchQuery.isEmpty) return widget.participants;
    final q = _searchQuery.toLowerCase();
    return widget.participants
        .where((p) => p.username.toLowerCase().contains(q))
        .toList();
  }

  bool get _hasMoreRight => _sub.index < 4;

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;

    if (widget.participants.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    final p = _filtered;

    final labels = [
      loc.t('recordingParticipantTabOverall'),
      loc.t('recordingParticipantTabBids'),
      loc.t('recordingParticipantTabShopping'),
      loc.t('recordingParticipantTabGifts'),
      loc.t('recordingParticipantTabChat'),
    ];

    final tabBar = TabBar(
      controller: _sub,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: kPrimary,
      labelColor: kPrimary,
      unselectedLabelColor: AppColors.textSecondary(context),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(fontSize: 13),
      indicatorSize: TabBarIndicatorSize.label,
      padding: EdgeInsets.zero,
      tabs: labels.map((l) => Tab(text: l)).toList(),
    );

    final surfaceColor = AppColors.surface(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TeqSearchField(
            hintText: loc.t('recordingSearchParticipants'),
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
          ),
        ),
        Container(
          color: surfaceColor,
          height: 44,
          child: Stack(
            children: [
              tabBar,
              if (_hasMoreRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: FadeTransition(
                      opacity: _hintFade,
                      child: Container(
                        width: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              surfaceColor.withAlpha(0),
                              surfaceColor.withAlpha(220),
                            ],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.border(context)),
        Expanded(
          child: TabBarView(
            controller: _sub,
            physics: const ClampingScrollPhysics(),
            children: [
              OverallSubTab(
                participants: p,
                loc: loc,
                durationSecs: widget.durationSecs,
              ),
              BidsSubTab(participants: p, loc: loc),
              ShoppingSubTab(participants: p, loc: loc),
              GiftsSubTab(participants: p, loc: loc),
              ChatSubTab(participants: p, loc: loc),
            ],
          ),
        ),
      ],
    );
  }
}
