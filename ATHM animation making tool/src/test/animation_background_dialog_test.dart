import 'package:animaker/features/language_anim/presentation/animation_background_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers character background editor next to inherit', (
    tester,
  ) async {
    AnimationBackgroundSelection? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<AnimationBackgroundSelection>(
                context: context,
                builder: (_) => const AnimationBackgroundDialog(
                  candidatesByName: {},
                  currentValue: null,
                  inheritedName: 'JM_BG',
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Inherit character background'), findsOneWidget);
    expect(find.text('Set character background'), findsOneWidget);
    expect(find.text('Current: JM_BG'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Set character background')).dy,
      lessThan(tester.getTopLeft(find.text('Inherit character background')).dy),
    );

    await tester.tap(find.text('Set character background'));
    await tester.pumpAndSettle();

    expect(result?.type, AnimationBackgroundSelectionType.setCharacter);
  });
}
