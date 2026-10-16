import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/recording.dart';
import '../../../services/localization_service.dart';

class ChatSubTab extends StatelessWidget {
  final List<RecordingParticipantActivity> participants;
  final TranslationPack loc;

  const ChatSubTab({
    super.key,
    required this.participants,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final chatters = participants
        .where((p) => p.chats.isNotEmpty)
        .toList()
      ..sort((a, b) => b.chatCount.compareTo(a.chatCount));

    if (chatters.isEmpty) {
      return Center(
        child: Text(
          loc.t('recordingNoBuyers'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: chatters.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _ChatterCard(
        participant: chatters[i],
        rank: i + 1,
        loc: loc,
      ),
    );
  }
}

class _ChatterCard extends StatefulWidget {
  final RecordingParticipantActivity participant;
  final int rank;
  final TranslationPack loc;

  const _ChatterCard({
    required this.participant,
    required this.rank,
    required this.loc,
  });

  @override
  State<_ChatterCard> createState() => _ChatterCardState();
}

class _ChatterCardState extends State<_ChatterCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.participant;

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${widget.rank}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textTertiary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 16,
                  backgroundImage: p.avatarUrl != null
                      ? NetworkImage(p.avatarUrl!)
                      : null,
                  child: p.avatarUrl == null
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.username,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (p.chats.isNotEmpty)
                        Text(
                          widget.loc
                              .t('recordingLastMessage')
                              .replaceAll('{msg}', ''),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.loc
                          .t('recordingChatMessageCount')
                          .replaceAll('{count}', '${p.chatCount}'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.secondary,
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textTertiary(context),
                    ),
                  ],
                ),
              ],
            ),
            if (_expanded && p.chats.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: AppColors.border(context)),
              const SizedBox(height: 8),
              ...p.chats.take(10).map(
                    (c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(width: 32),
                          if (c.isHost)
                            Padding(
                              padding: const EdgeInsets.only(right: 4, top: 1),
                              child: Icon(Icons.star,
                                  size: 11,
                                  color: cs.primary),
                            ),
                          if (c.isMod && !c.isHost)
                            Padding(
                              padding: const EdgeInsets.only(right: 4, top: 1),
                              child: Icon(Icons.shield,
                                  size: 11,
                                  color: cs.tertiary),
                            ),
                          Expanded(
                            child: Text(
                              c.content,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (p.chats.length > 10)
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 4),
                  child: Text(
                    '+${p.chats.length - 10} mesaj daha',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
