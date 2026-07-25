import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/widgets.dart';
import 'auth_scaffold.dart';

/// Account creation (web `RegisterForm`). Field-level errors returned by the
/// API are mapped back onto the matching inputs.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SlowRequestTracker<RegisterScreen> {
  static final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static const _fields = [
    'first_name',
    'last_name',
    'email',
    'password',
    'password_confirm'
  ];

  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _submitting = false;
  String? _serverError;
  final Map<String, String?> _fieldErrors = {};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _clearError(String field) {
    if (_fieldErrors[field] != null || _serverError != null) {
      setState(() {
        _fieldErrors.remove(field);
        _serverError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _serverError = null;
      _fieldErrors.clear();
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.mediumImpact();
      return;
    }

    setState(() => _submitting = true);
    try {
      await trackSlow(() => ref.read(authProvider.notifier).register(
            email: _email.text,
            firstName: _firstName.text,
            lastName: _lastName.text,
            password: _password.text,
            passwordConfirm: _confirm.text,
          ));
      TextInput.finishAutofillContext();
      // Router redirect takes over from here.
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        var mapped = false;
        for (final f in _fields) {
          final msg = e.fieldError(f);
          if (msg != null) {
            _fieldErrors[f] = msg;
            mapped = true;
          }
        }
        if (!mapped) _serverError = e.friendly;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      eyebrow: 'New account',
      title: 'Create your account',
      subtitle: 'Start managing projects with your team',
      footer: AuthSwitchLink(
        prompt: 'Already have an account?',
        action: 'Sign in',
        onTap: () => context.pushReplacement('/login'),
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
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TFTextField(
                  label: 'First name',
                  hint: 'Jane',
                  controller: _firstName,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.givenName],
                  errorText: _fieldErrors['first_name'],
                  onChanged: (_) => _clearError('first_name'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'First name is required.'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TFTextField(
                  label: 'Last name',
                  hint: 'Doe',
                  controller: _lastName,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.familyName],
                  errorText: _fieldErrors['last_name'],
                  onChanged: (_) => _clearError('last_name'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Last name is required.'
                      : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TFTextField(
              label: 'Email address',
              hint: 'you@example.com',
              controller: _email,
              enabled: !_submitting,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              prefixIcon: Icons.alternate_email_rounded,
              errorText: _fieldErrors['email'],
              onChanged: (_) => _clearError('email'),
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
              hint: 'Min. 8 characters',
              controller: _password,
              enabled: !_submitting,
              obscure: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              prefixIcon: Icons.lock_outline_rounded,
              errorText: _fieldErrors['password'],
              onChanged: (_) {
                _clearError('password');
                setState(() {}); // refresh strength meter
              },
              validator: (v) => (v ?? '').length < 8
                  ? 'Password must be at least 8 characters.'
                  : null,
            ),
            const SizedBox(height: 10),
            PasswordStrengthMeter(password: _password.text),
            const SizedBox(height: 16),
            TFTextField(
              label: 'Confirm password',
              hint: 'Repeat your password',
              controller: _confirm,
              enabled: !_submitting,
              obscure: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              prefixIcon: Icons.lock_reset_rounded,
              errorText: _fieldErrors['password_confirm'],
              onChanged: (_) => _clearError('password_confirm'),
              onSubmitted: (_) => _submit(),
              validator: (v) {
                if ((v ?? '').isEmpty) return 'Please confirm your password.';
                if (v != _password.text) return 'Passwords do not match.';
                return null;
              },
            ),
            const SizedBox(height: 22),
            TFButton(
              label: _submitting ? 'Creating account…' : 'Create account',
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
            const SizedBox(height: 14),
            Text(
              'By creating an account you can create or join organizations and start forging projects.',
              textAlign: TextAlign.center,
              style: TFText.small(color: TF.textDisabled),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Four-segment animated password strength meter with a mono label.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});
  final String password;

  /// 0 = empty, 1 = weak … 4 = strong.
  static int score(String p) {
    if (p.isEmpty) return 0;
    if (p.length < 8) return 1;
    var s = 1;
    if (p.length >= 12) s++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s > 4 ? 4 : s;
  }

  @override
  Widget build(BuildContext context) {
    final s = score(password);
    final (String label, Color color) = switch (s) {
      0 => ('Must be at least 8 characters', TF.textDisabled),
      1 => (password.length < 8 ? 'Too short' : 'Weak', TF.danger),
      2 => ('Fair', TF.brand),
      3 => ('Good', TF.info),
      _ => ('Strong', TF.success),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: AnimatedContainer(
              duration: TF.durSlow,
              curve: TF.ease,
              height: 3,
              decoration: BoxDecoration(
                color: i < s ? color : TF.borderDefault,
                borderRadius: BorderRadius.circular(TF.radiusSm),
                boxShadow: i < s && s == 4
                    ? [
                        BoxShadow(
                            color: color.withValues(alpha: 0.45), blurRadius: 6)
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 6),
      AnimatedSwitcher(
        duration: TF.dur,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        ),
        child: Row(
          key: ValueKey(label),
          children: [
            Text(
              s == 0 ? 'STRENGTH' : 'STRENGTH · ',
              style: TFText.mono(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: TF.textMuted,
                  letterSpacing: 1.2),
            ),
            if (s == 0) const SizedBox(width: 8),
            Flexible(
              child: Text(
                s == 0 ? label : label.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: s == 0
                    ? TFText.small(color: TF.textDisabled)
                    : TFText.mono(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: color,
                        letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}
