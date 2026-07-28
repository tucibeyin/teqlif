import '../ui_library/components/overlays/teq_snackbar.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import '../config/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../services/storage_service.dart';
import 'public_profile_screen.dart';
import '../ui_library/components/buttons/teq_button.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  List<dynamic> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return buildApiHeaders(token, json: true);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(
        Uri.parse('$kBaseUrl/users/blocked'),
        headers: await _headers(),
      );
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _blocked = jsonDecode(resp.body) as List;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String username, int userId) async {
    try {
      final resp = await http.delete(
        Uri.parse('$kBaseUrl/users/${Uri.encodeComponent(username)}/block'),
        headers: await _headers(),
      );
      if ((resp.statusCode == 200 || resp.statusCode == 404) && mounted) {
        setState(() => _blocked.removeWhere((u) => u['id'] == userId));
      }
    } catch (_) {
      if (mounted) {
        TeqSnackBar.show(message: ref.read(localizationProvider).t('blockedActionFailed'), type: TeqSnackBarType.info);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(loc.t('blockedUsersTitle')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _blocked.isEmpty
              ? Center(
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
                )
              : ListView.separated(
                  itemCount: _blocked.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppColors.divider(context)),
                  itemBuilder: (_, i) {
                    final u = _blocked[i] as Map<String, dynamic>;
                    final name = (u['full_name'] as String?) ??
                        (u['username'] as String?) ??
                        '?';
                    final username = u['username'] as String? ?? '';
                    final rawImg = u['profile_image_url'] as String?;
                    final initial =
                        name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return ListTile(
                      leading: GestureDetector(
                        key: Key('blocked_avatar_${u['id']}'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: username),
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
                            builder: (_) =>
                                PublicProfileScreen(username: username),
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
                            fontSize: 12,
                            color: AppColors.textSecondary(context)),
                      ),
                      trailing: TeqButton.outline(
                        key: Key('blocked_btn_engel_kaldir_${u['id']}'),
                        onPressed: () => _unblock(username, u['id'] as int),
                        text: loc.t('blockedUnblock'),
                        size: TeqButtonSize.small,
                        customColor: const Color(0xFFEF4444),
                      ),
                    );
                  },
                ),
    );
  }
}
