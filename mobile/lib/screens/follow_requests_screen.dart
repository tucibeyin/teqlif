import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/api.dart';
import '../config/app_colors.dart';
import '../services/localization_service.dart';
import '../ui_library/components/overlays/teq_toast.dart';
import 'public_profile_screen.dart';
import 'viewmodels/follow_requests_view_model.dart';

class FollowRequestsScreen extends ConsumerWidget {
  const FollowRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(followRequestsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          title: Text(loc.t('followRequests')),
          centerTitle: true,
          elevation: 0,
          backgroundColor: AppColors.surface(context),
          foregroundColor: AppColors.textPrimary(context),
          bottom: TabBar(
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: AppColors.textSecondary(context),
            indicatorColor: const Color(0xFF6366F1),
            tabs: [
              Tab(text: loc.t('tabFollowRequestsReceived')),
              Tab(text: loc.t('tabFollowRequestsSent')),
            ],
          ),
        ),
        body: stateAsync.when(
          data: (state) => TabBarView(
            children: [
              _buildReceivedList(context, ref, state.receivedRequests),
              _buildSentList(context, ref, state.sentRequests),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(loc.t('errorGenericRetry'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.read(followRequestsProvider.notifier).reload(),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceivedList(BuildContext context, WidgetRef ref, List<dynamic> receivedRequests) {
    final loc = ref.watch(localizationProvider);
    if (receivedRequests.isEmpty) {
      return Center(
        child: Text(
          loc.t('noFollowRequests'),
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: receivedRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = receivedRequests[index];
        final String username = user['username'];
        final String fullName = user['full_name'];
        final String? avatarUrl = user['profile_image_thumb_url'];

        return _buildUserCard(
          context: context,
          ref: ref,
          username: username,
          fullName: fullName,
          avatarUrl: avatarUrl,
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () async {
                  try {
                    await ref.read(followRequestsProvider.notifier).handleReceivedAction(user['id'], 'accept');
                  } catch (e) {
                    TeqToast.error("Hata oluştu.");
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(loc.t('acceptRequest'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  try {
                    await ref.read(followRequestsProvider.notifier).handleReceivedAction(user['id'], 'reject');
                  } catch (e) {
                    TeqToast.error("Hata oluştu.");
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surfaceVariant(context),
                  foregroundColor: AppColors.textPrimary(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(loc.t('rejectRequest'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSentList(BuildContext context, WidgetRef ref, List<dynamic> sentRequests) {
    final loc = ref.watch(localizationProvider);
    if (sentRequests.isEmpty) {
      return Center(
        child: Text(
          "Gönderilen istek yok.",
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sentRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = sentRequests[index];
        final String username = user['username'];
        final String fullName = user['full_name'];
        final String? avatarUrl = user['profile_image_thumb_url'];

        return _buildUserCard(
          context: context,
          ref: ref,
          username: username,
          fullName: fullName,
          avatarUrl: avatarUrl,
          actions: TextButton(
            onPressed: () async {
              try {
                await ref.read(followRequestsProvider.notifier).handleSentWithdraw(user['id']);
              } catch (e) {
                TeqToast.error("İptal edilemedi.");
              }
            },
            style: TextButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant(context),
              foregroundColor: AppColors.textPrimary(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(loc.t('withdrawRequest'), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  void _goToProfile(BuildContext context, WidgetRef ref, String username) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    ).then((_) {
      ref.read(followRequestsProvider.notifier).reload();
    });
  }

  Widget _buildUserCard({
    required BuildContext context,
    required WidgetRef ref,
    required String username,
    required String fullName,
    required String? avatarUrl,
    required Widget actions,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _goToProfile(context, ref, username),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.surfaceVariant(context),
                  backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(imgUrl(avatarUrl)) : null,
                  child: avatarUrl == null
                      ? Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
