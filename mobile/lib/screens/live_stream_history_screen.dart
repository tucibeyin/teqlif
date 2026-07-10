import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../config/theme.dart';
import '../l10n/app_localizations.dart';
import '../services/category_service.dart';
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

  // Filters
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _categoryFilter;
  DateTimeRange? _dateRange;
  List<(String, String)>? _categories;

  List<dynamic> get _filtered {
    var result = _streams;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) => (s['title'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_categoryFilter != null) {
      result = result.where((s) => s['category'] == _categoryFilter).toList();
    }
    if (_dateRange != null) {
      final start = _dateRange!.start;
      final end = _dateRange!.end.add(const Duration(days: 1));
      result = result.where((s) {
        final raw = s['started_at'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        return dt != null && !dt.isBefore(start) && dt.isBefore(end);
      }).toList();
    }
    return result;
  }

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) {
      CategoryService.getCategories(locale: Localizations.localeOf(context).languageCode)
          .then((cats) { if (mounted) setState(() => _categories = cats); });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
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

      final filtered = _filtered;

      bodyContent = Column(
        children: [
          // ── Arama + tarih + kategori ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: l.searchHintTextListing,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
                const SizedBox(height: 8),
                _buildDateRangePicker(l),
                const SizedBox(height: 8),
                _buildCategoryChips(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Horizontal Carousel
          SizedBox(
            height: 100,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length + 1 + (_hasMore ? 1 : 0),
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

                if (index == filtered.length + 1) {
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

                final s = filtered[index - 1];
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
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final s = filtered[index];
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

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  Widget _buildDateRangePicker(AppLocalizations l) {
    final hasRange = _dateRange != null;
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: _dateRange,
          locale: Localizations.localeOf(context),
        );
        if (picked != null) setState(() => _dateRange = picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: hasRange ? kPrimary : AppColors.border(context)),
          borderRadius: BorderRadius.circular(8),
          color: hasRange ? kPrimary.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 16,
                color: hasRange ? kPrimary : AppColors.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasRange
                    ? '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'
                    : l.filterSelectDate,
                style: TextStyle(fontSize: 13,
                    color: hasRange ? kPrimary : AppColors.textSecondary(context)),
              ),
            ),
            if (hasRange)
              GestureDetector(
                onTap: () => setState(() => _dateRange = null),
                child: Icon(Icons.close, size: 16, color: kPrimary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final cats = _categories;
    if (cats == null || cats.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(AppLocalizations.of(context)!.filterAll, _categoryFilter == null, () => setState(() => _categoryFilter = null)),
          ...cats.map((c) => _chip(c.$2, _categoryFilter == c.$1,
              () => setState(() => _categoryFilter = _categoryFilter == c.$1 ? null : c.$1))),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kPrimary : AppColors.card(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? kPrimary : AppColors.border(context)),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.textPrimary(context),
              )),
        ),
      ),
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
