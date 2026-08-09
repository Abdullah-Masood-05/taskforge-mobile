import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error.dart';
import '../../core/theme/tokens.dart';
import '../../data/models.dart' show BillingStatus;
import '../../data/repository.dart';

/// Shared billing data + helpers for [BillingScreen] and [PricingScreen].
/// Plan copy mirrors the web `orgs/[slug]/pricing/page.jsx`.

/// Stripe price IDs. The web reads these from NEXT_PUBLIC_STRIPE_*_PRICE_ID;
/// the app takes them at build time:
///   flutter run --dart-define=STRIPE_PRO_PRICE_ID=price_xxx \
///               --dart-define=STRIPE_BUSINESS_PRICE_ID=price_yyy
const stripeProPriceId = String.fromEnvironment('STRIPE_PRO_PRICE_ID');
const stripeBusinessPriceId =
    String.fromEnvironment('STRIPE_BUSINESS_PRICE_ID');

class PlanInfo {
  const PlanInfo({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.description,
    required this.features,
    required this.cta,
    this.priceId,
    this.highlight = false,
    this.badge,
  });

  final String id;
  final String name;
  final String price;
  final String period;
  final String description;
  final List<String> features;
  final String cta;
  final String? priceId;
  final bool highlight;
  final String? badge;

  bool get isPaid => id != 'free';
}

const plans = <PlanInfo>[
  PlanInfo(
    id: 'free',
    name: 'Free',
    price: r'$0',
    period: 'forever',
    description: 'For individuals and small teams just getting started.',
    features: [
      'Up to 3 active projects',
      '5 team members',
      '1 GB file storage',
      'Kanban boards',
      'Task comments & activity',
      'PDF exports',
      'Community support',
    ],
    cta: 'Current plan',
  ),
  PlanInfo(
    id: 'pro',
    name: 'Pro',
    price: r'$12',
    period: 'per seat / month',
    description:
        'For growing teams that need unlimited projects and priority support.',
    highlight: true,
    badge: 'Most Popular',
    features: [
      'Unlimited projects',
      '25 team members',
      '50 GB file storage',
      'Kanban boards',
      'Task comments & activity',
      'PDF exports',
      'Email support',
      'Advanced filters & search',
      'Notifications digest',
    ],
    cta: 'Upgrade to Pro',
    priceId: stripeProPriceId,
  ),
  PlanInfo(
    id: 'business',
    name: 'Business',
    price: r'$29',
    period: 'per seat / month',
    description:
        'For large organisations with dedicated support and unlimited scale.',
    features: [
      'Unlimited projects',
      'Unlimited team members',
      '500 GB file storage',
      'Kanban boards',
      'Task comments & activity',
      'PDF exports',
      'Dedicated account manager',
      'SLA & priority queue',
      'SSO / SAML (coming soon)',
      'Audit log export',
    ],
    cta: 'Upgrade to Business',
    priceId: stripeBusinessPriceId,
  ),
];

String planLabel(String? plan) => switch (plan) {
      'pro' => 'Pro',
      'business' => 'Business',
      'free' || null || '' => 'Free',
      final String p => p[0].toUpperCase() + p.substring(1),
    };

Color planColor(String? plan) => switch (plan) {
      'pro' => TF.brandHover,
      'business' => const Color(0xFFFBBF24),
      _ => TF.textSecondary,
    };

String statusLabel(String? status) => switch (status) {
      'active' => 'Active',
      'trialing' => 'Trialing',
      'past_due' => 'Past Due',
      'canceled' => 'Canceled',
      'incomplete' => 'Incomplete',
      null || '' => '—',
      final String s => s,
    };

Color statusColor(String? status) => switch (status) {
      'active' => TF.success,
      'trialing' => TF.brandHover,
      'past_due' || 'incomplete' => TF.danger,
      _ => TF.textMuted,
    };

final billingStatusProvider =
    FutureProvider.autoDispose.family<BillingStatus, String>(
  (ref, slug) => ref.watch(repositoryProvider).billingStatus(slug),
);

/// Turns billing API failures into something a person can act on. Stripe is
/// not configured on the hosted demo, so 503 "Billing is not configured." is
/// the common case.
String billingErrorMessage(Object error) {
  if (error is ApiError) {
    final msg = error.message.toLowerCase();
    if (error.status == 503 || msg.contains('not configured')) {
      return "Billing isn't enabled on this TaskForge server yet, so payments are turned off for now. "
          'Your workspace keeps working on its current plan.';
    }
    if (error.status == 403) {
      return 'Only organization admins can manage billing. Ask an admin to make changes.';
    }
    if (msg.contains('no billing account')) {
      return 'There is no billing account for this organization yet. Upgrade to a paid plan first.';
    }
    if (error.isNetwork) return error.friendly;
    if (error.status >= 500) {
      return 'The billing service is unavailable right now. Please try again later.';
    }
    return error.friendly;
  }
  return errorMessage(error);
}

/// Opens a Stripe-hosted URL in the browser. Returns false if it couldn't.
Future<bool> launchExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
