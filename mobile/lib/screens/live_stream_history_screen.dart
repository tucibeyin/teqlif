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
  State<LiveStreamHistoryScreen> createState() => _LiveStreamHistoryScreenState();
}

class _LiveStreamHistoryScreenState extends State<LiveStreamHistoryScreen> {
  List<dynamic> _streams = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final token = await StorageService.getToken();
      final resp = await http.get(
        Uri.parse('$kBaseUrl/streams/my-history'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        if (mounted) {
          setState(() {
            _streams = jsonDecode(resp.body) as List;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final bodyContent = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _hasError
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary(context)),
                    const SizedBox(height: 16),
                    Text(l.proLoadError, style: TextStyle(color: AppColors.textSecondary(context))),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _fetchHistory, child: Text(l.btnRetry)),
                  ],
                ),
              )
            : _streams.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off, size: 64, color: AppColors.textSecondary(context).withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(l.proToolStreamHistoryEmpty, style: TextStyle(color: AppColors.textSecondary(context))),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
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
                            final dt = DateTime.parse(startedAtStr).toLocal();
                            dateStr = DateFormat('dd MMM yyyy HH:mm').format(dt);
                          } catch (_) {}
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppColors.card(context),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border(context)),
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
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LiveStreamAnalyticsScreen(streamId: s['id']),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.podcasts, color: Colors.white),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Text(dateStr, style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('${rev.toStringAsFixed(0)} TUCi', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF22C55E))),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.visibility, size: 12, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text('$viewers', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                    );

    if (widget.isEmbedded) {
      return bodyContent;
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(l.proToolStreamHistoryTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.bg(context),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHistory)
        ],
      ),
      body: bodyContent,
    );
  }
}
