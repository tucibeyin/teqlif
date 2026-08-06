// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart' show kPrimary;
import '../models/auction.dart';
import '../providers/auction_provider.dart';
import '../providers/direct_sale_provider.dart';
import '../services/localization_service.dart';
import 'auction_panel.dart';
import 'direct_sale_panel.dart';

/// Hangi commerce panelinin gösterileceğini belirler.
/// _force* bayrakları host'un idle chip'ten panel açmasına izin verir;
/// provider state non-idle'a geçince bayrak artık etkisiz kalır.
enum _CommerceMode { idle, auction, directSale }

/// Açık artırma ve direkt satış panellerini tek noktadan yöneten sarmalayıcı.
/// Aktif moda göre doğru paneli gösterir; her ikisi de boştayken idle şeridini
/// görüntüler. Host/viewer ayrımı içeride ilgili widget'a aktarılır.
class CommercePanelWrapper extends ConsumerStatefulWidget {
  // ── Ortak ──────────────────────────────────────────────────────────────────
  final int streamId;
  final bool isHost;

  // ── Auction ─────────────────────────────────────────────────────────────────
  final void Function(String bidder, double amount, String? itemName)? onBidAdded;
  final VoidCallback? onAuctionReset;
  final bool enabled;
  final bool isCoHost;
  final int? hostUserId;
  final String? myUsername;
  final VoidCallback? onAuctionWin;

  // ── Direct Sale ──────────────────────────────────────────────────────────────
  final VoidCallback? onDirectSaleWin;

  // ── Proof image capture (ikisi de kullanır) ──────────────────────────────────
  final Future<String?> Function()? captureProofImage;

  const CommercePanelWrapper({
    super.key,
    required this.streamId,
    required this.isHost,
    this.onBidAdded,
    this.onAuctionReset,
    this.enabled = true,
    this.isCoHost = false,
    this.hostUserId,
    this.myUsername,
    this.onAuctionWin,
    this.onDirectSaleWin,
    this.captureProofImage,
  });

  @override
  ConsumerState<CommercePanelWrapper> createState() => _CommercePanelWrapperState();
}

class _CommercePanelWrapperState extends ConsumerState<CommercePanelWrapper> {
  // Host idle chip'inden panel açmak için geçici bayraklar.
  // Provider state non-idle'a geçince bunlara bakılmaz (mode naturally güncellenir).
  bool _forceAuction = false;
  bool _forceDirectSale = false;

  bool get _isHostLike => widget.isHost || widget.isCoHost;

  @override
  Widget build(BuildContext context) {
    // Provider state non-idle'a geçince force bayraklarını temizle.
    // ref.listen build() içinde çağrılır ama Riverpod bunu güvenli yönetir —
    // mutation build sırasında değil, bir sonraki frame'de tetiklenir.
    ref.listen<AuctionState>(auctionProvider(widget.streamId), (_, next) {
      if (_forceAuction && !next.isIdle) {
        setState(() => _forceAuction = false);
      }
    });
    ref.listen<DirectSaleState>(directSaleHostProvider(widget.streamId), (_, next) {
      if (_forceDirectSale && !next.isIdle && !next.isTerminal) {
        setState(() => _forceDirectSale = false);
      }
    });

    final auctionState = ref.watch(auctionProvider(widget.streamId));
    final dsState = ref.watch(directSaleHostProvider(widget.streamId));
    final mode = _resolveMode(auctionState, dsState);

    return switch (mode) {
      _CommerceMode.auction => AuctionPanel(
          streamId: widget.streamId,
          isHost: widget.isHost,
          isCoHost: widget.isCoHost,
          enabled: widget.enabled,
          hostUserId: widget.hostUserId,
          myUsername: widget.myUsername,
          onBidAdded: widget.onBidAdded,
          onAuctionReset: () {
            widget.onAuctionReset?.call();
            setState(() => _forceAuction = false);
          },
          onWin: widget.onAuctionWin,
          captureProofImage: widget.captureProofImage,
        ),
      _CommerceMode.directSale => DirectSalePanel(
          streamId: widget.streamId,
          saleId: dsState.saleId,
          isHost: _isHostLike,
          captureProofImage: widget.captureProofImage,
          onSaleEnded: () => setState(() => _forceDirectSale = false),
          onWin: widget.onDirectSaleWin,
        ),
      _CommerceMode.idle => _IdleChip(
          isHost: _isHostLike,
          onStartAuction: () => setState(() => _forceAuction = true),
          onStartDirectSale: () => setState(() => _forceDirectSale = true),
        ),
    };
  }

  _CommerceMode _resolveMode(AuctionState auctionState, DirectSaleState dsState) {
    // Force bayrakları: host paneli henüz başlamamışken açmak için
    if (_forceDirectSale) return _CommerceMode.directSale;
    if (_forceAuction) return _CommerceMode.auction;

    // Direct sale öncelikli — aynı anda ikisi aktif olmamalı ama guard ekle
    if (!dsState.isIdle && !dsState.isTerminal) return _CommerceMode.directSale;
    if (!auctionState.isIdle) return _CommerceMode.auction;
    return _CommerceMode.idle;
  }
}

// ── Idle şeridi ──────────────────────────────────────────────────────────────

class _IdleChip extends ConsumerWidget {
  final bool isHost;
  final VoidCallback onStartAuction;
  final VoidCallback onStartDirectSale;

  const _IdleChip({
    required this.isHost,
    required this.onStartAuction,
    required this.onStartDirectSale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(localizationProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isHost
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.gavel_rounded,
                  label: loc.t('commerceSelectAuction'),
                  onTap: onStartAuction,
                ),
                const SizedBox(width: 12),
                _ActionButton(
                  icon: Icons.sell_outlined,
                  label: loc.t('commerceSelectDirectSale'),
                  onTap: onStartDirectSale,
                ),
              ],
            )
          : Text(
              loc.t('directSaleIdleChip'),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: kPrimary.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
