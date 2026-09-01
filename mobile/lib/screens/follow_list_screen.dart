import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/error_mapper.dart';
import '../services/localization_service.dart';
import 'public_profile_screen.dart';
import 'viewmodels/follow_list_view_model.dart';

export 'viewmodels/follow_list_view_model.dart' show FollowListType;

class FollowListScreen extends ConsumerWidget {
  final int userId;
  final FollowListType type;
  final String title;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.type,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final args = FollowListArgs(userId: userId, type: type);
    final stateAsync = ref.watch(followListProvider(args));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: stateAsync.when(
        data: (state) {
          if (state.users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people_outline, size: 56, color: Color(0xFFD1D5DB)),
                  const SizedBox(height: 12),
                  Text(
                    type == FollowListType.followers
                        ? loc.t('followNoFollowers')
                        : loc.t('followNoFollowing'),
                    style: TextStyle(color: AppColors.textSecondary(context), fontSize: 15),
                  ),
                ],
              ),
            );
          }
          
          return ListView.separated(
            itemCount: state.users.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (ctx, i) {
              final u = state.users[i] as Map<String, dynamic>;
              final isMe = u['is_me'] as bool? ?? false;
              final isFollowing = u['is_following'] as bool? ?? false;
              final fullName = u['full_name'] as String? ?? '';
              final username = u['username'] as String? ?? '';
              final initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: GestureDetector(
                  key: Key('follow_avatar_${u['id']}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(username: username),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: kPrimary.withValues(alpha: 0.12),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: kPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                title: GestureDetector(
                  key: Key('follow_name_${u['id']}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(username: username),
                    ),
                  ),
                  child: Text(
                    fullName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                subtitle: Text(
                  '@$username',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context)),
                ),
                trailing: isMe
                    ? null
                    : SizedBox(
                        width: 100,
                        child: OutlinedButton(
                          key: Key('follow_btn_toggle_${u['id']}'),
                          onPressed: () {
                            ref.read(followListProvider(args).notifier).toggleFollow(i);
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isFollowing ? null : kPrimary,
                            foregroundColor: isFollowing ? AppColors.textPrimary(context) : Colors.white,
                            side: BorderSide(
                              color: isFollowing ? AppColors.border(context) : kPrimary,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(isFollowing ? loc.t('followBtnFollowing') : loc.t('followBtnFollow')),
                        ),
                      ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (e, _) => Center(child: Text(ErrorMapper.map(e, loc))),
      ),
    );
  }
}
