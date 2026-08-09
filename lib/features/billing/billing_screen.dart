import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart' show BillingStatus;
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import 'plans.dart';

const _monthNames = [
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

String _longDate(DateTime t) =>
    '${_monthNames[t.month - 1]} ${t.day}, ${t.year}';

/// Org billing (web `orgs/[slug]/billing/page.jsx`): current plan, status,
/// renewal date, Stripe portal and feature comparison.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  bool _opening = false;
  String? _notice;

  Future<void> _openPortal() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _notice = null;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final url = await repo.openPortal(widget.slug);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() => _notice =
            'The billing portal is unavailable right now. Please try again later.');
      } else {
        final ok = await launchExternal(url);
        if (!ok && mounted) {
          showToast(context, "Couldn't open the billing portal",
              kind: ToastKind.error);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _notice = billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(billingStatusProvider(widget.slug));
    ref.invalidate(orgDetailProvider(widget.slug));
    setState(() => _notice = null);
    try {
      await ref.read(billingStatusProvider(widget.slug).future);
    } catch (_) {
      // Rendered by the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(billingStatusProvider(widget.slug));
    final orgName = ref.watch(orgDetailProvider(widget.slug)).valueOrNull?.name;

    return Scaffold(
      backgroundColor: TF.bgBase,
      appBar: AppBar(title: const Text('Billing')),
      body: RefreshIndicator(
        color: TF.brand,
        backgroundColor: TF.bgElevated,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
          children: [
            Eyebrow(orgName == null
                ? 'Organization · ${widget.slug}'
                : 'Organization · $orgName'),
            const SizedBox(height: 4),
            Text('Plan & billing', style: TFText.h1()),
            const SizedBox(height: 6),
            Text('Manage your subscription, payment method and invoices.',
                style: TFText.body(color: TF.textMuted)),
            const SizedBox(height: 20),
            AnimatedSize(
              duration: TF.dur,
              curve: TF.ease,
              child: _notice == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _NoticeBanner(
                        message: _notice!,
                        onClose: () => setState(() => _notice = null),
                      ),
                    ),
            ),
            AsyncView<BillingStatus>(
              value: billing,
              onRetry: () => ref.invalidate(billingStatusProvider(widget.slug)),
              loading: const Skeleton(height: 190, radius: TF.radiusLg),
              data: (b) => _CurrentPlanCard(
                billing: b,
                opening: _opening,
                onManage: _openPortal,
                onUpgrade: () => context.push('/orgs/${widget.slug}/pricing'),
              ),
            ),
            const SizedBox(height: 24),
            _FeatureTable(currentPlan: billing.valueOrNull?.plan ?? 'free')
                .animate()
                .fadeIn(duration: 400.ms, delay: 150.ms)
                .slideY(
                    begin: 0.05,
                    end: 0,
                    duration: 400.ms,
                    delay: 150.ms,
                    curve: TF.ease),
            const SizedBox(height: 16),
            Center(
              child: TFButton(
                label: 'See full pricing',
                icon: Icons.arrow_forward_rounded,
                variant: TFButtonVariant.ghost,
                size: TFButtonSize.sm,
                onPressed: () => context.push('/orgs/${widget.slug}/pricing'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.billing,
    required this.opening,
    required this.onManage,
    required this.onUpgrade,
  });

  final BillingStatus billing;
  final bool opening;
  final VoidCallback onManage;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final isFree = billing.plan == 'free' || billing.plan.isEmpty;
    final color = planColor(billing.plan);
    final status = billing.subscriptionStatus;
    final periodEnd = billing.currentPeriodEnd;
    final canceled = status == 'canceled';

    return TFCard(
      highlight: !isFree,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Current plan'),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(TF.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              boxShadow: isFree
                  ? null
                  : [
                      BoxShadow(
                          color: color.withValues(alpha: 0.25), blurRadius: 16)
                    ],
            ),
            child: Text(
              planLabel(billing.plan),
              style: TFText.sans(
                  size: 22,
                  weight: FontWeight.w700,
                  color: color,
                  letterSpacing: -0.4),
            ),
          ).animate().scale(
              begin: const Offset(0.9, 0.9),
              duration: 400.ms,
              curve: TF.easeBounce),
          const Spacer(),
          if (status != null && status.isNotEmpty)
            TFBadge(statusLabel(status), color: statusColor(status), dot: true),
        ]),
        const SizedBox(height: 16),
        _MetaRow(
          icon: Icons.event_repeat_rounded,
          label: canceled ? 'Ends' : 'Renews',
          value: periodEnd == null
              ? (isFree ? 'Free forever' : '—')
              : _longDate(periodEnd),
        ),
        const SizedBox(height: 8),
        _MetaRow(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Billing account',
          value: billing.hasBillingAccount ? 'Connected' : 'Not set up',
          valueColor: billing.hasBillingAccount ? TF.success : TF.textMuted,
        ),
        const SizedBox(height: 18),
        if (isFree)
          TFButton(
            label: 'Upgrade plan',
            icon: Icons.arrow_upward_rounded,
            expand: true,
            onPressed: onUpgrade,
          )
        else
          Row(children: [
            Expanded(
              child: TFButton(
                label: opening ? 'Redirecting…' : 'Manage billing',
                icon: Icons.open_in_new_rounded,
                expand: true,
                loading: opening,
                onPressed: onManage,
              ),
            ),
            const SizedBox(width: 10),
            TFButton(
              label: 'Plans',
              variant: TFButtonVariant.secondary,
              onPressed: onUpgrade,
            ),
          ]),
        if (!isFree) ...[
          const SizedBox(height: 10),
          Text(
            'Opens the secure Stripe portal in your browser to update payment details or download invoices.',
            style: TFText.small(),
          ),
        ],
      ]),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: TF.textMuted),
      const SizedBox(width: 10),
      Text(label, style: TFText.sans(size: 13.5, color: TF.textMuted)),
      const Spacer(),
      Text(value,
          style: TFText.mono(size: 12.5, color: valueColor ?? TF.textPrimary)),
    ]);
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: TF.warningLight,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(color: TF.borderBrand),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline_rounded, size: 18, color: TF.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TFText.sans(
                    size: 13.5, color: TF.textSecondary, height: 1.45))),
        InkWell(
          onTap: onClose,
          borderRadius: BorderRadius.circular(TF.radiusSm),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.close_rounded, size: 16, color: TF.textMuted),
          ),
        ),
      ]),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: -0.1, end: 0, duration: 250.ms);
  }
}

class _FeatureTable extends StatelessWidget {
  const _FeatureTable({required this.currentPlan});
  final String currentPlan;

  static const _rows = <(String, String, String, String)>[
    ('Active projects', 'Up to 3', 'Unlimited', 'Unlimited'),
    ('Team members', '5', '25', 'Unlimited'),
    ('File storage', '1 GB', '50 GB', '500 GB'),
    ('PDF exports', '✓', '✓', '✓'),
    ('Priority support', '—', 'Email', 'Dedicated'),
  ];

  @override
  Widget build(BuildContext context) {
    const planIds = ['free', 'pro', 'business'];

    Widget cell(String text, int col, {bool header = false}) {
      final id = planIds[col];
      final current = id == currentPlan;
      final color = header
          ? planColor(id)
          : (current ? TF.textPrimary : TF.textSecondary);
      return Expanded(
        flex: 2,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          color: current ? TF.brand.withValues(alpha: 0.06) : null,
          alignment: Alignment.center,
          child: Text(
            header ? text.toUpperCase() : text,
            textAlign: TextAlign.center,
            style: header
                ? TFText.mono(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1.2)
                : TFText.sans(
                    size: 12.5,
                    color: color,
                    weight: current ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
      );
    }

    return TFCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text('Plan features', style: TFText.h3()),
        ),
        const Divider(),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Expanded(flex: 3, child: SizedBox()),
            cell('Free', 0, header: true),
            cell('Pro', 1, header: true),
            cell('Business', 2, header: true),
          ]),
        ),
        for (final r in _rows) ...[
          const Divider(),
          IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(r.$1,
                        style: TFText.sans(size: 13, color: TF.textMuted)),
                  ),
                ),
              ),
              cell(r.$2, 0),
              cell(r.$3, 1),
              cell(r.$4, 2),
            ]),
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }
}
