import 'package:flutter/material.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:slider_button/slider_button.dart';
import '../../../core/models/ad.dart';

class ManualBidSheet extends StatelessWidget {
  final AdModel ad;
  final TextEditingController bidCtrl;
  final dynamic bidFormatter;
  final Future<void> Function() onConfirm;

  const ManualBidSheet({
    required this.ad,
    required this.bidCtrl,
    required this.bidFormatter,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        top: 32,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Özel Teklif Ver', 
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: bidCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [bidFormatter],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00B4CC)),
              decoration: const InputDecoration(
                hintText: 'Miktar Girin',
                border: InputBorder.none,
                prefixText: '₺ ',
              ),
            ),
          ),
          const SizedBox(height: 32),
          SliderButton(
            action: () async {
              await Haptics.vibrate(HapticsType.heavy);
              await onConfirm();
              if (context.mounted) Navigator.pop(context);
              return true;
            },
            label: const Text(
              "Onaylamak için Kaydır",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            icon: const Icon(Icons.check, color: Color(0xFF00B4CC)),
            width: double.infinity,
            radius: 30,
            buttonColor: Colors.white,
            backgroundColor: const Color(0xFF00B4CC),
          ),
        ],
      ),
    );
  }
}
