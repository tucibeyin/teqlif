import '../ui_library/components/overlays/teq_snackbar.dart';
import 'package:flutter/material.dart';
import '../config/api.dart';
import '../config/theme.dart';
import '../config/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import 'public_profile_screen.dart';
import '../ui_library/components/buttons/teq_button.dart';
import 'viewmodels/blocked_users_view_model.dart';

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t('blockedUsersTitle')),
      ),
      body: stateAsync.when(
        data: (state) {
          if (state.blockedUsers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 52, color: AppColors.textTertiary(context)),
                  const SizedBox(height: 12),
                  Text(
                    loc.t('blockedNone'),
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: state.blockedUsers.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: AppColors.divider(context)),
            itemBuilder: (_, i) {
              final u = state.blockedUsers[i] as Map<String, dynamic>;
              final name = (u['full_name'] as String?) ??
                  (u['username'] as String?) ??
                  '?';
              final username = u['username'] as String? ?? '';
              final rawImg = u['profile_image_url'] as String?;
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return ListTile(
                leading: GestureDetector(
                  key: Key('blocked_avatar_${u['id']}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(username: username),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: kPrimary.withValues(alpha: 0.12),
                    backgroundImage:
                        rawImg != null ? NetworkImage(imgUrl(rawImg)) : null,
                    child: rawImg == null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          )
                        : null,
                  ),
                ),
                title: GestureDetector(
                  key: Key('blocked_name_${u['id']}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(username: username),
                    ),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                subtitle: Text(
                  '@$username',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary(context)),
                ),
                trailing: TeqButton.outline(
                  key: Key('blocked_btn_engel_kaldir_${u['id']}'),
                  onPressed: () async {
                    try {
                      await ref
                          .read(blockedUsersProvider.notifier)
                          .unblock(username, u['id'] as int);
                    } catch (_) {
                      if (context.mounted) {
                        TeqSnackBar.show(
                          message: loc.t('blockedActionFailed'),
                          type: TeqSnackBarType.info,
                        );
                      }
                    }
                  },
                  text: loc.t('blockedUnblock'),
                  size: TeqButtonSize.small,
                  customColor: const Color(0xFFEF4444),
                  isExpanded: false,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: kPrimary)),
        error: (e, st) => Center(child: Text(loc.t('errorGenericRetry'))),
      ),
    );
  }
}
