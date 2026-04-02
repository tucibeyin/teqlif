import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/bid_calculator.dart';

/// Yatay ListWheelScrollView ile kompakt teklif çarkı.
/// Ortadaki eleman büyütülür, kenarlar soluklaştırılır.
class SmartBidPicker extends StatefulWidget {
  final int currentHighestBid;
  final void Function(int) onBidSelected;

  const SmartBidPicker({
    super.key,
    required this.currentHighestBid,
    required this.onBidSelected,
  });

  @override
  State<SmartBidPicker> createState() => _SmartBidPickerState();
}

class _SmartBidPickerState extends State<SmartBidPicker> {
  static const int _count = 50;
  static const double _itemExtent = 92.0;
  static const double _pickerHeight = 108.0;

  late List<int> _bids;
  late FixedExtentScrollController _scrollCtrl;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _bids = generateNextBids(widget.currentHighestBid, _count);
    _scrollCtrl = FixedExtentScrollController(initialItem: 0);
    // İlk seçimi dışarı bildir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onBidSelected(_bids[0]);
    });
  }

  @override
  void didUpdateWidget(SmartBidPicker old) {
    super.didUpdateWidget(old);
    if (old.currentHighestBid != widget.currentHighestBid) {
      _bids = generateNextBids(widget.currentHighestBid, _count);
      _selectedIndex = 0;
      _scrollCtrl.jumpToItem(0);
      widget.onBidSelected(_bids[0]);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _pickerHeight,
      child: RotatedBox(
        quarterTurns: -1, // Çarkı yatay çevir
        child: ListWheelScrollView.useDelegate(
          controller: _scrollCtrl,
          itemExtent: _itemExtent,
          perspective: 0.003,
          diameterRatio: 2.0,
          magnification: 1.28,
          useMagnifier: true,
          overAndUnderCenterOpacity: 0.38,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (index) {
            if (index == _selectedIndex) return;
            _selectedIndex = index;
            HapticFeedback.selectionClick();
            widget.onBidSelected(_bids[index]);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: _count,
            builder: (context, index) {
              final isSelected = index == _selectedIndex;
              final bid = _bids[index];
              final label = _formatBid(bid);

              return RotatedBox(
                quarterTurns: 1, // Metni tekrar düzelt
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: _itemExtent,
                  height: _pickerHeight,
                  alignment: Alignment.center,
                  decoration: isSelected
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: const Color(0xFF06B6D4).withValues(alpha: 0.70),
                              width: 2.5,
                            ),
                          ),
                        )
                      : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: isSelected ? 18 : 14,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.55),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TL',
                        style: TextStyle(
                          fontSize: isSelected ? 10 : 9,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF06B6D4)
                              : Colors.white.withValues(alpha: 0.30),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 1000'leri nokta ile ayırır: 1250 → "1.250"
String _formatBid(int value) {
  final s = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final remaining = s.length - i;
    if (i > 0 && remaining % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
