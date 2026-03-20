import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/theme.dart';
import '../config/app_colors.dart';
import '../services/storage_service.dart';
import 'public_profile_screen.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<dynamic> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşlem gerçekleştirilemedi')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: const Text('Engellenen Kullanıcılar'),
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
                        'Engellenen kullanıcı yok',
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
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.divider(context)),
                  itemBuilder: (_, i) {
                    final u = _blocked[i] as Map<String, dynamic>;
                    final name = (u['full_name'] as String?) ??
                        (u['username'] as String?) ??
                        '?';
                    final username = u['username'] as String? ?? '';
                    final imgUrl = u['profile_image_url'] as String?;
                    final initial =
                        name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return ListTile(
                      leading: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PublicProfileScreen(username: username),
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: kPrimary.withOpacity(0.12),
                          backgroundImage:
                              imgUrl != null ? NetworkImage(imgUrl) : null,
                          child: imgUrl == null
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
                      trailing: OutlinedButton(
                        onPressed: () => _unblock(username, u['id'] as int),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          backgroundColor: const Color(0xFFFEF2F2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Engeli Kaldır',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
