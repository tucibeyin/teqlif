import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../utils/error_helper.dart';
import 'public_profile_screen.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  bool _loading = true;
  List<dynamic> _receivedRequests = [];
  List<dynamic> _sentRequests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final futures = await Future.wait([
        http.get(
          Uri.parse('$kBaseUrl/follows/requests'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse('$kBaseUrl/follows/requests/sent'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      if (mounted) {
        if (futures[0].statusCode == 200) {
          _receivedRequests = jsonDecode(futures[0].body) as List;
        }
        if (futures[1].statusCode == 200) {
          _sentRequests = jsonDecode(futures[1].body) as List;
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleReceivedAction(int followerId, String action) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final uri = Uri.parse('$kBaseUrl/follows/$followerId/$action');
      final resp = await http.post(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        setState(() {
          _receivedRequests.removeWhere((req) => req['id'] == followerId);
        });
      } else {
        if (mounted) showErrorSnackbar(context, "Hata oluştu.");
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  Future<void> _handleSentWithdraw(int targetUserId) async {
    try {
      final token = await StorageService.getToken();
      if (token == null) return;
      final uri = Uri.parse('$kBaseUrl/follows/$targetUserId');
      final resp = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        setState(() {
          _sentRequests.removeWhere((req) => req['id'] == targetUserId);
        });
      } else {
        if (mounted) showErrorSnackbar(context, "İptal edilemedi.");
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    }
  }

  void _goToProfile(String username) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(username: username),
      ),
    ).then((_) => _loadRequests());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          title: Text(l.followRequests),
          centerTitle: true,
          elevation: 0,
          backgroundColor: AppColors.surface(context),
          foregroundColor: AppColors.textPrimary(context),
          bottom: TabBar(
            labelColor: const Color(0xFF6366F1), // or kPrimary
            unselectedLabelColor: AppColors.textSecondary(context),
            indicatorColor: const Color(0xFF6366F1),
            tabs: [
              Tab(text: l.tabFollowRequestsReceived),
              Tab(text: l.tabFollowRequestsSent),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildReceivedList(l),
                  _buildSentList(l),
                ],
              ),
      ),
    );
  }

  Widget _buildReceivedList(AppLocalizations l) {
    if (_receivedRequests.isEmpty) {
      return Center(
        child: Text(
          l.noFollowRequests,
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _receivedRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = _receivedRequests[index];
        final String username = user['username'];
        final String fullName = user['full_name'];
        final String? avatarUrl = user['profile_image_thumb_url'];

        return _buildUserCard(
          username: username,
          fullName: fullName,
          avatarUrl: avatarUrl,
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => _handleReceivedAction(user['id'], 'accept'),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(l.acceptRequest, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _handleReceivedAction(user['id'], 'reject'),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surfaceVariant(context),
                  foregroundColor: AppColors.textPrimary(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: Text(l.rejectRequest, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSentList(AppLocalizations l) {
    if (_sentRequests.isEmpty) {
      return Center(
        child: Text(
          "Gönderilen istek yok.",
          style: TextStyle(color: AppColors.textSecondary(context), fontSize: 16),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sentRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = _sentRequests[index];
        final String username = user['username'];
        final String fullName = user['full_name'];
        final String? avatarUrl = user['profile_image_thumb_url'];

        return _buildUserCard(
          username: username,
          fullName: fullName,
          avatarUrl: avatarUrl,
          actions: TextButton(
            onPressed: () => _handleSentWithdraw(user['id']),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant(context),
              foregroundColor: AppColors.textPrimary(context),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(l.withdrawRequest, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildUserCard({
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
          onTap: () => _goToProfile(username),
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
