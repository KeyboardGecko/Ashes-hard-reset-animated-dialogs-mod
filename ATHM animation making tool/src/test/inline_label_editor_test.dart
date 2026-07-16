import 'package:animaker/widgets/inline_label_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('label field keeps taps from the surrounding frame card', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var cardTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => cardTaps++,
            child: InlineLabelEditor(
              initial: 'OLD',
              focusNode: focusNode,
              onChangedCommitted: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(cardTaps, 0);
  });
}
