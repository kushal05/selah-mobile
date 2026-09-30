// The reset screen must not promise an email it did not send.
//
// `forgotPassword` returns false both when the request throws and when the
// server rejects it. The screen discarded that and played its success panel
// either way — "Check your email", over a request that never left the device.
// The user then waits for a link that is not coming, and the one thing that
// would tell them otherwise is the thing that was thrown away.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/features/auth/presentation/providers/auth_providers.dart';
import 'package:notify/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:notify/l10n/l10n.dart';

/// An AuthNotifier whose reset request reports a fixed outcome, so the screen's
/// handling of it can be tested without a server.
class _FixedAuth extends AuthNotifier {
  _FixedAuth(super.ref, this._result);
  final bool _result;

  @override
  Future<bool> forgotPassword(String email) async => _result;
}

Future<void> _pump(WidgetTester tester, {required bool sent}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith((ref) => _FixedAuth(ref, sent)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ForgotPasswordScreen(),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));

  await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
  await tester.pump();
  await tester.tap(find.text('Send reset link'));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Which side of the crossfade is actually shown.
///
/// Not find.text: AnimatedCrossFade builds both children and fades between
/// them, so the success panel's words are in the tree either way. Asserting on
/// their presence passed with the bug still in place — the state driving the
/// fade is the thing that was wrong, so the state is what to read.
CrossFadeState _shown(WidgetTester tester) =>
    tester.widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
        .crossFadeState;

void main() {
  testWidgets('a rejected request does not claim the email was sent', (
    tester,
  ) async {
    await _pump(tester, sent: false);

    expect(_shown(tester), CrossFadeState.showFirst,
        reason: 'the form stays up; the success panel must not play');
    expect(
      find.text("Couldn't send a reset link. Check the address and your "
          'connection, then try again.'),
      findsOneWidget,
      reason: 'and the user is told why',
    );
  });

  testWidgets('a successful request does show the confirmation', (
    tester,
  ) async {
    await _pump(tester, sent: true);

    expect(_shown(tester), CrossFadeState.showSecond);
    expect(find.textContaining("Couldn't send a reset link"), findsNothing);
  });
}
