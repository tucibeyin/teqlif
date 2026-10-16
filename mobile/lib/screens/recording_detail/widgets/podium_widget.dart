import 'package:flutter/material.dart';

import '../../../models/recording.dart';
import 'stacked_avatars.dart';

class PodiumWidget extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final String title;

  const PodiumWidget({
    super.key,
    required this.participants,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (participants.length == 1)
          _singlePodium(context, participants[0])
        else if (participants.length == 2)
          _twoPodium(context, participants[0], participants[1])
        else
          _threePodium(
              context, participants[0], participants[1], participants[2]),
      ],
    );
  }

  Widget _singlePodium(
      BuildContext context, RecordingParticipantActivity p1) {
    return _PodiumSlot(
      participant: p1,
      rank: 1,
      barHeight: 80,
    );
  }

  Widget _twoPodium(BuildContext context, RecordingParticipantActivity p1,
      RecordingParticipantActivity p2) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumSlot(participant: p2, rank: 2, barHeight: 56)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSlot(participant: p1, rank: 1, barHeight: 80)),
      ],
    );
  }

  Widget _threePodium(
    BuildContext context,
    RecordingParticipantActivity p1,
    RecordingParticipantActivity p2,
    RecordingParticipantActivity p3,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _PodiumSlot(participant: p2, rank: 2, barHeight: 56)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSlot(participant: p1, rank: 1, barHeight: 80)),
        const SizedBox(width: 8),
        Expanded(child: _PodiumSlot(participant: p3, rank: 3, barHeight: 40)),
      ],
    );
  }
}

class _PodiumSlot extends StatelessWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final double barHeight;

  const _PodiumSlot({
    required this.participant,
    required this.rank,
    required this.barHeight,
  });

  Color _rankColor(ColorScheme cs) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFCD7F32);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rankColor = _rankColor(cs);

    return Column(
      children: [
        StackedAvatars(
          avatarUrls: [participant.avatarUrl],
          size: 36,
          maxVisible: 1,
        ),
        const SizedBox(height: 4),
        Text(
          participant.username,
          style: TextStyle(fontSize: 11, color: cs.onSurface),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: rankColor.withAlpha(40),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(color: rankColor.withAlpha(120)),
          ),
          alignment: Alignment.center,
          child: Text(
            '#$rank',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: rankColor,
            ),
          ),
        ),
      ],
    );
  }
}
