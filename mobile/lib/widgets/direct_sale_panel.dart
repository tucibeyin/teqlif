// ignore_for_file: use_build_context_synchronously
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api.dart';
import '../config/theme.dart' show kPrimary;
import '../models/direct_sale.dart';
import '../providers/direct_sale_provider.dart';
import '../services/analytics_service.dart';
import '../services/direct_sale_service.dart';
import '../services/localization_service.dart';
import '../utils/number_formatter.dart';
import 'swipe_paginated_list.dart';

class DirectSalePanel extends ConsumerStatefulWidget {
  final int streamId;
  final int saleId; // 0 → start formu göster (host)
  final bool isHost;
  final Future<String?> Function()? captureProofImage;
  final VoidCallback? onSaleEnded;
  final VoidCallback? onWin;

  const DirectSalePanel({
    super.key,
    required this.streamId,
    required this.saleId,
    required this.isHost,
    this.captureProofImage,
    this.onSaleEnded,
    this.onWin,
  });

  @override
  ConsumerState<DirectSalePanel> createState() => _DirectSalePanelState();
}

class _DirectSalePanelState extends ConsumerState<DirectSalePanel> {
  bool _impressionFired = false;

  @override
  void initState() {
    super.initState();
    // Panel mount edildiğinde provider terminal state'teyse sıfırla.
    // CommercePanelWrapper bu paneli yalnızca "yeni satış başlat" amacıyla
    // açar; terminal state bu bağlamda geçersizdir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(directSaleHostProvider(widget.streamId));
      if (state.isTerminal) {
        ref.read(directSaleHostProvider(widget.streamId).notifier).reset();
      }
    });
  }

  // ── Dialog orchestration ───────────────────────────────────────────────────
  // API çağrıları ViewModel'de; View yalnızca dialog akışını yönetir.

  Future<void> _confirmEnd(BuildContext context) async {
    final loc = ref.read(localizationProvider);
    final notifier = ref.read(directSaleHostProvider(widget.streamId).notifier);
    final orderCount = await notifier.fetchOrderCount();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: loc.t('directSaleEndDialogTitle'),
        body: orderCount > 0
            ? loc.t('directSaleEndDialogBody', {'count': orderCount.toString()})
            : loc.t('directSaleEndDialogBodyNoOrders'),
        confirmLabel: loc.t('directSaleEndBtn'),
        confirmColor: Colors.redAccent,
      ),
    );
    if (confirmed == true) {
      await notifier.end(loc);
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final loc = ref.read(localizationProvider);
    final notifier = ref.read(directSaleHostProvider(widget.streamId).notifier);
    final orderCount = await notifier.fetchOrderCount();
    if (!context.mounted) return;

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(loc: loc, orderCount: orderCount),
    );
    if (result != null) {
      await notifier.cancel(loc, ordersVoided: result == 'void');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Yalnızca terminal'e ilk geçişte onSaleEnded tetiklenir (her rebuild'de değil).
    ref.listen<DirectSaleState>(directSaleHostProvider(widget.streamId), (prev, next) {
      if (next.isTerminal && !(prev?.isTerminal ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSaleEnded?.call();
        });
      }
      // Viewer'ın satışı ilk gördüğü an — impression (Faz 5.3)
      if (!widget.isHost && !_impressionFired && !next.isIdle && next.saleId > 0) {
        _impressionFired = true;
        AnalyticsService.logInteraction(
          itemId: next.saleId,
          itemType: 'direct_sale',
          interactionType: 'sale_impression',
          pricePoint: next.price,
        );
      }
    });

    final dsState = ref.watch(directSaleHostProvider(widget.streamId));
    final loc = ref.watch(localizationProvider);

    if (dsState.isTerminal) {
      return _TerminalBanner(state: dsState, loc: loc);
    }

    if (dsState.isIdle && widget.isHost) {
      return _StartFormTrigger(
        streamId: widget.streamId,
        hostUserId: null,
        captureProofImage: widget.captureProofImage,
      );
    }

    if (!dsState.isIdle) {
      return _ActivePanel(
        state: dsState,
        isHost: widget.isHost,
        onPause: () => ref
            .read(directSaleHostProvider(widget.streamId).notifier)
            .pause(ref.read(localizationProvider)),
        onResume: () => ref
            .read(directSaleHostProvider(widget.streamId).notifier)
            .resume(ref.read(localizationProvider)),
        onEnd: (ctx) => _confirmEnd(ctx),
        onCancel: (ctx) => _confirmCancel(ctx),
        onBuy: () => _showBuySheet(context, dsState),
      );
    }

    return const SizedBox.shrink();
  }

  void _showBuySheet(BuildContext context, DirectSaleState state) {
    AnalyticsService.logInteraction(
      itemId: state.saleId,
      itemType: 'direct_sale',
      interactionType: 'purchase_intent',
      pricePoint: state.price,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PurchaseSheet(
        streamId: widget.streamId,
        state: state,
        onWin: widget.onWin,
      ),
    );
  }
}

// ── Start Form ────────────────────────────────────────────────────────────────

class _StartFormTrigger extends ConsumerStatefulWidget {
  final int streamId;
  final int? hostUserId;
  final Future<String?> Function()? captureProofImage;

  const _StartFormTrigger({
    required this.streamId,
    required this.hostUserId,
    required this.captureProofImage,
  });

  @override
  ConsumerState<_StartFormTrigger> createState() => _StartFormTriggerState();
}

class _StartFormTriggerState extends ConsumerState<_StartFormTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openForm();
    });
  }

  Future<void> _openForm() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StartDialog(
        streamId: widget.streamId,
        hostUserId: widget.hostUserId,
        captureProofImage: widget.captureProofImage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
          const SizedBox(width: 8),
          Text(
            loc.t('directSaleFormTitle'),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Active Panel ───────────────────────────────────────────────────────────────

class _ActivePanel extends ConsumerWidget {
  final DirectSaleState state;
  final bool isHost;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final void Function(BuildContext) onEnd;
  final void Function(BuildContext) onCancel;
  final VoidCallback onBuy;

  const _ActivePanel({
    required this.state,
    required this.isHost,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    required this.onCancel,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Ürün kartı ──────────────────────────────────────────────────
          Row(
            children: [
              if (state.displayImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imgUrl(state.displayImageUrl),
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.image_not_supported,
                      color: Colors.white38,
                      size: 52,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₺ ${TeqNumberFormatter.format(state.price, fieldKey: 'price')}',
                      style: const TextStyle(
                        color: kPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(state: state, loc: loc),
                  const SizedBox(height: 4),
                  Text(
                    '${state.remainingStock}/${state.totalStock}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),

          if (state.isSoldOut)
            _Banner(
              text: loc.t('directSaleSoldOutBanner'),
              color: Colors.green,
            ),

          if (state.isPaused)
            _Banner(
              text: loc.t('directSalePausedLabel'),
              color: Colors.orange,
            ),

          const SizedBox(height: 8),

          if (isHost) ...[
            Row(
              children: [
                if (state.isActive)
                  _HostBtn(
                    label: loc.t('directSalePauseBtn'),
                    color: Colors.orange,
                    onTap: onPause,
                  ),
                if (state.isPaused)
                  _HostBtn(
                    label: loc.t('directSaleResumeBtn'),
                    color: Colors.green,
                    onTap: onResume,
                  ),
                if (!state.isSoldOut) ...[
                  const SizedBox(width: 6),
                  _HostBtn(
                    label: loc.t('directSaleEndBtn'),
                    color: Colors.redAccent,
                    onTap: () => onEnd(context),
                  ),
                ],
                const SizedBox(width: 6),
                _HostBtn(
                  label: loc.t('directSaleCancelBtn'),
                  color: Colors.grey,
                  onTap: () => onCancel(context),
                ),
              ],
            ),
          ] else if (state.canPurchase) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onBuy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  loc.t('directSaleBuyBtn'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Banner ─────────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final String text;
  final Color color;

  const _Banner({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color == Colors.green ? Colors.greenAccent : Colors.orange,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Terminal Banner ────────────────────────────────────────────────────────────

class _TerminalBanner extends StatelessWidget {
  final DirectSaleState state;
  final TranslationPack loc;

  const _TerminalBanner({required this.state, required this.loc});

  @override
  Widget build(BuildContext context) {
    final msg = state.isEnded
        ? switch (state.endReason) {
            'sold_out' => loc.t('directSaleEndedSoldOut'),
            'host_ended' => loc.t('directSaleEndedByHost'),
            _ => loc.t('directSaleEndedStreamClosed'),
          }
        : loc.t('directSaleCancelledNeutral');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        msg,
        style: const TextStyle(color: Colors.white54, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final DirectSaleState state;
  final TranslationPack loc;

  const _StatusBadge({required this.state, required this.loc});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state.status) {
      'active' => (loc.t('directSaleStatusActive'), Colors.green),
      'paused' => (loc.t('directSaleStatusPaused'), Colors.orange),
      'sold_out' => (loc.t('directSaleStatusSoldOut'), Colors.green),
      _ => (loc.t('directSaleStatusEnded'), Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Host Buton ────────────────────────────────────────────────────────────────

class _HostBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _HostBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ── Confirm Dialog ────────────────────────────────────────────────────────────

class _ConfirmDialog extends ConsumerWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(body, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            loc.t('cancel'),
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// ── Cancel Dialog ─────────────────────────────────────────────────────────────

class _CancelDialog extends ConsumerWidget {
  final TranslationPack loc;
  final int orderCount;

  const _CancelDialog({required this.loc, required this.orderCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: Text(
        loc.t('directSaleCancelDialogTitle'),
        style: const TextStyle(color: Colors.white),
      ),
      content: Text(
        orderCount > 0
            ? loc.t('directSaleCancelDialogBody', {'count': orderCount.toString()})
            : loc.t('directSaleCancelDialogBodyNoOrders'),
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(loc.t('cancel'), style: const TextStyle(color: Colors.white54)),
        ),
        if (orderCount > 0) ...[
          TextButton(
            onPressed: () => Navigator.pop(context, 'void'),
            child: Text(
              loc.t('directSaleCancelVoidOrders'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: Text(
              loc.t('directSaleCancelKeepOrders'),
              style: const TextStyle(color: Colors.greenAccent),
            ),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.pop(context, 'confirm'),
            child: Text(
              loc.t('directSaleCancelBtn'),
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Purchase Bottom Sheet ─────────────────────────────────────────────────────

class _PurchaseSheet extends ConsumerStatefulWidget {
  final int streamId;
  final DirectSaleState state;
  final VoidCallback? onWin;

  const _PurchaseSheet({
    required this.streamId,
    required this.state,
    required this.onWin,
  });

  @override
  ConsumerState<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends ConsumerState<_PurchaseSheet> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final viewerState = ref.watch(directSaleViewerProvider(widget.streamId));
    final liveStock = ref.watch(directSaleHostProvider(widget.streamId)).remainingStock;
    final maxQty = liveStock.clamp(1, 10);
    final total = _qty * widget.state.price;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.t('directSaleBuySheetTitle'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.state.displayImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imgUrl(widget.state.displayImageUrl),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.image, color: Colors.white38, size: 48),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.state.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '₺ ${TeqNumberFormatter.format(widget.state.price, fieldKey: 'price')}',
                style: const TextStyle(
                  color: kPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                loc.t('directSaleBuySheetQuantity'),
                style: const TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              _QtyBtn(
                icon: Icons.remove,
                onTap: _qty > 1 ? () => setState(() => _qty--) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '$_qty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _QtyBtn(
                icon: Icons.add,
                onTap: _qty < maxQty ? () => setState(() => _qty++) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                loc.t('directSaleBuySheetTotal'),
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                '₺ ${TeqNumberFormatter.format(total, fieldKey: 'price')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: viewerState.isLoading
                  ? null
                  : () async {
                      await ref
                          .read(directSaleViewerProvider(widget.streamId).notifier)
                          .purchase(
                            widget.state.saleId,
                            _qty,
                            ref.read(localizationProvider),
                          );
                      if (ref
                          .read(directSaleViewerProvider(widget.streamId))
                          .isPurchaseSuccess) {
                        widget.onWin?.call();
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: viewerState.isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      loc.t('directSaleBuySheetConfirm'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null
              ? kPrimary.withOpacity(0.8)
              : Colors.grey.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ── Start Dialog ──────────────────────────────────────────────────────────────

class _StartDialog extends ConsumerStatefulWidget {
  final int streamId;
  final int? hostUserId;
  final Future<String?> Function()? captureProofImage;

  const _StartDialog({
    required this.streamId,
    required this.hostUserId,
    required this.captureProofImage,
  });

  @override
  ConsumerState<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends ConsumerState<_StartDialog> {
  bool _fromListing = false;
  Map<String, dynamic>? _selectedListing;
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  bool _loading = false;
  String? _formError;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchListings(int offset) =>
      DirectSaleService.fetchListingsForDialog(
        hostUserId: widget.hostUserId,
        offset: offset,
      );

  Future<void> _submit() async {
    final loc = ref.read(localizationProvider);
    setState(() { _loading = true; _formError = null; });

    String? proofUrl;
    if (widget.captureProofImage != null) {
      final confirmed = await _showProofDialog(loc);
      if (confirmed == false) {
        setState(() => _loading = false);
        return;
      }
      proofUrl = confirmed as String?;
    }

    if (_fromListing) {
      if (_selectedListing == null) {
        setState(() { _loading = false; _formError = loc.t('directSaleFormValidationError'); });
        return;
      }
      await ref.read(directSaleHostProvider(widget.streamId).notifier).startSale(
            widget.streamId,
            listingId: _selectedListing!['id'] as int,
            proofImageUrl: proofUrl,
            loc: loc,
          );
    } else {
      final title = _titleCtrl.text.trim();
      final price = double.tryParse(_priceCtrl.text.trim());
      final stock = int.tryParse(_stockCtrl.text.trim());
      if (title.isEmpty || price == null || stock == null || stock < 1) {
        setState(() { _loading = false; _formError = loc.t('directSaleFormValidationError'); });
        return;
      }
      await ref.read(directSaleHostProvider(widget.streamId).notifier).startSale(
            widget.streamId,
            title: title,
            price: price,
            stock: stock,
            proofImageUrl: proofUrl,
            loc: loc,
          );
    }

    setState(() => _loading = false);
    if (context.mounted) Navigator.pop(context);
  }

  Future<dynamic> _showProofDialog(TranslationPack loc) {
    return showDialog<dynamic>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          loc.t('directSaleProofDialogTitle'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          loc.t('directSaleProofDialogBody'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              loc.t('cancel'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              final url = await widget.captureProofImage!();
              if (context.mounted) Navigator.pop(context, url);
            },
            child: Text(
              loc.t('directSaleStartBtn'),
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      scrollable: true,
      title: Text(
        loc.t('directSaleFormTitle'),
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      contentPadding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _modeBtn(
                    loc.t('directSaleFormManual'),
                    !_fromListing,
                    () => setState(() {
                      _fromListing = false;
                      _selectedListing = null;
                      _formError = null;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _modeBtn(
                    loc.t('directSaleFormSelectListing'),
                    _fromListing,
                    () => setState(() { _fromListing = true; _formError = null; }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_fromListing)
              SwipePaginatedList<Map<String, dynamic>>(
                fetchPage: _fetchListings,
                itemHeight: 64,
                itemBuilder: (ctx, item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item['title'] as String? ?? '',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    item['price'] != null
                        ? '₺${item['price']}'
                        : loc.t('directSaleFormNoListing'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  selected: _selectedListing?['id'] == item['id'],
                  selectedTileColor: kPrimary.withOpacity(0.1),
                  onTap: () => setState(() => _selectedListing = item),
                ),
                emptyWidget: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    loc.t('directSaleFormNoListing'),
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              _field(loc.t('directSaleFormProductTitle'), _titleCtrl),
              const SizedBox(height: 8),
              _field(loc.t('directSaleFormPrice'), _priceCtrl, number: true),
              const SizedBox(height: 8),
              _field(loc.t('directSaleFormStock'), _stockCtrl, number: true),
              const SizedBox(height: 8),
              _SuggestionChip(
                priceCtrl: _priceCtrl,
                stockCtrl: _stockCtrl,
                onApply: () => setState(() {}),
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(
                _formError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            loc.t('cancel'),
            style: const TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  loc.t('directSaleStartBtn'),
                  style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _modeBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active ? kPrimary.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: active ? kPrimary : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? kPrimary : Colors.white54,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool number = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: kPrimary),
          borderRadius: BorderRadius.circular(8),
        ),
        isDense: true,
      ),
    );
  }
}

// ── Faz 6 — Fiyat + stok öneri chip'i ────────────────────────────────────────

class _SuggestionChip extends ConsumerWidget {
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  final VoidCallback onApply;

  const _SuggestionChip({
    required this.priceCtrl,
    required this.stockCtrl,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);
    final async = ref.watch(directSaleSuggestionsProvider(0));

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        if (!s.hasData) return const SizedBox.shrink();

        final priceStr = TeqNumberFormatter.format(s.suggestedPrice!, fieldKey: 'price');
        final stockStr = s.recommendedStock != null ? '${s.recommendedStock}' : null;

        String label = loc.t('directSaleSuggestionPrice', {'price': priceStr});
        if (stockStr != null) {
          label += '  ·  ${loc.t('directSaleSuggestionStock', {'stock': stockStr})}';
        }

        return GestureDetector(
          onTap: () {
            priceCtrl.text = s.suggestedPrice!.toStringAsFixed(2);
            if (s.recommendedStock != null) {
              stockCtrl.text = '${s.recommendedStock}';
            }
            onApply();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.08),
              border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: kPrimary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: kPrimary, fontSize: 12),
                  ),
                ),
                Text(
                  loc.t('directSaleSuggestionApply'),
                  style: const TextStyle(
                    color: kPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
