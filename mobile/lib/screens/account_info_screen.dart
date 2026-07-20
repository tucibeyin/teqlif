import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import '../config/api.dart';
import '../config/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/phone_input_field.dart';
import '../ui_library/components/overlays/teq_snackbar.dart';
import '../ui_library/components/inputs/teq_text_field.dart';
import '../ui_library/components/buttons/teq_button.dart';

class AccountInfoScreen extends StatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  State<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends State<AccountInfoScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kullanıcı tarayıcıdan (telefon doğrulama linki) uygulamaya döndüğünde yenile
    if (state == AppLifecycleState.resumed) _loadUser();
  }

  Future<void> _loadUser() async {
    if (_user == null) {
      setState(() => _loading = true);
    }
    try {
      final u = await AuthService.me();
      if (mounted) {
        setState(() {
          _user = {
            'id': u.id,
            'email': u.email,
            'username': u.username,
            'full_name': u.fullName,
            'phone': u.phone,
            'phone_verified': u.phoneVerified,
          };
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        TeqSnackBar.show(
          context,
          message: AppLocalizations.of(context)!.errorGenericRetry,
          type: TeqSnackBarType.error,
        );
      }
    }
  }

  void _reload() => _loadUser();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        title: Text(l.accountInfoTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading && _user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUser,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                _SectionCard(
                  title: l.accountInfoSecuritySection,
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.email_outlined,
                        label: l.accountInfoEmail,
                        value: _user?['email'] as String? ?? '',
                        verified: true,
                        onTap: () => _showEmailChangeSheet(),
                      ),
                      const Divider(height: 1, indent: 16),
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        label: l.accountInfoPhone,
                        value: _user?['phone'] as String? ?? l.accountInfoPhoneEmpty,
                        verified: _user?['phone_verified'] as bool? ?? false,
                        onTap: () => _showPhoneSheet(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showEmailChangeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EmailChangeSheet(
        currentEmail: _user?['email'] as String? ?? '',
        onChanged: _reload,
      ),
    );
  }

  void _showPhoneSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PhoneSheet(
        currentPhone: _user?['phone'] as String?,
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
          padding: const EdgeInsets.only(left: 4, bottom: 8),
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

class _InfoRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
              child: Text(AppLocalizations.of(context)!.accountInfoUnverified, style: const TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.w600)),
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

class _EmailChangeSheet extends StatefulWidget {
  final String currentEmail;
  final VoidCallback onChanged;
  const _EmailChangeSheet({required this.currentEmail, required this.onChanged});

  @override
  State<_EmailChangeSheet> createState() => _EmailChangeSheetState();
}

class _EmailChangeSheetState extends State<_EmailChangeSheet> {
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
    final l = AppLocalizations.of(context)!;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l.accountInfoNewEmail);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/email-change/request'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'new_email': email}),
      );
      if (!mounted) return;
      if (resp.statusCode == 202) {
        setState(() { _codeSent = true; _loading = false; });
      } else {
        final msg = (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Hata';
        setState(() { _error = msg; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = AppLocalizations.of(context)!.accountInfoConnectError; _loading = false; });
    }
  }

  Future<void> _verifyCode() async {
    final l = AppLocalizations.of(context)!;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = l.accountInfoVerifyCode);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/email-change/verify'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'new_email': _emailCtrl.text.trim(), 'code': code}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.pop(context);
        widget.onChanged();
        TeqSnackBar.show(
          context,
          message: l.accountInfoEmailUpdated,
          type: TeqSnackBarType.success,
        );
      } else {
        final msg = (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Hata';
        setState(() { _error = msg; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = AppLocalizations.of(context)!.accountInfoConnectError; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 32),
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
          Text(l.accountInfoEmailChangeTitle, style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            l.accountInfoEmailCurrent(widget.currentEmail),
            style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
          ),
          const SizedBox(height: 20),
          TeqTextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            readOnly: _codeSent,
            labelText: l.accountInfoNewEmail,
            prefixIcon: Icon(Icons.email_outlined, size: 18, color: AppColors.iconColor(context)),
            onChanged: (_) { if (_error != null) setState(() => _error = null); },
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TeqTextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              labelText: l.accountInfoVerifyCode,
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
            text: _codeSent ? l.accountInfoVerifyCodeBtn : l.accountInfoSendCode,
            onPressed: _loading ? null : (_codeSent ? _verifyCode : _requestCode),
            isLoading: _loading,
            isExpanded: true,
          ),
          if (_codeSent) ...[
            const SizedBox(height: 8),
            Center(
              child: TeqButton.text(
                text: l.accountInfoDifferentEmail,
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
// Phone sheet (reuses the same email-based verification flow)
// ---------------------------------------------------------------------------

class _PhoneSheet extends StatefulWidget {
  final String? currentPhone;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  const _PhoneSheet({this.currentPhone, required this.onChanged, required this.onClose});

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet> {
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
    if (phone == null || phone.length < 8) {
      setState(() => _error = AppLocalizations.of(context)!.accountInfoPhone);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final token = await StorageService.getToken();
      final resp = await http.post(
        Uri.parse('$kBaseUrl/auth/phone-verify/request'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'phone': phone}),
      );
      if (!mounted) return;
      if (resp.statusCode == 202) {
        setState(() { _sent = true; _loading = false; });
      } else {
        final msg = (jsonDecode(resp.body) as Map<String, dynamic>)['detail'] as String? ?? 'Hata';
        setState(() { _error = msg; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = AppLocalizations.of(context)!.accountInfoConnectError; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 32),
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
            Text(l.accountInfoEmailSent, style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              l.accountInfoEmailSentDesc,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13, height: 1.55),
            ),
            const SizedBox(height: 28),
            TeqButton(
              text: l.accountInfoOk,
              onPressed: () { Navigator.pop(context); widget.onChanged(); },
              isExpanded: true,
            ),
          ] else ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.currentPhone != null ? l.accountInfoPhoneChangeTitle : l.accountInfoPhoneAddTitle,
                style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.currentPhone != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l.accountInfoPhoneCurrent(widget.currentPhone!),
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
              text: l.accountInfoPhoneSendVerify,
              onPressed: _loading ? null : _send,
              isLoading: _loading,
              isExpanded: true,
            ),
            const SizedBox(height: 10),
            TeqButton.text(
              text: l.accountInfoCancel,
              onPressed: widget.onClose,
            ),
          ],
        ],
      ),
    );
  }
}
