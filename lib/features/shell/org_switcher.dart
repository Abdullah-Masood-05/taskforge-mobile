import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';

// ── Shared org helpers ───────────────────────────────────────────────────────

/// Plan → colour (web Badge `free` / `pro` / `business` variants).
Color planColor(String? plan) => switch ((plan ?? 'free').toLowerCase()) {
      'pro' => TF.brand,
      'business' || 'enterprise' => TF.brandSecondary,
      _ => TF.textMuted,
    };

/// The signed-in user's role in [slug] from the `/auth/me/` memberships.
String? userRoleIn(User? user, String slug) {
  if (user == null) return null;
  for (final m in user.memberships) {
    if (m.orgSlug == slug) return m.role;
  }
  return null;
}

/// Normalises a user-entered website (adds https:// when no scheme given).
String normalizeWebsite(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return v;
  return v.startsWith(RegExp(r'https?://', caseSensitive: false))
      ? v
      : 'https://$v';
}

/// Validator for optional website fields.
String? validateWebsite(String? raw) {
  final v = normalizeWebsite(raw ?? '');
  if (v.isEmpty) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || !uri.hasAuthority || !uri.host.contains('.')) {
    return 'Enter a valid URL.';
  }
  return null;
}

/// Plan pill.
class PlanBadge extends StatelessWidget {
  const PlanBadge(this.plan, {super.key});
  final String plan;

  @override
  Widget build(BuildContext context) =>
      TFBadge(plan.isEmpty ? 'free' : plan, color: planColor(plan));
}

/// Square monogram for an organization.
class OrgMark extends StatelessWidget {
  const OrgMark(
      {super.key, required this.name, this.size = 28, this.active = false});
  final String name;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return AnimatedContainer(
      duration: TF.dur,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? TF.brandLight : TF.bgOverlay,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: active ? TF.borderBrand : TF.borderDefault),
      ),
      child: Text(
        initial,
        style: TFText.mono(
            size: size * 0.44,
            weight: FontWeight.w700,
            color: active ? TF.brand : TF.textSecondary),
      ),
    );
  }
}

// ── Switcher chip ────────────────────────────────────────────────────────────

/// Tappable chip showing the active organization. Opens a sheet to switch
/// orgs or create a new one. Safe to place in any Row (bounded or not).
class OrgSwitcher extends ConsumerWidget {
  const OrgSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeOrgProvider);
    final Widget child = active.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () =>
          const Skeleton(key: ValueKey('org-loading'), width: 150, height: 40),
      error: (_, __) => _SwitcherChip(
        key: const ValueKey('org-error'),
        leading: const Icon(Icons.refresh_rounded, size: 18, color: TF.danger),
        label: 'Retry organizations',
        onTap: () => ref.invalidate(orgsProvider),
      ),
      data: (org) => org == null
          ? _SwitcherChip(
              key: const ValueKey('org-none'),
              leading: const Icon(Icons.add_rounded, size: 18, color: TF.brand),
              label: 'Create organization',
              onTap: () => showCreateOrgSheet(context, ref),
            )
          : _SwitcherChip(
              key: ValueKey('org-${org.slug}'),
              leading: OrgMark(name: org.name, size: 26, active: true),
              label: org.name,
              onTap: () => showOrgSwitcherSheet(context, ref),
            ),
    );
    return AnimatedSwitcher(
      duration: TF.dur,
      switchInCurve: TF.ease,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      child: child,
    );
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip(
      {super.key,
      required this.leading,
      required this.label,
      required this.onTap});
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double maxLabel = constraints.maxWidth.isFinite
          ? (constraints.maxWidth - 72).clamp(40.0, 420.0).toDouble()
          : 200.0;
      return Pressable(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 7, right: 9),
          decoration: BoxDecoration(
            color: TF.bgElevated,
            borderRadius: BorderRadius.circular(TF.radiusMd),
            border: Border.all(color: TF.borderDefault),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            leading,
            const SizedBox(width: 9),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxLabel),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TFText.sans(size: 14, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.unfold_more_rounded,
                size: 16, color: TF.textMuted),
          ]),
        ),
      );
    });
  }
}

// ── Switcher sheet ───────────────────────────────────────────────────────────

const _createAction = '__create__';

/// Opens the org picker sheet. Selecting an org updates [currentOrgProvider].
Future<void> showOrgSwitcherSheet(BuildContext context, WidgetRef ref) async {
  final action =
      await showTFSheet<String>(context, builder: (_) => const _OrgListSheet());
  if (action == _createAction && context.mounted) {
    await showCreateOrgSheet(context, ref);
  }
}

class _OrgListSheet extends ConsumerWidget {
  const _OrgListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgs = ref.watch(orgsProvider);
    final activeSlug = ref.watch(activeOrgProvider).valueOrNull?.slug;
    final user = ref.watch(authProvider.select((s) => s.user));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Eyebrow('Switch organization'),
            const SizedBox(height: 4),
            Text('Organizations', style: TFText.h2()),
            const SizedBox(height: 16),
            Flexible(
              child: orgs.when(
                skipLoadingOnRefresh: true,
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'You are not a member of any organization yet.',
                          style: TFText.body(color: TF.textMuted),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final org = list[i];
                          final isActive = org.slug == activeSlug;
                          return _OrgRow(
                            org: org,
                            active: isActive,
                            role: userRoleIn(user, org.slug),
                            onTap: () {
                              ref.read(currentOrgProvider.notifier).state =
                                  org.slug;
                              Navigator.of(ctx).pop();
                              if (!isActive) {
                                showToast(context, 'Switched to ${org.name}',
                                    kind: ToastKind.info);
                              }
                            },
                          )
                              .animate(delay: (40 * i).ms)
                              .fadeIn(duration: 260.ms)
                              .slideX(
                                  begin: 0.04,
                                  end: 0,
                                  duration: 260.ms,
                                  curve: Curves.easeOutCubic);
                        },
                      ),
                loading: () =>
                    Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < 3; i++) ...[
                    const Skeleton(height: 60, radius: TF.radiusLg),
                    if (i < 2) const SizedBox(height: 8),
                  ],
                ]),
                error: (e, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(errorMessage(e),
                          style: TFText.body(color: TF.danger)),
                      const SizedBox(height: 10),
                      TFButton(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        size: TFButtonSize.sm,
                        variant: TFButtonVariant.secondary,
                        onPressed: () => ref.invalidate(orgsProvider),
                      ),
                    ]),
              ),
            ),
            const SizedBox(height: 16),
            TFButton(
              label: 'Create organization',
              icon: Icons.add_rounded,
              variant: TFButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_createAction),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgRow extends StatelessWidget {
  const _OrgRow(
      {required this.org,
      required this.active,
      required this.onTap,
      this.role});
  final Organization org;
  final bool active;
  final String? role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: AnimatedContainer(
        duration: TF.dur,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? TF.brand.withValues(alpha: 0.06) : TF.bgElevated,
          borderRadius: BorderRadius.circular(TF.radiusLg),
          border: Border.all(color: active ? TF.borderBrand : TF.borderDefault),
        ),
        child: Row(children: [
          OrgMark(name: org.name, size: 38, active: active),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                org.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TFText.sans(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                role == null ? '/${org.slug}' : '/${org.slug} · ${role!}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TFText.mono(size: 11),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          PlanBadge(org.plan),
          const SizedBox(width: 10),
          AnimatedScale(
            scale: active ? 1 : 0,
            duration: TF.durSlow,
            curve: TF.easeBounce,
            child: Container(
              width: 22,
              height: 22,
              decoration:
                  const BoxDecoration(color: TF.brand, shape: BoxShape.circle),
              child:
                  const Icon(Icons.check_rounded, size: 15, color: TF.onBrand),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Create organization ──────────────────────────────────────────────────────

/// Opens the "Create organization" sheet. On success the new org becomes the
/// active one, [orgsProvider] is refreshed, and the org is returned.
Future<Organization?> showCreateOrgSheet(BuildContext context, WidgetRef ref) {
  // The sheet owns its own ref so the mutation survives the caller rebuilding.
  return showTFSheet<Organization>(context,
      builder: (_) => const _CreateOrgSheet());
}

class _CreateOrgSheet extends ConsumerStatefulWidget {
  const _CreateOrgSheet();

  @override
  ConsumerState<_CreateOrgSheet> createState() => _CreateOrgSheetState();
}

class _CreateOrgSheetState extends ConsumerState<_CreateOrgSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _website = TextEditingController();
  bool _saving = false;
  Map<String, String?> _fieldErrors = const {};
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _fieldErrors = const {};
      _formError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final org = await ref.read(repositoryProvider).createOrg(
            name: _name.text.trim(),
            description: _description.text.trim(),
            website: normalizeWebsite(_website.text),
          );
      ref.read(currentOrgProvider.notifier).state = org.slug;
      ref.invalidate(orgsProvider);
      unawaited(ref.read(authProvider.notifier).refreshUser());
      if (!mounted) return;
      showToast(context, '${org.name} created');
      Navigator.of(context).pop(org);
    } on ApiError catch (e) {
      if (!mounted) return;
      final fields = {
        'name': e.fieldError('name'),
        'description': e.fieldError('description'),
        'website': e.fieldError('website'),
      };
      setState(() {
        _saving = false;
        _fieldErrors = fields;
        _formError = fields.values.every((v) => v == null) ? e.friendly : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('New workspace', color: TF.brand),
              const SizedBox(height: 4),
              Text('Create organization', style: TFText.h2()),
              const SizedBox(height: 6),
              Text(
                'Organizations hold your projects, members and billing.',
                style: TFText.body(color: TF.textMuted),
              ),
              const SizedBox(height: 20),
              AnimatedSize(
                duration: TF.dur,
                curve: TF.ease,
                child: _formError == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _InlineError(message: _formError!),
                      ),
              ),
              TFTextField(
                label: 'Organization name',
                hint: 'Acme Inc.',
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                errorText: _fieldErrors['name'],
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Name must be at least 2 characters.'
                    : null,
              ),
              const SizedBox(height: 14),
              TFTextField(
                label: 'Description (optional)',
                hint: 'What does your team do?',
                controller: _description,
                textInputAction: TextInputAction.next,
                errorText: _fieldErrors['description'],
              ),
              const SizedBox(height: 14),
              TFTextField(
                label: 'Website (optional)',
                hint: 'https://example.com',
                controller: _website,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                errorText: _fieldErrors['website'],
                validator: validateWebsite,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TFButton(
                    label: 'Cancel',
                    variant: TFButtonVariant.secondary,
                    expand: true,
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TFButton(
                    label: 'Create',
                    icon: Icons.add_rounded,
                    expand: true,
                    loading: _saving,
                    onPressed: _submit,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TF.dangerLight,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.danger.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, size: 18, color: TF.danger),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TFText.sans(size: 13.5, color: TF.danger))),
      ]),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .shakeX(hz: 4, amount: 3, duration: 300.ms);
  }
}
