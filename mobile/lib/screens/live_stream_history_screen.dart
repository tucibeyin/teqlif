import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_service.dart';
import 'live_stream_analytics_screen.dart';

class LiveStreamHistoryScreen extends StatefulWidget {
  final bool isEmbedded;
  const LiveStreamHistoryScreen({super.key, this.isEmbedded = false});

  @override
  State<LiveStreamHistoryScreen> createState() =>
      _LiveStreamHistoryScreenState();
}

class _LiveStreamHistoryScreenState extends State<LiveStreamHistoryScreen> {
  List<dynamic> _streams = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasError = false;
  int? _selectedStreamId;
  String? _cursor;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50) {
        if (!_isLoading && !_isLoadingMore && _hasMore) {
          _fetchHistory(loadMore: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _streams.clear();
        _cursor = null;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final token = await StorageService.getToken();
      String url = '$kBaseUrl/streams/my-history?limit=20';
      if (_cursor != null) url += '&cursor=$_cursor';

      final resp = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (resp.statusCode == 200) {
        if (mounted) {
          final newStreams = jsonDecode(resp.body) as List;
          setState(() {
            if (newStreams.isNotEmpty) {
              _streams.addAll(newStreams);
              _cursor = newStreams.last['started_at'] as String?;
            }
            if (newStreams.length < 20) {
              _hasMore = false;
            }
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      } else {
        throw Exception('Failed to load');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!loadMore) _hasError = true;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    Widget bodyContent;
    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_hasError) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(height: 16),
            Text(
              l.proLoadError,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _fetchHistory, child: Text(l.btnRetry)),
          ],
        ),
      );
    } else if (_streams.isEmpty) {
      bodyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_toggle_off,
              size: 64,
              color: AppColors.textSecondary(context).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              l.proToolStreamHistoryEmpty,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      );
    } else {
      int totalViewers = 0;
      double totalRev = 0;
      for (var s in _streams) {
        totalViewers += (s['viewer_count'] as int? ?? 0);
        totalRev += (s['revenue'] as num? ?? 0);
      }

      bodyContent = Column(
        children: [
          const SizedBox(height: 16),
          // Horizontal Carousel
          SizedBox(
            height: 100,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _streams.length + 1 + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = _selectedStreamId == null;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedStreamId = null),
                    child: Container(
                      width: 90,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                            : AppColors.card(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : AppColors.border(context),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.podcasts,
                            color: isSelected
                                ? const Color(0xFF8B5CF6)
                                : AppColors.textSecondary(context),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.liveAllCategory,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6)
                                  : AppColors.textPrimary(context),
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (index == _streams.length + 1) {
                  return Container(
                    width: 50,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final s = _streams[index - 1];
                final sid = s['id'] as int;
                final isSelected = _selectedStreamId == sid;
                final title = s['title'] as String? ?? 'Untitled';

                return GestureDetector(
                  onTap: () => setState(() => _selectedStreamId = sid),
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                          : AppColors.card(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF8B5CF6)
                            : AppColors.border(context),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: 20,
                          color: AppColors.textSecondary(context),
                        ),
                        const Spacer(),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Details Area
          Expanded(
            child: _selectedStreamId != null
                ? LiveStreamAnalyticsScreen(
                    streamId: _selectedStreamId!,
                    isEmbedded: true,
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                l.analyticsRevenue,
                                '${totalRev.toStringAsFixed(0)} TUCi',
                                Icons.monetization_on,
                                const Color(0xFF22C55E),
                                context,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryCard(
                                l.audienceTotalViewers,
                                '$totalViewers',
                                Icons.visibility,
                                const Color(0xFF8B5CF6),
                                context,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _streams.length,
                          itemBuilder: (context, index) {
                            final s = _streams[index];
                            final startedAtStr = s['started_at'] as String?;
                            final title = s['title'] as String? ?? 'Untitled';
                            final viewers = s['viewer_count'] as int? ?? 0;
                            final rev = s['revenue'] as num? ?? 0;

                            String dateStr = '';
                            if (startedAtStr != null) {
                              try {
                                final dt = DateTime.parse(
                                  startedAtStr,
                                ).toLocal();
                                dateStr = DateFormat(
                                  'dd MMM yyyy HH:mm',
                                ).format(dt);
                              } catch (_) {}
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.card(context),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.border(context),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => setState(
                                    () => _selectedStreamId = s['id'],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF8B5CF6),
                                                Color(0xFF6366F1),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.podcasts,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                dateStr,
                                                style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary(
                                                        context,
                                                      ),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${rev.toStringAsFixed(0)} TUCi',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF22C55E),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.visibility,
                                                  size: 12,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$viewers',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    }

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(
          l.proToolStreamHistoryTitle,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHistory),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
    BuildContext context,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
