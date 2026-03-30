import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Ekranın sağ altından başlayıp yukarı doğru kavisli uçan, yavaşça
/// kaybolan kalp animasyonları yöneticisi.
///
/// Dışarıdan [GlobalKey<FloatingHeartsState>] üzerinden tetiklenir:
/// ```dart
/// final _heartsKey = GlobalKey<FloatingHeartsState>();
/// // ...
/// FloatingHearts(key: _heartsKey)
/// // ...
/// _heartsKey.currentState?.addHeart();
/// ```
///
/// RAM güvenliği: Ekranda aynı anda en fazla [maxHearts] kalp bulunur.
/// Animasyonu biten kalpler List'ten çıkarılır.
class FloatingHearts extends StatefulWidget {
  /// Aynı anda ekranda bulunabilecek maksimum kalp sayısı.
  final int maxHearts;

  const FloatingHearts({super.key, this.maxHearts = 25});

  @override
  State<FloatingHearts> createState() => FloatingHeartsState();
}

class FloatingHeartsState extends State<FloatingHearts>
    with TickerProviderStateMixin {
  final List<_HeartParticle> _hearts = [];
  final _rng = Random();

  /// Yeni bir kalp ekler.
  ///
  /// [isLocal] true → ana tema rengi (#06B6D4 / kPrimary benzeri).
  /// [isLocal] false → başka izleyicilerden gelen: rastgele canlı renk.
  void addHeart({bool isLocal = true}) {
    if (!mounted) return;

    // Maksimum sayıyı aşıyorsa en eskisini dispose edip çıkar
    if (_hearts.length >= widget.maxHearts) {
      final oldest = _hearts.removeAt(0);
      oldest.dispose();
    }

    final color = isLocal ? _kLocalColor : _randomRemoteColor();
    final driftX = (_rng.nextDouble() - 0.5) * 60; // –30..+30 px yatay sapma
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    final particle = _HeartParticle(
      id: DateTime.now().microsecondsSinceEpoch ^ _rng.nextInt(99999),
      color: color,
      driftX: driftX,
      scale: 0.8 + _rng.nextDouble() * 0.6, // 0.8..1.4
      ctrl: ctrl,
    );

    _hearts.add(particle);

    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (!mounted) return;
        setState(() {
          _hearts.removeWhere((h) => h.id == particle.id);
          particle.dispose();
        });
      }
    });

    ctrl.forward();

    // setState burada — yeni kalbi ekrana yansıt
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final h in _hearts) {
      h.dispose();
    }
    _hearts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Her zaman Positioned.fill döndür — non-positioned↔positioned geçişi
    // parent Stack'te layout reset'e neden oluyor.
    return Positioned.fill(
      child: IgnorePointer(
        child: _hearts.isEmpty
            ? const SizedBox.shrink()
            : Stack(
                children:
                    _hearts.map((h) => _HeartWidget(particle: h)).toList(),
              ),
      ),
    );
  }

  Color _randomRemoteColor() {
    const colors = [
      Color(0xFFFF4081), // pembe
      Color(0xFFFF6B6B), // mercan
      Color(0xFFFFD700), // altın
      Color(0xFF64FFDA), // turkuaz
      Color(0xFFE040FB), // mor
      Color(0xFFFF9100), // turuncu
      Color(0xFF69F0AE), // yeşil
    ];
    return colors[_rng.nextInt(colors.length)];
  }

  static const _kLocalColor = Color(0xFF06B6D4); // kPrimary
}

// ── Tek kalp verisi ──────────────────────────────────────────────────────────

class _HeartParticle {
  final int id;
  final Color color;
  final double driftX;
  final double scale;
  final AnimationController ctrl;

  _HeartParticle({
    required this.id,
    required this.color,
    required this.driftX,
    required this.scale,
    required this.ctrl,
  });

  void dispose() {
    ctrl.dispose();
  }
}

// ── Tek kalp widget'ı ────────────────────────────────────────────────────────

class _HeartWidget extends StatelessWidget {
  final _HeartParticle particle;
  const _HeartWidget({required this.particle});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // Sağ alttan biraz içeriden başlat
      right: 28,
      bottom: 120,
      child: AnimatedBuilder(
        animation: particle.ctrl,
        builder: (_, __) {
          final t = particle.ctrl.value; // 0.0 → 1.0

          // Yukarı hareketi: 0 → 200 px
          final dy = -t * 200;

          // Sinüs tabanlı yatay salınım
          final dx = particle.driftX * sin(t * pi);

          // Ölçek: 0→0.3'te büyü (pop), 0.7→1.0'da küçül
          final double scaleVal;
          if (t < 0.15) {
            scaleVal = particle.scale * (t / 0.15);
          } else if (t > 0.7) {
            scaleVal = particle.scale * (1.0 - (t - 0.7) / 0.3);
          } else {
            scaleVal = particle.scale;
          }

          // Opaklık: 0.6'ya kadar tam, sonra yavaş sil
          final opacity = t < 0.6 ? 1.0 : 1.0 - ((t - 0.6) / 0.4).clamp(0.0, 1.0);

          return Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scaleVal.clamp(0.0, 2.0),
                child: Icon(
                  Icons.favorite,
                  color: particle.color,
                  size: 32,
                  shadows: const [
                    Shadow(color: Colors.black38, blurRadius: 6),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
