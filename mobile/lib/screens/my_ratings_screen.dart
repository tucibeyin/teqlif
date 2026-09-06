import 'viewmodels/my_ratings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../services/localization_service.dart';
import '../widgets/ratings/expandable_comment.dart';
import 'public_profile_screen.dart';

class MyRatingsScreen extends ConsumerStatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  ConsumerState<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends ConsumerState<MyRatingsScreen> {
  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(myRatingsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: AppBar(
          backgroundColor: AppColors.surface(context),
          foregroundColor: AppColors.textPrimary(context),
          elevation: 0,
          title: Text(loc.t('settingsMyRatings'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            labelColor: kPrimary,
            unselectedLabelColor: AppColors.textSecondary(context),
            indicatorColor: kPrimary,
            tabs: [
              Tab(text: loc.t('tabRatingsReceived')),
              Tab(text: loc.t('tabRatingsGiven')),
            ],
          ),
        ),
        body: stateAsync.when(
          data: (state) => TabBarView(
            children: [
              _buildList(state.receivedRatings, isReceived: true),
              _buildList(state.givenRatings, isReceived: false),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Hata: $e')),
        ),
      ),
    );
  }

  Widget _buildList(List<dynamic> ratings, {required bool isReceived}) {
    if (ratings.isEmpty) {
      return Center(
        child: Text(
          isReceived
              ? 'Henüz değerlendirme almadınız.'
              : 'Henüz değerlendirme yapmadınız.',
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
        return _RatingCard(
          key: ValueKey(item['id']),
          ratingId: item['id'] as int,
          userObj: userObj,
          score: item['score'] as int? ?? 0,
          comment: item['comment'] as String?,
          reply: item['reply'] as String?,
          repliedAt: item['replied_at'] as String?,
          dateStr: item['created_at'] as String?,
          updatedAt: item['updated_at'] as String?,
          history: (item['history'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          isReceived: isReceived,
          ratedUserId: isReceived ? null : (item['rated']?['id'] as int?),
        );
      },
    );
  }
}

// ── Rating Card ──────────────────────────────────────────────────────────────

class _RatingCard extends ConsumerStatefulWidget {
  final int ratingId;
  final dynamic userObj;
  final int score;
  final String? comment;
  final String? reply;
  final String? repliedAt;
  final String? dateStr;
  final String? updatedAt;
  final List<Map<String, dynamic>> history;
  final bool isReceived;
  final int? ratedUserId; // sadece given tab (isReceived=false) için dolu
  

  const _RatingCard({
    super.key,
    required this.ratingId,
    required this.userObj,
    required this.score,
    required this.comment,
    required this.reply,
    required this.repliedAt,
    required this.dateStr,
    required this.updatedAt,
    required this.history,
    required this.isReceived,
    required this.ratedUserId,
    
  });

  @override
  ConsumerState<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends ConsumerState<_RatingCard> {
  bool _historyExpanded = false;
  bool _replyFormVisible = false;
  final _replyCtrl = TextEditingController();
  bool _replySending = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  void _goToProfile() {
    if (widget.userObj == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PublicProfileScreen(username: widget.userObj['username']),
      ),
    );
  }

  Future<void> _openEditSheet() async {
    final ratedId = widget.ratedUserId;
    if (ratedId == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditRatingSheet(
        userId: ratedId,
        existingScore: widget.score,
        existingComment: widget.comment,
      ),
    );
  }

  Future<void> _submitReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _replySending = true);
    final success = await ref.read(myRatingsProvider.notifier).submitReply(widget.ratingId, text);
    if (mounted) {
      setState(() => _replySending = false);
      if (success) {
        setState(() {
          _replyFormVisible = false;
          _replyCtrl.clear();
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.userObj;
    if (u == null) return const SizedBox.shrink();

    final username = u['username'] as String? ?? '';
    final fullName = u['full_name'] as String? ?? username;
    final avatarUrl = u['profile_image_url'] as String?;
    final hasComment = widget.comment != null && widget.comment!.isNotEmpty;
    final hasReply = widget.reply != null && widget.reply!.isNotEmpty;
    final hasHistory = widget.history.isNotEmpty;
    final dateText = _formatDate(widget.dateStr);

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
          // ── Header ──────────────────────────────────────────────────────
          InkWell(
            onTap: _goToProfile,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: kPrimary.withValues(alpha: 0.1),
                    backgroundImage: avatarUrl != null
                        ? CachedNetworkImageProvider(imgUrl(avatarUrl))
                        : null,
                    child: avatarUrl == null
                        ? Text(
                            fullName.isNotEmpty
                                ? fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kPrimary,
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
                            i < widget.score
                                ? Icons.star
                                : Icons.star_border,
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
                  // Düzenle butonu (sadece verilen değerlendirmelerde)
                  if (!widget.isReceived) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _openEditSheet,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Yorum ───────────────────────────────────────────────────────
          if (hasComment) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ExpandableComment(text: widget.comment!),
            ),
          ],

          // ── Yanıt (var olan) ─────────────────────────────────────────
          if (hasReply) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.reply,
                      size: 14,
                      color: AppColors.textTertiary(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.reply!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Yanıtla butonu (sadece alınan değerlendirmelerde) ────────
          if (widget.isReceived && !hasReply) ...[
            const Divider(height: 1, thickness: 1),
            if (!_replyFormVisible)
              TextButton.icon(
                onPressed: () =>
                    setState(() => _replyFormVisible = true),
                icon: Icon(Icons.reply,
                    size: 14, color: AppColors.textSecondary(context)),
                label: Text(
                  'Yanıtla',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyCtrl,
                        maxLines: null,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: 'Yanıtınızı yazın...',
                          hintStyle: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: AppColors.border(context)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          isDense: true,
                          counterText: '',
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _replySending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kPrimary),
                          )
                        : IconButton(
                            onPressed: _submitReply,
                            icon: const Icon(Icons.send, color: kPrimary),
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => setState(() {
                        _replyFormVisible = false;
                        _replyCtrl.clear();
                      }),
                      icon: Icon(Icons.close,
                          color: AppColors.textTertiary(context)),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
          ],

          // ── Geçmiş (düzenlenmiş değerlendirmeler) ───────────────────
          if (hasHistory) ...[
            const Divider(height: 1, thickness: 1),
            InkWell(
              onTap: () =>
                  setState(() => _historyExpanded = !_historyExpanded),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.history,
                        size: 14,
                        color: AppColors.textTertiary(context)),
                    const SizedBox(width: 6),
                    Text(
                      'Düzenlendi (${widget.history.length}x)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _historyExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.textTertiary(context),
                    ),
                  ],
                ),
              ),
            ),
            if (_historyExpanded)
              ...widget.history.reversed.map((h) {
                final hScore = h['score'] as int? ?? 0;
                final hComment = h['comment'] as String?;
                final hDate = _formatDate(h['changed_at'] as String?);
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant(context),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                  ),
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Row(
                            children: List.generate(
                              5,
                              (i) => Icon(
                                i < hScore
                                    ? Icons.star
                                    : Icons.star_border,
                                color: const Color(0xFFEAB308),
                                size: 13,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            hDate,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ],
                      ),
                      if (hComment != null && hComment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          hComment,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
}

// ── Edit Rating Sheet ─────────────────────────────────────────────────────────

class _EditRatingSheet extends ConsumerStatefulWidget {
  final int userId;
  final int existingScore;
  final String? existingComment;

  const _EditRatingSheet({
    required this.userId,
    required this.existingScore,
    required this.existingComment,
  });

  @override
  ConsumerState<_EditRatingSheet> createState() => _EditRatingSheetState();
}

class _EditRatingSheetState extends ConsumerState<_EditRatingSheet> {
  late int _score;
  late final TextEditingController _commentCtrl;
  bool _saving = false;

  static const _labels = ['Çok kötü', 'Kötü', 'Orta', 'İyi', 'Mükemmel'];

  @override
  void initState() {
    super.initState();
    _score = widget.existingScore;
    _commentCtrl = TextEditingController(text: widget.existingComment ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final comment = _commentCtrl.text.trim();
    final success = await ref.read(myRatingsProvider.notifier).saveRating(widget.userId, _score, comment);
    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _score > 0 ? _labels[_score - 1] : '';

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 20,
        end: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Değerlendirmeyi Düzenle',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final idx = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _score = idx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    idx <= _score ? Icons.star : Icons.star_border,
                    color: const Color(0xFFEAB308),
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Yorumunuzu yazın... (isteğe bağlı)',
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: kPrimary, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _score == 0 || _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Güncelle',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
