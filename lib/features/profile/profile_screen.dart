import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart' show User, MembershipSummary;
import '../../data/repository.dart';
import '../../widgets/widgets.dart';

const _appVersion = '1.0.0';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthYear(DateTime t) => '${_months[t.month - 1]} ${t.year}';

Future<void> _openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showToast(context, "Couldn't open $url", kind: ToastKind.error);
  }
}

/// Account screen: profile header, organizations, account actions, links,
/// about and sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.user));

    return Scaffold(
      backgroundColor: TF.bgBase,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: TF.brand,
          backgroundColor: TF.bgElevated,
          onRefresh: () => ref.read(authProvider.notifier).refreshUser(),
          child: user == null ? _loading() : _ProfileBody(user: user),
        ),
      ),
    );
  }

  Widget _loading() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: const [
        Skeleton(height: 24, width: 120),
        SizedBox(height: 16),
        Skeleton(height: 150, radius: TF.radiusLg),
        SizedBox(height: 16),
        Skeleton(height: 64, radius: TF.radiusLg),
        SizedBox(height: 10),
        Skeleton(height: 64, radius: TF.radiusLg),
      ],
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.user});
  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiHost = Uri.tryParse(AppConfig.apiBase)?.host ?? AppConfig.apiBase;

    final sections = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Eyebrow('Account'),
          const SizedBox(height: 4),
          Text('Profile', style: TFText.h1()),
        ]),
      ),
      _ProfileHeader(user: user),
      const SizedBox(height: 28),
      Eyebrow(
        'Organizations',
        trailing:
            Text('${user.memberships.length}', style: TFText.mono(size: 11)),
      ),
      const SizedBox(height: 10),
      if (user.memberships.isEmpty)
        TFCard(
          child: Row(children: [
            const Icon(Icons.apartment_rounded, size: 18, color: TF.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text("You're not a member of any organization yet.",
                  style: TFText.body(color: TF.textMuted)),
            ),
          ]),
        )
      else
        for (final m in user.memberships) ...[
          _MembershipTile(membership: m),
          const SizedBox(height: 8),
        ],
      const SizedBox(height: 20),
      const Eyebrow('Security & details'),
      const SizedBox(height: 10),
      _Group(children: [
        _RowTile(
          icon: Icons.edit_outlined,
          title: 'Edit profile',
          subtitle: 'Name, bio and timezone',
          onTap: () => showTFSheet<void>(context,
              builder: (_) => _EditProfileSheet(user: user)),
        ),
        _RowTile(
          icon: Icons.lock_outline_rounded,
          title: 'Change password',
          subtitle: 'Update your sign-in password',
          onTap: () => showTFSheet<void>(context,
              builder: (_) => const _ChangePasswordSheet()),
        ),
      ]),
      const SizedBox(height: 20),
      const Eyebrow('Resources'),
      const SizedBox(height: 10),
      _Group(children: [
        _RowTile(
          icon: Icons.open_in_browser_rounded,
          title: 'Open web app',
          subtitle: Uri.tryParse(AppConfig.webUrl)?.host ?? AppConfig.webUrl,
          trailingIcon: Icons.north_east_rounded,
          onTap: () => _openExternal(context, AppConfig.webUrl),
        ),
        _RowTile(
          icon: Icons.menu_book_outlined,
          title: 'Documentation',
          subtitle: 'Guides and API reference',
          trailingIcon: Icons.north_east_rounded,
          onTap: () => _openExternal(context, AppConfig.docsUrl),
        ),
      ]),
      const SizedBox(height: 20),
      const Eyebrow('About'),
      const SizedBox(height: 10),
      TFCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          const _KeyValue(label: 'App', value: 'TaskForge Mobile'),
          const Divider(),
          const _KeyValue(label: 'Version', value: _appVersion),
          const Divider(),
          _KeyValue(label: 'API host', value: apiHost),
        ]),
      ),
      const SizedBox(height: 28),
      TFButton(
        label: 'Sign out',
        icon: Icons.logout_rounded,
        variant: TFButtonVariant.danger,
        expand: true,
        onPressed: () async {
          final ok = await confirmDialog(
            context,
            title: 'Sign out?',
            message: "You'll need to sign in again to access your workspaces.",
            confirmLabel: 'Sign out',
            destructive: true,
          );
          if (ok) {
            HapticFeedback.mediumImpact();
            await ref.read(authProvider.notifier).logout();
          }
        },
      ),
      const SizedBox(height: 12),
      Center(
        child: Text('TaskForge v$_appVersion',
            style: TFText.mono(size: 10.5, color: TF.textDisabled)),
      ),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        for (var i = 0; i < sections.length; i++)
          sections[i]
              .animate()
              .fadeIn(
                  duration: 350.ms,
                  delay: (i < 14 ? i * 25 : 350).ms,
                  curve: TF.ease)
              .slideY(
                  begin: 0.06,
                  end: 0,
                  duration: 350.ms,
                  delay: (i < 14 ? i * 25 : 350).ms,
                  curve: TF.ease),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final User user;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGridBackground(
        glow: true,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: TF.borderBrand),
                  boxShadow: TF.shadowGlow,
                ),
                child: TFAvatar(
                    name: user.displayName, imageUrl: user.avatarUrl, size: 64),
              ).animate().scale(
                  begin: const Offset(0.85, 0.85),
                  duration: 450.ms,
                  curve: TF.easeBounce),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName,
                          style: TFText.h2(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: TFText.mono(size: 12, color: TF.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  user.isVerified
                      ? const TFBadge('Verified', color: TF.success, dot: true)
                      : const TFBadge('Unverified',
                          color: TF.warning, dot: true),
                  if (user.dateJoined != null)
                    TFBadge('Member since ${_monthYear(user.dateJoined!)}',
                        color: TF.textMuted),
                  TFBadge(user.timezone.isEmpty ? 'UTC' : user.timezone,
                      color: TF.info),
                ]),
            if (user.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(user.bio.trim(), style: TFText.body()),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MembershipTile extends StatelessWidget {
  const _MembershipTile({required this.membership});
  final MembershipSummary membership;

  @override
  Widget build(BuildContext context) {
    final m = membership;
    return TFCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap:
          m.orgSlug.isEmpty ? null : () => context.push('/orgs/${m.orgSlug}'),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: TF.brandLight,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border: Border.all(color: TF.borderBrand),
          ),
          child: Text(
            m.orgName.isEmpty ? '?' : m.orgName.substring(0, 1).toUpperCase(),
            style:
                TFText.mono(size: 15, weight: FontWeight.w700, color: TF.brand),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              m.orgName.isEmpty ? m.orgSlug : m.orgName,
              style: TFText.sans(size: 15, weight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              m.joinedAt != null
                  ? '/${m.orgSlug} · joined ${Fmt.short(m.joinedAt)}'
                  : '/${m.orgSlug}',
              style: TFText.mono(size: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 8),
        TFBadge.role(m.role),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right_rounded, size: 20, color: TF.textMuted),
      ]),
    );
  }
}

// ── Small building blocks ─────────────────────────────────────────────────────

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: 52),
          children[i],
        ],
      ]),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Icon(icon, size: 19, color: TF.textSecondary),
            const SizedBox(width: 19),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TFText.sans(size: 15, weight: FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TFText.small(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ]),
            ),
            Icon(trailingIcon, size: 18, color: TF.textMuted),
          ]),
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Text(label.toUpperCase(), style: TFText.eyebrow()),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TFText.mono(size: 12, color: TF.textSecondary),
          ),
        ),
      ]),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.eyebrow, required this.title});
  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Eyebrow(eyebrow),
      const SizedBox(height: 4),
      Text(title, style: TFText.h2()),
    ]);
  }
}

class _FormError extends StatelessWidget {
  const _FormError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TF.dangerLight,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.danger.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: TF.danger),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TFText.small(color: TF.danger))),
      ]),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .shakeX(hz: 4, amount: 3, duration: 300.ms);
  }
}

// ── Edit profile sheet ────────────────────────────────────────────────────────

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});
  final User user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  static const _commonZones = [
    'UTC',
    'America/New_York',
    'America/Los_Angeles',
    'Europe/London',
    'Europe/Berlin',
    'Asia/Karachi',
    'Asia/Dubai',
    'Asia/Kolkata',
    'Asia/Singapore',
    'Australia/Sydney',
  ];

  late final _first = TextEditingController(text: widget.user.firstName);
  late final _last = TextEditingController(text: widget.user.lastName);
  late final _bio = TextEditingController(text: widget.user.bio);
  late final _tz = TextEditingController(
      text: widget.user.timezone.isEmpty ? 'UTC' : widget.user.timezone);

  bool _saving = false;
  ApiError? _apiError;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _bio.dispose();
    _tz.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final first = _first.text.trim();
    final last = _last.text.trim();
    final tz = _tz.text.trim().isEmpty ? 'UTC' : _tz.text.trim();
    if (first.isEmpty) {
      setState(() => _error = 'First name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _apiError = null;
    });
    // Capture before awaiting: the sheet may be dismissed mid-request.
    final repo = ref.read(repositoryProvider);
    final auth = ref.read(authProvider.notifier);
    try {
      final updated = await repo.updateProfile({
        'first_name': first,
        'last_name': last,
        'bio': _bio.text.trim(),
        'timezone': tz,
      });
      auth.setUser(updated);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Profile updated');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e is ApiError) {
          _apiError = e;
          _error = e.errors.isEmpty ? e.friendly : null;
        } else {
          _error = errorMessage(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHeader(eyebrow: 'Profile', title: 'Edit profile'),
            const SizedBox(height: 20),
            if (_error != null) ...[
              _FormError(_error!),
              const SizedBox(height: 14)
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TFTextField(
                  label: 'First name',
                  controller: _first,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.givenName],
                  errorText: _apiError?.fieldError('first_name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TFTextField(
                  label: 'Last name',
                  controller: _last,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.familyName],
                  errorText: _apiError?.fieldError('last_name'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TFTextField(
              label: 'Bio',
              hint: 'A line or two about you',
              controller: _bio,
              maxLines: 4,
              minLines: 2,
              keyboardType: TextInputType.multiline,
              errorText: _apiError?.fieldError('bio'),
            ),
            const SizedBox(height: 14),
            TFTextField(
              label: 'Timezone',
              hint: 'e.g. Asia/Karachi',
              controller: _tz,
              prefixIcon: Icons.public_rounded,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => setState(() {}),
              errorText: _apiError?.fieldError('timezone'),
            ),
            const SizedBox(height: 10),
            ChoiceChips<String>(
              options: _commonZones,
              value: _commonZones.contains(_tz.text.trim())
                  ? _tz.text.trim()
                  : null,
              labelOf: (z) => z,
              onChanged: (z) => setState(() => _tz.text = z),
            ),
            const SizedBox(height: 24),
            TFButton(
              label: 'Save changes',
              icon: Icons.check_rounded,
              size: TFButtonSize.lg,
              expand: true,
              loading: _saving,
              onPressed: _save,
            ),
          ]),
    );
  }
}

// ── Change password sheet ─────────────────────────────────────────────────────

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _oldError;
  String? _newError;
  String? _confirmError;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _oldError = _old.text.isEmpty ? 'Enter your current password.' : null;
      _newError = _new.text.length < 8 ? 'Use at least 8 characters.' : null;
      _confirmError =
          _confirm.text != _new.text ? 'Passwords do not match.' : null;
    });
    if (_oldError != null || _newError != null || _confirmError != null) return;

    setState(() => _saving = true);
    // Capture before awaiting: the sheet may be dismissed mid-request.
    final repo = ref.read(repositoryProvider);
    final storage = ref.read(tokenStorageProvider);
    try {
      final res = await repo.changePassword(
        oldPassword: _old.text,
        newPassword: _new.text,
        confirm: _confirm.text,
      );
      // The backend re-issues a token pair; old tokens may be invalidated.
      final tokenMap = res['tokens'] is Map
          ? Map<String, dynamic>.from(res['tokens'] as Map)
          : res;
      final access = tokenMap['access'];
      if (access is String && access.isNotEmpty) {
        final refresh = tokenMap['refresh'];
        await storage.save(
          access: access,
          refresh: refresh is String && refresh.isNotEmpty ? refresh : null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Password changed');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e is ApiError) {
          _oldError = e.fieldError('old_password');
          _newError = e.fieldError('new_password');
          _confirmError = e.fieldError('new_password_confirm');
          final hasField =
              _oldError != null || _newError != null || _confirmError != null;
          if (!hasField) {
            // Wrong-password responses come back as a bare 400 without the
            // standard envelope.
            _error = e.status == 400 && e.message.startsWith('Request failed')
                ? 'Your current password is incorrect.'
                : e.friendly;
          }
        } else {
          _error = errorMessage(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: AutofillGroup(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHeader(eyebrow: 'Security', title: 'Change password'),
              const SizedBox(height: 6),
              Text("You'll stay signed in on this device.",
                  style: TFText.small()),
              const SizedBox(height: 20),
              if (_error != null) ...[
                _FormError(_error!),
                const SizedBox(height: 14)
              ],
              TFTextField(
                label: 'Current password',
                controller: _old,
                obscure: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.password],
                errorText: _oldError,
              ),
              const SizedBox(height: 14),
              TFTextField(
                label: 'New password',
                hint: 'At least 8 characters',
                controller: _new,
                obscure: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                errorText: _newError,
              ),
              const SizedBox(height: 14),
              TFTextField(
                label: 'Confirm new password',
                controller: _confirm,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _submit(),
                errorText: _confirmError,
              ),
              const SizedBox(height: 24),
              TFButton(
                label: 'Update password',
                icon: Icons.lock_reset_rounded,
                size: TFButtonSize.lg,
                expand: true,
                loading: _saving,
                onPressed: _submit,
              ),
            ]),
      ),
    );
  }
}
