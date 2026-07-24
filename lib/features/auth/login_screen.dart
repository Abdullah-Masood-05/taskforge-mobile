import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'auth_scaffold.dart';

/// Sign-in screen (web `LoginForm`). On success the auth state flips to
/// signed-in and the router redirects to the dashboard automatically.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SlowRequestTracker<LoginScreen> {
  static const _demoEmail = 'admin@taskforge.dev';
  static const _demoPassword = 'TaskForge2024!';
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _submitting = false;
  String? _serverError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _fillDemo() {
    HapticFeedback.lightImpact();
    setState(() {
      _email.text = _demoEmail;
      _password.text = _demoPassword;
      _serverError = null;
      _emailError = null;
      _passwordError = null;
    });
    _formKey.currentState?.validate();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _serverError = null;
      _emailError = null;
      _passwordError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await trackSlow(() =>
          ref.read(authProvider.notifier).login(_email.text, _password.text));
      TextInput.finishAutofillContext();
      // Router redirect takes over from here.
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        final emailErr = e.fieldError('email');
        final passErr = e.fieldError('password');
        if (e.status == 400 && (emailErr != null || passErr != null)) {
          _emailError = emailErr;
          _passwordError = passErr;
        } else if (e.status == 401 || e.status == 400) {
          _serverError = 'Invalid email or password. Please try again.';
        } else {
          _serverError = e.friendly;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = errorMessage(e) == 'Something went wrong.'
          ? 'Something went wrong. Please try again.'
          : errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: 'Sign in',
      title: 'Welcome back',
      subtitle: 'Sign in to your TaskForge account',
      footer: AuthSwitchLink(
        prompt: "Don't have an account?",
        action: 'Create one',
        onTap: () => context.pushReplacement('/register'),
      ),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AnimatedSize(
              duration: TF.dur,
              curve: TF.ease,
              alignment: Alignment.topCenter,
              child: _serverError == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AuthErrorBanner(
                          key: ValueKey(_serverError), message: _serverError!),
                    ),
            ),
            TFTextField(
              label: 'Email address',
              hint: 'you@example.com',
              controller: _email,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.email,
                AutofillHints.username
              ],
              prefixIcon: Icons.alternate_email_rounded,
              errorText: _emailError,
              onChanged: (_) {
                if (_emailError != null || _serverError != null) {
                  setState(() {
                    _emailError = null;
                    _serverError = null;
                  });
                }
              },
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty || !_emailRe.hasMatch(value)) {
                  return 'Please enter a valid email.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TFTextField(
              label: 'Password',
              hint: '••••••••',
              controller: _password,
              enabled: !_submitting,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              prefixIcon: Icons.lock_outline_rounded,
              errorText: _passwordError,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_passwordError != null || _serverError != null) {
                  setState(() {
                    _passwordError = null;
                    _serverError = null;
                  });
                }
              },
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Password is required.' : null,
            ),
            const SizedBox(height: 22),
            TFButton(
              label: _submitting ? 'Signing in…' : 'Sign in',
              size: TFButtonSize.lg,
              expand: true,
              loading: _submitting,
              onPressed: _submit,
            ),
            AnimatedSize(
              duration: TF.dur,
              curve: TF.ease,
              alignment: Alignment.topCenter,
              child: requestIsSlow
                  ? const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: WakingServerHint())
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 20),
            _DemoAccountCard(
                email: _demoEmail, onUse: _submitting ? null : _fillDemo),
          ]),
        ),
      ),
    );
  }
}

/// Dashed "terminal" panel offering the seeded demo credentials.
class _DemoAccountCard extends StatelessWidget {
  const _DemoAccountCard({required this.email, required this.onUse});
  final String email;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: TF.bgElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(TF.radiusMd),
        border: Border.all(color: TF.borderSubtle),
      ),
      child: Row(children: [
        const Icon(Icons.terminal_rounded, size: 16, color: TF.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DEMO ACCOUNT', style: TFText.eyebrow()),
            const SizedBox(height: 3),
            Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: TFText.mono(size: 12, color: TF.textSecondary),
            ),
          ]),
        ),
        TFButton(
          label: 'Use demo',
          icon: Icons.bolt_rounded,
          variant: TFButtonVariant.secondary,
          size: TFButtonSize.sm,
          onPressed: onUse,
        ),
      ]),
    ).animate().fadeIn(delay: 500.ms, duration: 400.ms);
  }
}
