import 'package:flutter/material.dart';
import '../ui_library/components/buttons/teq_button.dart';
import '../ui_library/components/cards/teq_card.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/overlays/teq_bottom_sheet.dart';
import '../ui_library/components/overlays/teq_dialog.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/foundation/teq_spacing.dart';
import '../ui_library/foundation/teq_typography.dart';

class TeqTestScreen extends StatelessWidget {
  const TeqTestScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teq Design System Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(TeqSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Typography & Cards', style: TeqTypography.h2),
            const SizedBox(height: TeqSpacing.m),
            TeqCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Bu bir TeqCard başlığıdır (h3)',
                    style: TeqTypography.h3,
                  ),
                  SizedBox(height: TeqSpacing.xs),
                  Text(
                    'Bu bir gövde metnidir (bodyMedium). Kart bileşeni içerisindedir.',
                    style: TeqTypography.bodyMedium,
                  ),
                ],
              ),
            ),

            const SizedBox(height: TeqSpacing.xl),
            const Text('Buttons', style: TeqTypography.h2),
            const SizedBox(height: TeqSpacing.m),
            TeqButton(text: 'Primary Button', onPressed: () {}),
            const SizedBox(height: TeqSpacing.m),
            TeqButton(
              text: 'Primary Loading',
              isLoading: true,
              onPressed: () {},
            ),
            const SizedBox(height: TeqSpacing.m),
            TeqButton.outline(text: 'Outline Button', onPressed: () {}),
            const SizedBox(height: TeqSpacing.m),
            TeqButton.text(text: 'Text Button', onPressed: () {}),

            const SizedBox(height: TeqSpacing.xl),
            const Text('Inputs', style: TeqTypography.h2),
            const SizedBox(height: TeqSpacing.m),
            const TeqTextField(
              labelText: 'Email',
              hintText: 'ornek@teqlif.com',
            ),
            const SizedBox(height: TeqSpacing.m),
            const TeqTextField(
              labelText: 'Şifre',
              obscureText: true,
              errorText: 'Şifre çok kısa',
            ),

            const SizedBox(height: TeqSpacing.xl),
            const Text('Overlays', style: TeqTypography.h2),
            const SizedBox(height: TeqSpacing.m),
            TeqButton(
              text: 'Show SnackBar',
              onPressed: () {
                TeqSnackBar.show(message: 'Bu bir başarılı işlemdir!',
                  type: TeqSnackBarType.success,
                );
              },
            ),
            const SizedBox(height: TeqSpacing.m),
            TeqButton(
              text: 'Show Dialog',
              onPressed: () {
                TeqDialog.show(
                  context: context,
                  title: 'Emin misiniz?',
                  message: 'Bu işlemi geri alamayacaksınız.',
                  primaryButtonText: 'Evet, Sil',
                  secondaryButtonText: 'İptal',
                  isDestructive: true,
                  onPrimaryPressed: () => Navigator.of(context).pop(),
                );
              },
            ),
            const SizedBox(height: TeqSpacing.m),
            TeqButton(
              text: 'Show Bottom Sheet',
              onPressed: () {
                TeqBottomSheet.show(
                  context: context,
                  title: 'Seçenekler',
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.share),
                        title: const Text('Paylaş'),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.report),
                        title: const Text('Şikayet Et'),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: TeqSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
