import 'package:flutter/material.dart';
import '../services/localization_service.dart';

/// Generic proof capture bottom sheet — auction ve direct sale tarafından
/// ortaklaşa kullanılır.
///
/// Return contract:
///   non-empty String → fotoğraf URL'i
///   ''               → skip (fotoğrafsız devam)
///   null             → iptal (isDismissible:false olduğu için normalde olmaz)
Future<String?> showProofCaptureSheet(
  BuildContext context, {
  required Future<String?> Function() captureProofImage,
  required TranslationPack loc,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.80),
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ProofCaptureBody(
      captureProofImage: captureProofImage,
      loc: loc,
    ),
  );
}

class _ProofCaptureBody extends StatefulWidget {
  final Future<String?> Function() captureProofImage;
  final TranslationPack loc;

  const _ProofCaptureBody({
    required this.captureProofImage,
    required this.loc,
  });

  @override
  State<_ProofCaptureBody> createState() => _ProofCaptureBodyState();
}

class _ProofCaptureBodyState extends State<_ProofCaptureBody> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '📷 ${loc.t("hostAcceptSaleDialogTitle")}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withValues(alpha: 0.15),
              border: Border.all(
                color: const Color(0xFFEA580C).withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.camera_alt, color: Color(0xFFEA580C), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.t('hostAcceptSaleDialogBody'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFEA580C)),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    setState(() => _loading = true);
                    try {
                      final url = await widget.captureProofImage();
                      if (context.mounted) Navigator.pop(context, url ?? '');
                    } catch (_) {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
                  child: Text(
                    loc.t('hostAcceptSaleBtnCapture'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF475569)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(
                    loc.t('hostAcceptSaleBtnSkip'),
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
