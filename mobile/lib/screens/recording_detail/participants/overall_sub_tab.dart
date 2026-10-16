import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/recording.dart';
import '../../../services/localization_service.dart';
import '../widgets/participant_card.dart';

class OverallSubTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final double? durationSecs;
  final TranslationPack loc;

  const OverallSubTab({
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: participants.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => ParticipantCard(
        participant: participants[i],
        rank: i + 1,
        durationSecs: durationSecs,
      ),
    );
  }
}
