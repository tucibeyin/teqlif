import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import '../utils/error_helper.dart';
import 'public_profile_screen.dart';

class MyRatingsScreen extends StatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen> {
  bool _isLoading = true;
  List<dynamic> _receivedRatings = [];
  List<dynamic> _givenRatings = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    final token = await StorageService.getToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$kBaseUrl/ratings/me/mark-read'),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final token = await StorageService.getToken();
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final futures = await Future.wait([
        http.get(
          Uri.parse('$kBaseUrl/ratings/me/received'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse('$kBaseUrl/ratings/me/given'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      if (mounted) {
        if (futures[0].statusCode == 200) {
          _receivedRatings = jsonDecode(futures[0].body);
        }
        if (futures[1].statusCode == 200) {
          _givenRatings = jsonDecode(futures[1].body);
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          backgroundColor: AppColors.surface(context),
          foregroundColor: AppColors.textPrimary(context),
          elevation: 0,
          title: Text(l.settingsMyRatings, style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: kPrimary,
            unselectedLabelColor: AppColors.textSecondary(context),
            indicatorColor: kPrimary,
            tabs: [
              Tab(text: l.tabRatingsReceived),
              Tab(text: l.tabRatingsGiven),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(_receivedRatings, isReceived: true),
                  _buildList(_givenRatings, isReceived: false),
                ],
              ),
      ),
    );
  }

  Widget _buildList(List<dynamic> ratings, {required bool isReceived}) {
    if (ratings.isEmpty) {
      return Center(
        child: Text(
          "Henüz değerlendirme yok.",
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ratings.length,
      itemBuilder: (context, index) {
        final item = ratings[index];
        final userObj = isReceived ? item['rater'] : item['rated'];
        final score = item['score'] as int? ?? 0;
        final comment = item['comment'] as String?;
        final date = item['created_at'] as String?;

        return _RatingCard(
          userObj: userObj,
          score: score,
          comment: comment,
          dateStr: date,
        );
      },
    );
  }
}

class _RatingCard extends StatefulWidget {
  final dynamic userObj;
  final int score;
  final String? comment;
  final String? dateStr;

  const _RatingCard({
    required this.userObj,
    required this.score,
    required this.comment,
    required this.dateStr,
  });

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  bool _isExpanded = false;

  void _goToProfile() {
    if (widget.userObj == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          username: widget.userObj['username'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.userObj;
    if (u == null) return const SizedBox.shrink();

    final username = u['username'];
    final fullName = u['full_name'];
    final avatarUrl = u['profile_image_url'];
    final hasComment = widget.comment != null && widget.comment!.isNotEmpty;

    String dateText = '';
    if (widget.dateStr != null) {
      try {
        final d = DateTime.parse(widget.dateStr!).toLocal();
        dateText = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (Clickable for Profile)
          InkWell(
            onTap: _goToProfile,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: kPrimary.withValues(alpha: 0.1),
                    backgroundImage: avatarUrl != null ? NetworkImage(imgUrl(avatarUrl)) : null,
                    child: avatarUrl == null
                        ? Text(
                            fullName[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) {
                          return Icon(
                            i < widget.score ? Icons.star : Icons.star_border,
                            color: const Color(0xFFEAB308),
                            size: 16,
                          );
                        }),
                      ),
                      if (dateText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          dateText,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Accordion Comment Section
          if (hasComment)
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: Column(
                children: [
                  const Divider(height: 1, thickness: 1),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        widget.comment!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary(context),
                          height: 1.4,
                        ),
                        maxLines: _isExpanded ? null : 2,
                        overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Icon(
                      _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.textTertiary(context),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
