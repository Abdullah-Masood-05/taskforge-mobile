import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';

const _docsUrl = 'https://abdullah-masood-05.github.io/taskforge-site/';

class _Feature {
  const _Feature(this.icon, this.title, this.description, this.tag);
  final IconData icon;
  final String title;
  final String description;
  final String tag;
}

const _features = [
  _Feature(
    Icons.view_kanban_outlined,
    'Kanban board',
    'Move tasks across columns with live updates for the whole team.',
    'board',
  ),
  _Feature(
    Icons.insights_rounded,
    'Live analytics',
    'Velocity, priority breakdowns, and activity feeds that update in real time.',
    'analytics',
  ),
  _Feature(
    Icons.hub_outlined,
    'Multi-tenant teams',
    'Separate organizations, role-based access, and invites for admins, members and viewers.',
    'orgs',
  ),
  _Feature(
    Icons.devices_rounded,
    'Everywhere you work',
    'The same workspace in the browser, the native desktop app, and now on your phone.',
    'sync',
  ),
];

/// Marketing / onboarding screen (web `welcome/page.jsx`).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pager = PageController(viewportFraction: 0.88);
  Timer? _autoplay;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoplay();
  }

  void _startAutoplay() {
    _autoplay?.cancel();
    _autoplay = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pager.hasClients) return;
      final next = (_page + 1) % _features.length;
      _pager.animateToPage(next,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _autoplay?.cancel();
    _pager.dispose();
    super.dispose();
  }

  void _go(String path) {
    ref.read(tokenStorageProvider).setOnboarded();
    context.push(path);
  }

  Future<void> _openDocs() async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(_docsUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      showToast(context, 'Could not open the documentation.',
          kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TF.bgBase,
      body: DotGridBackground(
        glow: true,
        child: Stack(children: [
          const Positioned(
              top: -140,
              right: -100,
              child: _GlowOrb(size: 420, color: Color(0x24F5A623), seconds: 9)),
          const Positioned(
            bottom: 60,
            left: -140,
            child: _GlowOrb(
                size: 360,
                color: Color(0x1AFFC880),
                seconds: 11,
                reverse: true),
          ),
          SafeArea(
            child: Column(children: [
              _TopBar(onLogin: () => _go('/login')),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 28, bottom: 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: _Hero(),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          height: 176,
                          child: PageView.builder(
                            controller: _pager,
                            itemCount: _features.length,
                            onPageChanged: (i) {
                              setState(() => _page = i);
                              _startAutoplay();
                            },
                            itemBuilder: (context, i) => AnimatedBuilder(
                              animation: _pager,
                              builder: (context, child) {
                                var delta = i == _page ? 0.0 : 1.0;
                                if (_pager.hasClients &&
                                    _pager.position.haveDimensions) {
                                  final d =
                                      ((_pager.page ?? _page.toDouble()) - i)
                                          .abs();
                                  delta = d > 1 ? 1.0 : d;
                                }
                                return Transform.scale(
                                  scale: 1 - delta * 0.06,
                                  child: Opacity(
                                      opacity: 1 - delta * 0.45, child: child),
                                );
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: _FeatureCard(
                                    feature: _features[i],
                                    index: i,
                                    active: i == _page),
                              ),
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 700.ms, duration: 500.ms)
                            .slideX(
                                begin: 0.15,
                                end: 0,
                                curve: Curves.easeOutCubic,
                                duration: 600.ms),
                        const SizedBox(height: 16),
                        Center(
                                child: _Dots(
                                    count: _features.length, active: _page))
                            .animate()
                            .fadeIn(delay: 850.ms, duration: 400.ms),
                      ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TFButton(
                        label: 'Get started',
                        icon: Icons.arrow_forward_rounded,
                        size: TFButtonSize.lg,
                        expand: true,
                        onPressed: () => _go('/register'),
                      ),
                      const SizedBox(height: 10),
                      TFButton(
                        label: 'Sign in',
                        variant: TFButtonVariant.secondary,
                        size: TFButtonSize.lg,
                        expand: true,
                        onPressed: () => _go('/login'),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Pressable(
                          onTap: _openDocs,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Documentation',
                                  style: TFText.sans(
                                      size: 13, color: TF.textMuted)),
                              const SizedBox(width: 4),
                              const Icon(Icons.north_east_rounded,
                                  size: 14, color: TF.textMuted),
                            ]),
                          ),
                        ),
                      ),
                    ]
                        .animate(interval: 90.ms, delay: 950.ms)
                        .fadeIn(duration: 400.ms)
                        .slideY(
                            begin: 0.4, end: 0, curve: Curves.easeOutCubic)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
      child: Row(children: [
        const BrandLogo(size: 30, glow: true)
            .animate()
            .fadeIn(duration: 500.ms)
            .scale(
                begin: const Offset(0.6, 0.6),
                curve: TF.easeBounce,
                duration: 700.ms),
        const Spacer(),
        TFButton(
          label: 'Log in',
          variant: TFButtonVariant.ghost,
          size: TFButtonSize.sm,
          onPressed: onLogin,
        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
      ]),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final headline = TFText.sans(
        size: 34, weight: FontWeight.w700, letterSpacing: -1.1, height: 1.12);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Pulsing mark — the forge is lit.
      const BrandLogo(size: 56, showWordmark: false, glow: true)
          .animate()
          .fadeIn(duration: 500.ms, delay: 100.ms)
          .scale(
              begin: const Offset(0.5, 0.5),
              curve: TF.easeBounce,
              duration: 800.ms)
          .animate(delay: 900.ms, onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(
              begin: 1, end: 1.05, duration: 1800.ms, curve: Curves.easeInOut),
      const SizedBox(height: 24),
      Row(children: [
        Container(width: 18, height: 1, color: TF.brand),
        const SizedBox(width: 10),
        const Flexible(
            child: Eyebrow('Multi-tenant project management', color: TF.brand)),
      ])
          .animate()
          .fadeIn(delay: 250.ms, duration: 400.ms)
          .slideX(begin: -0.1, end: 0),
      const SizedBox(height: 14),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Project management with a '),
          TextSpan(
              text: 'mission-control',
              style: headline.copyWith(color: TF.brand)),
          const TextSpan(text: ' dashboard'),
        ]),
        style: headline,
      )
          .animate()
          .fadeIn(delay: 350.ms, duration: 500.ms)
          .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
      const SizedBox(height: 14),
      Text(
        'Organize work across teams with a Kanban board, real-time activity, and live project analytics — '
        'on the web, the desktop, and in your pocket.',
        style: TFText.body(color: TF.textMuted),
      )
          .animate()
          .fadeIn(delay: 480.ms, duration: 500.ms)
          .slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
      const SizedBox(height: 18),
      const _TypewriterPrompt()
          .animate()
          .fadeIn(delay: 600.ms, duration: 300.ms),
    ]);
  }
}

/// `> forge init --team` typed out with a blinking block cursor.
class _TypewriterPrompt extends StatelessWidget {
  const _TypewriterPrompt();

  static const _command = 'forge init --team your-crew';

  @override
  Widget build(BuildContext context) {
    final style = TFText.mono(size: 12.5, color: TF.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TF.bgSurface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.borderDefault),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('\$ ',
            style:
                style.copyWith(color: TF.brand, fontWeight: FontWeight.w700)),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: _command.length),
          duration: const Duration(milliseconds: 1400),
          curve: const Interval(0.45, 1, curve: Curves.linear),
          builder: (context, n, _) =>
              Text(_command.substring(0, n), style: style),
        ),
        const SizedBox(width: 2),
        Container(width: 7, height: 14, color: TF.brand)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fade(
                begin: 1,
                end: 0,
                duration: 530.ms,
                curve: Curves.easeInOutExpo),
      ]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(
      {required this.feature, required this.index, required this.active});
  final _Feature feature;
  final int index;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TF.durSlow,
      curve: TF.ease,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TF.bgSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(TF.radiusXl),
        border: Border.all(color: active ? TF.borderBrand : TF.borderDefault),
        boxShadow: active ? TF.shadowGlow : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: TF.brandLight,
              borderRadius: BorderRadius.circular(TF.radiusLg),
              border: Border.all(color: TF.borderBrand),
            ),
            child: Icon(feature.icon, size: 19, color: TF.brand),
          ),
          const Spacer(),
          Text(
            '${(index + 1).toString().padLeft(2, '0')} / ${_features.length.toString().padLeft(2, '0')}',
            style:
                TFText.mono(size: 11, color: TF.textDisabled, letterSpacing: 1),
          ),
        ]),
        const Spacer(),
        Text(feature.title, style: TFText.h3()),
        const SizedBox(height: 6),
        Text(
          feature.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TFText.small(color: TF.textMuted),
        ),
      ]),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: TF.durSlow,
          curve: TF.ease,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == active ? 22 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == active ? TF.brand : TF.borderStrong,
            borderRadius: BorderRadius.circular(TF.radiusSm),
            boxShadow: i == active
                ? const [BoxShadow(color: Color(0x66F5A623), blurRadius: 8)]
                : null,
          ),
        ),
    ]);
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb(
      {required this.size,
      required this.color,
      required this.seconds,
      this.reverse = false});
  final double size;
  final Color color;
  final int seconds;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0, 0.7]),
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
            begin: Offset.zero,
            end: Offset(reverse ? 18 : -18, reverse ? -26 : 26),
            duration: Duration(milliseconds: seconds * 500),
            curve: Curves.easeInOut,
          ),
    );
  }
}
