import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareService {
  /// İçerik paylaşım bottom sheet'ini gösterir.
  ///
  /// [url]       — paylaşılacak web URL'i
  /// [text]      — URL ile birlikte gönderilecek metin
  /// [imageUrl]  — Instagram Story için kullanılacak görsel (opsiyonel)
  /// [origin]    — iOS iPad popup konumu (opsiyonel)
  static Future<void> show(
    BuildContext context, {
    required String url,
    required String text,
    String? imageUrl,
    Rect? origin,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        url: url,
        text: text,
        imageUrl: imageUrl,
        origin: origin,
      ),
    );
  }

  // ── Paylaşım eylemleri ───────────────────────────────────────────

  static Future<void> shareToInstagramStory(
    BuildContext context, {
    required String url,
    required String text,
    String? imageUrl,
    Rect? origin,
  }) async {
    if (imageUrl != null) {
      try {
        final file = await _downloadImage(imageUrl);
        if (file != null) {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: '$text\n$url',
            sharePositionOrigin: origin,
          );
          return;
        }
      } catch (_) {}
    }
    // Görsel yoksa veya indirilemezse native sheet aç
    await _shareNative(text: '$text\n$url', origin: origin);
  }

  static Future<void> shareToWhatsApp({
    required String url,
    required String text,
  }) async {
    final encoded = Uri.encodeComponent('$text\n$url');
    final waUrl = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl);
    } else {
      // WhatsApp yüklü değil → native share
      await _shareNative(text: '$text\n$url');
    }
  }

  static Future<void> copyLink(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link kopyalandı'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<void> shareOther({
    required String url,
    required String text,
    Rect? origin,
  }) async {
    await _shareNative(text: '$text\n$url', origin: origin);
  }

  // ── Yardımcılar ──────────────────────────────────────────────────

  static Future<void> _shareNative({required String text, Rect? origin}) async {
    await Share.share(text, sharePositionOrigin: origin);
  }

  static Future<File?> _downloadImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/teqlif_share_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } catch (_) {
      return null;
    }
  }
}

// ── Bottom Sheet Widget ──────────────────────────────────────────────────────

class _ShareSheet extends StatelessWidget {
  final String url;
  final String text;
  final String? imageUrl;
  final Rect? origin;

  const _ShareSheet({
    required this.url,
    required this.text,
    this.imageUrl,
    this.origin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Paylaş',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          // Seçenekler
          _ShareOption(
            icon: _instagramIcon(),
            label: 'Instagram Story',
            subtitle: 'Story\'ne görsel olarak ekle',
            onTap: () async {
              Navigator.of(context).pop();
              await ShareService.shareToInstagramStory(
                context,
                url: url,
                text: text,
                imageUrl: imageUrl,
                origin: origin,
              );
            },
          ),
          _ShareOption(
            icon: const _WhatsAppIcon(),
            label: 'WhatsApp',
            subtitle: 'Doğrudan WhatsApp\'a gönder',
            onTap: () async {
              Navigator.of(context).pop();
              await ShareService.shareToWhatsApp(url: url, text: text);
            },
          ),
          _ShareOption(
            icon: const Icon(Icons.copy_rounded, size: 28, color: Color(0xFF6B7280)),
            label: 'Link Kopyala',
            subtitle: url,
            onTap: () async {
              Navigator.of(context).pop();
              await ShareService.copyLink(context, url);
            },
          ),
          _ShareOption(
            icon: const Icon(Icons.ios_share_rounded, size: 28, color: Color(0xFF6B7280)),
            label: 'Diğer...',
            subtitle: 'Tüm uygulamaları göster',
            onTap: () async {
              Navigator.of(context).pop();
              await ShareService.shareOther(url: url, text: text, origin: origin);
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ],
      ),
    );
  }

  Widget _instagramIcon() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final Widget icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 36, height: 36,
                child: Center(child: icon)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9CA3AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB), size: 20),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFF25D366),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.chat_rounded, color: Colors.white, size: 16),
    );
  }
}
