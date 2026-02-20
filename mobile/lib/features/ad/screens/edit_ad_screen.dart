import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/models/ad.dart';
import '../../home/screens/home_screen.dart';

class EditAdScreen extends ConsumerStatefulWidget {
  final String adId;
  const EditAdScreen({super.key, required this.adId});

  @override
  ConsumerState<EditAdScreen> createState() => _EditAdScreenState();
}

class _EditAdScreenState extends ConsumerState<EditAdScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  AdModel? _ad;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAd() async {
    try {
      final res = await ApiClient().get(Endpoints.adById(widget.adId));
      final ad = AdModel.fromJson(res.data as Map<String, dynamic>);
      setState(() {
        _ad = ad;
        _titleCtrl.text = ad.title;
        _descCtrl.text = ad.description;
        _priceCtrl.text = ad.price.toStringAsFixed(0);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient().patch(Endpoints.adById(widget.adId), data: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text),
      });
      ref.invalidate(adsProvider(const FilterState()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('İlan güncellendi! ✅')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('İlanı Düzenle')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Başlık'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Açıklama'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Piyasa Değeri (₺)',
                  prefixIcon: Icon(Icons.monetization_on_outlined)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
