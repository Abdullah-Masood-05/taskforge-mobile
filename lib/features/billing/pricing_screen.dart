import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/repository.dart';
import '../../widgets/widgets.dart';
import 'plans.dart';

/// Plan picker (web `orgs/[slug]/pricing/page.jsx`). Upgrading creates a
/// Stripe Checkout session and opens it in the browser.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  static const _rank = {'free': 0, 'pro': 1, 'business': 2};

  String? _pendingPlan;
  String? _notice;
  bool _noticeOffersWeb = false;

  Future<void> _upgrade(PlanInfo plan) async {
    if (_pendingPlan != null) return;
    HapticFeedback.mediumImpact();
    final priceId = plan.priceId;
    if (priceId == null || priceId.isEmpty) {
      setState(() {
        _notice =
            'In-app checkout is not set up for this build. You can upgrade to ${plan.name} from the TaskForge web app.';
        _noticeOffersWeb = true;
      });
      return;
    }
    setState(() {
      _pendingPlan = plan.id;
      _notice = null;
      _noticeOffersWeb = false;
    });
    final repo = ref.read(repositoryProvider);
    try {
      final url = await repo.createCheckout(widget.slug, priceId);
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() => _notice =
            'Checkout is unavailable right now. Please try again later.');
      } else {
        final ok = await launchExternal(url);
        if (!ok && mounted) {
          showToast(context, "Couldn't open checkout", kind: ToastKind.error);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _notice = billingErrorMessage(e));
    } finally {
      if (mounted) setState(() => _pendingPlan = null);
    }
  }

  Future<void> _openWebPricing() async {
    final ok =
        await launchExternal('${AppConfig.webUrl}/orgs/${widget.slug}/pricing');
    if (!ok && mounted) {
      showToast(context, "Couldn't open the web app", kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = ref.watch(billingStatusProvider(widget.slug));
    final currentPlan = billing.valueOrNull?.plan ?? 'free';
    final currentRank = _rank[currentPlan] ?? 0;

    return Scaffold(
      backgroundColor: TF.bgBase,
      appBar: AppBar(title: const Text('Pricing')),
      body: RefreshIndicator(
        color: TF.brand,
        backgroundColor: TF.bgElevated,
        onRefresh: () async {
          ref.invalidate(billingStatusProvider(widget.slug));
          try {
            await ref.read(billingStatusProvider(widget.slug).future);
          } catch (_) {}
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
          children: [
            Column(children: [
              const SizedBox(height: 8),
              const Eyebrow('Pricing', color: TF.brand),
              const SizedBox(height: 8),
              Text('Simple, transparent pricing',
                  style: TFText.h1(), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Start free, scale when you need to. No hidden fees.',
                style: TFText.body(color: TF.textMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ])
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.06, end: 0, duration: 400.ms, curve: TF.ease),
            AnimatedSize(
              duration: TF.dur,
              curve: TF.ease,
              child: _notice == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _Notice(
                        message: _notice!,
                        action: _noticeOffersWeb
                            ? TFButton(
                                label: 'Open web pricing',
                                icon: Icons.north_east_rounded,
                                size: TFButtonSize.sm,
                                variant: TFButtonVariant.secondary,
                                onPressed: _openWebPricing,
                              )
                            : null,
                        onClose: () => setState(() => _notice = null),
                      ),
                    ),
            ),
            for (var i = 0; i < plans.length; i++)
              Padding(
                padding: EdgeInsets.only(
                    bottom: 16, top: plans[i].highlight ? 10 : 0),
                child: _PlanCard(
                  plan: plans[i],
                  isCurrent: plans[i].id == currentPlan,
                  isLower: (_rank[plans[i].id] ?? 0) < currentRank,
                  loadingStatus: billing.isLoading && !billing.hasValue,
                  pending: _pendingPlan == plans[i].id,
                  busy: _pendingPlan != null,
                  onUpgrade: () => _upgrade(plans[i]),
                )
                    .animate()
                    .fadeIn(
                        duration: 420.ms,
                        delay: (120 + i * 90).ms,
                        curve: TF.ease)
                    .slideY(
                        begin: 0.08,
                        end: 0,
                        duration: 420.ms,
                        delay: (120 + i * 90).ms,
                        curve: TF.ease),
              ),
            const SizedBox(height: 4),
            Text(
              'All plans include a 14-day free trial. Cancel anytime. Prices in USD.',
              textAlign: TextAlign.center,
              style: TFText.small(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.isLower,
    required this.loadingStatus,
    required this.pending,
    required this.busy,
    required this.onUpgrade,
  });

  final PlanInfo plan;
  final bool isCurrent;
  final bool isLower;
  final bool loadingStatus;
  final bool pending;
  final bool busy;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final color = planColor(plan.id);
    final highlight = plan.highlight;

    final String ctaLabel;
    final bool ctaEnabled;
    if (isCurrent) {
      ctaLabel = 'Current plan';
      ctaEnabled = false;
    } else if (!plan.isPaid) {
      ctaLabel = 'Free forever';
      ctaEnabled = false;
    } else if (pending) {
      ctaLabel = 'Redirecting…';
      ctaEnabled = false;
    } else {
      ctaLabel = isLower ? 'Switch to ${plan.name}' : plan.cta;
      ctaEnabled = !busy && !loadingStatus;
    }

    final card = AnimatedContainer(
      duration: TF.durSlow,
      curve: TF.ease,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        // BoxDecoration forbids color + gradient together.
        color: highlight ? null : TF.bgSurface,
        borderRadius: BorderRadius.circular(TF.radiusLg),
        border: Border.all(
          color: isCurrent
              ? TF.success.withValues(alpha: 0.5)
              : (highlight ? TF.borderBrand : TF.borderDefault),
          width: highlight ? 1.2 : 1,
        ),
        boxShadow: highlight
            ? const [
                BoxShadow(
                    color: Color(0x40F5A623), blurRadius: 32, spreadRadius: -4),
                BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 12,
                    offset: Offset(0, 4)),
              ]
            : null,
        gradient: highlight
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [TF.brand.withValues(alpha: 0.08), TF.bgElevated],
                stops: const [0, 0.45],
              )
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            plan.name.toUpperCase(),
            style: TFText.mono(
                size: 13,
                weight: FontWeight.w700,
                color: color,
                letterSpacing: 2),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: TF.dur,
            child: isCurrent
                ? const TFBadge('Current',
                    key: ValueKey('current'), color: TF.success, dot: true)
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(plan.price,
              style: TFText.sans(
                  size: 40,
                  weight: FontWeight.w700,
                  letterSpacing: -1.2,
                  height: 1)),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(plan.period, style: TFText.mono(size: 12)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(plan.description, style: TFText.body(color: TF.textMuted)),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 14),
        for (final f in plan.features)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.check_rounded, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(f,
                      style: TFText.sans(size: 14, color: TF.textSecondary))),
            ]),
          ),
        const SizedBox(height: 8),
        TFButton(
          label: ctaLabel,
          expand: true,
          loading: pending,
          icon: isCurrent
              ? Icons.check_circle_outline_rounded
              : (plan.isPaid ? Icons.bolt_rounded : null),
          variant: highlight && !isCurrent
              ? TFButtonVariant.primary
              : TFButtonVariant.secondary,
          onPressed: ctaEnabled ? onUpgrade : null,
        ),
      ]),
    );

    if (plan.badge == null) return card;

    return Stack(clipBehavior: Clip.none, children: [
      card,
      Positioned(
        top: -11,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: TF.brandGradient,
              borderRadius: BorderRadius.circular(TF.radiusSm),
              boxShadow: TF.shadowGlow,
            ),
            child: Text(
              plan.badge!.toUpperCase(),
              style: TFText.mono(
                  size: 10,
                  weight: FontWeight.w700,
                  color: TF.onBrand,
                  letterSpacing: 1.4),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
              duration: 2200.ms, delay: 600.ms, color: const Color(0x55FFFFFF)),
        ),
      ),
    ]);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onClose, this.action});
  final String message;
  final VoidCallback onClose;
  final Widget? action;

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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message,
                style: TFText.sans(
                    size: 13.5, color: TF.textSecondary, height: 1.45)),
            if (action != null) ...[const SizedBox(height: 10), action!],
          ]),
        ),
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
