import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';

/// Shared layout for the login / register screens — the mobile analogue of
/// the web `(auth)/layout.jsx`: warm glowing dot-grid, floating orbs, a
/// frosted card and the "Built for modern teams" footer.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  /// Form content rendered inside the card, below the heading.
  final Widget child;

  /// Optional content below the card (e.g. "Don't have an account?").
  final Widget? footer;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/welcome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TF.bgBase,
      resizeToAvoidBottomInset: true,
      body: DotGridBackground(
        glow: true,
        child: Stack(children: [
          // Decorative floating orbs (web .orb1 / .orb2).
          const Positioned(
            top: -120,
            left: -90,
            child: _Orb(
                size: 380,
                color: Color(0x1FF5A623),
                duration: Duration(seconds: 8)),
          ),
          const Positioned(
            bottom: -110,
            right: -80,
            child: _Orb(
                size: 320,
                color: Color(0x1AFFC880),
                duration: Duration(seconds: 10),
                reverse: true),
          ),
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  TFIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: () => _back(context),
                  )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .slideX(begin: -0.3, end: 0, curve: Curves.easeOutCubic),
                  const Spacer(),
                  const BrandLogo(size: 26, glow: true)
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 80.ms)
                      .scale(
                          begin: const Offset(0.85, 0.85),
                          curve: TF.easeBounce,
                          duration: 500.ms),
                  const Spacer(),
                  const SizedBox(width: 40),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _AuthCard(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                            color: TF.brand,
                                            shape: BoxShape.circle),
                                      )
                                          .animate(
                                              onPlay: (c) =>
                                                  c.repeat(reverse: true))
                                          .fade(
                                              begin: 1,
                                              end: 0.25,
                                              duration: 900.ms),
                                      const SizedBox(width: 8),
                                      Expanded(
                                          child: Eyebrow(eyebrow,
                                              color: TF.brand)),
                                    ]),
                                    const SizedBox(height: 12),
                                    Text(title, style: TFText.h1()),
                                    const SizedBox(height: 6),
                                    Text(subtitle,
                                        style:
                                            TFText.body(color: TF.textMuted)),
                                    const SizedBox(height: 24),
                                    child,
                                  ]
                                      .animate(interval: 60.ms, delay: 150.ms)
                                      .fadeIn(duration: 350.ms)
                                      .slideY(
                                          begin: 0.12,
                                          end: 0,
                                          curve: Curves.easeOutCubic)),
                            ).animate().fadeIn(duration: 400.ms).slideY(
                                begin: 0.05,
                                end: 0,
                                curve: Curves.easeOutCubic,
                                duration: 450.ms),
                            if (footer != null) ...[
                              const SizedBox(height: 20),
                              footer!
                                  .animate()
                                  .fadeIn(delay: 450.ms, duration: 400.ms),
                            ],
                            const SizedBox(height: 20),
                            const _BrandFooter()
                                .animate()
                                .fadeIn(delay: 600.ms, duration: 500.ms),
                          ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Frosted, hairline-bordered card (web `.card` in the auth layout).
class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TF.radiusXl),
        boxShadow: TF.shadowLg,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TF.radiusXl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            decoration: BoxDecoration(
              color: const Color(0xCC16130D),
              borderRadius: BorderRadius.circular(TF.radiusXl),
              border: Border.all(color: TF.borderDefault),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => TF.brandGradient.createShader(rect),
        child: Text('TaskForge',
            style: TFText.sans(size: 13, weight: FontWeight.w700)),
      ),
      Text(' · Built for modern teams',
          style: TFText.sans(size: 13, color: TF.textDisabled)),
    ]);
  }
}

/// Soft radial orb drifting up and down (web `@keyframes float`).
class _Orb extends StatelessWidget {
  const _Orb(
      {required this.size,
      required this.color,
      required this.duration,
      this.reverse = false});
  final double size;
  final Color color;
  final Duration duration;
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
      ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(
          begin: reverse ? -24 : 0,
          end: reverse ? 0 : -24,
          duration: duration ~/ 2,
          curve: Curves.easeInOut),
    );
  }
}

/// Inline alert for non-field server errors (web `.serverError`).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: TF.dangerLight,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.danger.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline_rounded, size: 17, color: TF.danger),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TFText.sans(size: 13.5, color: TF.danger, height: 1.4))),
      ]),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .shakeX(hz: 5, amount: 3, duration: 350.ms);
  }
}

/// Subtle hint shown when a request is slow — the API runs on Render's free
/// tier and may take ~50s to cold-start.
class WakingServerHint extends StatelessWidget {
  const WakingServerHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TF.brandLight,
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.borderBrand),
      ),
      child: Row(children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: TF.brand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WAKING UP THE SERVER…',
                style: TFText.mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: TF.brand,
                    letterSpacing: 1.4)),
            const SizedBox(height: 2),
            Text(
              'The first request after a quiet spell can take up to a minute.',
              style: TFText.small(color: TF.textSecondary),
            ),
          ]),
        ),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0);
  }
}

/// Tracks whether an in-flight request has exceeded [threshold], so screens
/// can show [WakingServerHint].
mixin SlowRequestTracker<T extends StatefulWidget> on State<T> {
  Timer? _slowTimer;
  bool requestIsSlow = false;

  Future<R> trackSlow<R>(Future<R> Function() run,
      {Duration threshold = const Duration(seconds: 6)}) async {
    _slowTimer?.cancel();
    _slowTimer = Timer(threshold, () {
      if (mounted) setState(() => requestIsSlow = true);
    });
    try {
      return await run();
    } finally {
      _slowTimer?.cancel();
      _slowTimer = null;
      if (mounted && requestIsSlow) setState(() => requestIsSlow = false);
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }
}

/// "Don't have an account? Create one" style footer link.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink(
      {super.key,
      required this.prompt,
      required this.action,
      required this.onTap});
  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('$prompt ', style: TFText.sans(size: 14, color: TF.textMuted)),
      Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(action,
              style: TFText.sans(
                  size: 14, weight: FontWeight.w600, color: TF.brand)),
        ),
      ),
    ]);
  }
}
