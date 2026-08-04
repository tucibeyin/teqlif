import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../config/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization_service.dart';
import '../widgets/phone_input_field.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/buttons/teq_button.dart';
import 'viewmodels/account_info_view_model.dart';

class AccountInfoScreen extends ConsumerStatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  ConsumerState<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends ConsumerState<AccountInfoScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(accountInfoProvider.notifier).reload();
    }
  }

  void _reload() => ref.read(accountInfoProvider.notifier).reload();

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    final stateAsync = ref.watch(accountInfoProvider);
    
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        title: Text(loc.t('accountInfoTitle'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
      ),
      body: stateAsync.when(
        data: (state) {
          final user = state.user;
          if (user == null) return const Center(child: Text('Kullanıcı bilgisi bulunamadı.'));
          
          return RefreshIndicator(
            onRefresh: ref.read(accountInfoProvider.notifier).reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _SectionCard(
                  title: loc.t('accountInfoSecuritySection'),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.email_outlined,
                        label: loc.t('accountInfoEmail'),
                        value: user['email'] as String? ?? '',
                        verified: true,
                        onTap: () => _showEmailChangeSheet(user['email'] as String? ?? ''),
                      ),
                      const Divider(height: 1, indent: 16),
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        label: loc.t('accountInfoPhone'),
                        value: user['phone'] as String? ?? loc.t('accountInfoPhoneEmpty'),
                        verified: user['phone_verified'] as bool? ?? false,
                        onTap: () => _showPhoneSheet(user['phone'] as String?),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(loc.t('errorGenericRetry'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: ref.read(accountInfoProvider.notifier).reload,
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmailChangeSheet(String currentEmail) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EmailChangeSheet(
        currentEmail: currentEmail,
        onChanged: _reload,
      ),
    );
  }

  void _showPhoneSheet(String? currentPhone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PhoneSheet(
        currentPhone: currentPhone,
        onChanged: _reload,
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary(context),
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.hardEdge,
          child: child,
        ),
      ],
    );
  }
}

class _InfoRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool verified;
  final VoidCallback onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.verified,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(icon, color: AppColors.iconColor(context), size: 20),
      title: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary(context)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (verified) ...[
            const SizedBox(width: 6),
            const FaIcon(FontAwesomeIcons.circleCheck, color: Color(0xFF0D9488), size: 14),
          ] else ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(ref.read(localizationProvider).t('accountInfoUnverified'), style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Email change sheet
// ---------------------------------------------------------------------------

class _EmailChangeSheet extends ConsumerStatefulWidget {
  final String currentEmail;
  final VoidCallback onChanged;
  const _EmailChangeSheet({required this.currentEmail, required this.onChanged});

  @override
  ConsumerState<_EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends ConsumerState<_EmailChangeSheet> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final loc = ref.read(localizationProvider);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = loc.t('accountInfoNewEmail'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    
    final errStr = await ref.read(emailChangeProvider.notifier).requestCode(email);
    if (!mounted) return;
    
    if (errStr == null) {
      setState(() { _codeSent = true; _loading = false; });
    } else {
      final msg = errStr == 'network_error' ? loc.t('accountInfoConnectError') : errStr;
      setState(() { _error = msg; _loading = false; });
    }
  }

  Future<void> _verifyCode() async {
    final loc = ref.read(localizationProvider);
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = loc.t('accountInfoVerifyCode'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    
    final errStr = await ref.read(emailChangeProvider.notifier).verifyCode(_emailCtrl.text.trim(), code);
    if (!mounted) return;
    
    if (errStr == null) {
      Navigator.pop(context);
      widget.onChanged();
      TeqSnackBar.show(message: loc.t('accountInfoEmailUpdated'), type: TeqSnackBarType.success);
    } else {
      final msg = errStr == 'network_error' ? loc.t('accountInfoConnectError') : errStr;
      setState(() { _error = msg; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.border(context), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(loc.t('accountInfoEmailChangeTitle'), style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            loc.t('accountInfoEmailCurrent', {'email': widget.currentEmail}),
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
          ),
          const SizedBox(height: 20),
          TeqTextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            readOnly: _codeSent,
            labelText: loc.t('accountInfoNewEmail'),
            prefixIcon: Icon(Icons.email_outlined, size: 18, color: AppColors.iconColor(context)),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TeqTextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              labelText: loc.t('accountInfoVerifyCode'),
              prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppColors.iconColor(context)),
              onChanged: (_) { if (_error != null) setState(() => _error = null); },
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ],
          const SizedBox(height: 20),
          TeqButton(
            text: _codeSent ? loc.t('accountInfoVerifyCodeBtn') : loc.t('accountInfoSendCode'),
            onPressed: _loading ? null : (_codeSent ? _verifyCode : _requestCode),
            isLoading: _loading,
            isExpanded: true,
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            Center(
              child: TeqButton.text(
                text: loc.t('accountInfoDifferentEmail'),
                onPressed: _loading ? null : () => setState(() { _codeSent = false; _codeCtrl.clear(); _error = null; }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phone sheet
// ---------------------------------------------------------------------------

class _PhoneSheet extends ConsumerStatefulWidget {
  final String? currentPhone;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  const _PhoneSheet({this.currentPhone, required this.onChanged, required this.onClose});

  @override
  ConsumerState<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends ConsumerState<_PhoneSheet> {
  late String? _phoneE164;
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneE164 = widget.currentPhone;
  }

  Future<void> _send() async {
    final phone = _phoneE164;
    final loc = ref.read(localizationProvider);
    if (phone == null || phone.length < 8) {
      setState(() => _error = loc.t('accountInfoPhone'));
      return;
    }
    setState(() { _loading = true; _error = null; });
    
    final errStr = await ref.read(phoneChangeProvider.notifier).requestVerification(phone);
    if (!mounted) return;
    
    if (errStr == null) {
      setState(() { _sent = true; _loading = false; });
    } else {
      final msg = errStr == 'network_error' ? loc.t('accountInfoConnectError') : errStr;
      setState(() { _error = msg; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(localizationProvider);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppColors.border(context), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if (_sent) ...[
            const Icon(Icons.mark_email_read_outlined, color: Color(0xFF0D9488), size: 48),
            const SizedBox(height: 14),
            Text(loc.t('accountInfoEmailSent'), style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              loc.t('accountInfoEmailSentDesc'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13, height: 1.55),
            ),
            const SizedBox(height: 28),
            TeqButton(
              text: loc.t('accountInfoOk'),
              onPressed: () { Navigator.pop(context); widget.onChanged(); },
              isExpanded: true,
            ),
          ] else ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.currentPhone != null ? loc.t('accountInfoPhoneChangeTitle') : loc.t('accountInfoPhoneAddTitle'),
                style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.currentPhone != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  loc.t('accountInfoPhoneCurrent', {'phone': widget.currentPhone!}),
                  style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 20),
            PhoneInputField(
              initialE164: widget.currentPhone,
              errorText: _error,
              onChanged: (e164) => setState(() { _phoneE164 = e164; _error = null; }),
              onReset: () => setState(() => _phoneE164 = null),
            ),
            const SizedBox(height: 20),
            TeqButton(
              text: loc.t('accountInfoPhoneSendVerify'),
              onPressed: _loading ? null : _send,
              isLoading: _loading,
              isExpanded: true,
            ),
            const SizedBox(height: 10),
            TeqButton.text(
              text: loc.t('accountInfoCancel'),
              onPressed: widget.onClose,
            ),
          ],
        ],
      ),
    );
  }
}
