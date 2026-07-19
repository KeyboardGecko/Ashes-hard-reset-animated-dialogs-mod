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

  testWidgets('deferred hotkey refocus does not steal the next label focus', (
    tester,
  ) async {
    final firstFocus = FocusNode();
    final secondFocus = FocusNode();
    final hotkeyFocus = FocusNode();
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);
    addTearDown(hotkeyFocus.dispose);

    void deferHotkeyRefocus() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isEditableTextFocused()) hotkeyFocus.requestFocus();
      });
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: hotkeyFocus, child: const SizedBox()),
              InlineLabelEditor(
                initial: 'FIRST',
                focusNode: firstFocus,
                onChangedCommitted: (_) => deferHotkeyRefocus(),
              ),
              InlineLabelEditor(
                initial: 'SECOND',
                focusNode: secondFocus,
                onChangedCommitted: (_) => deferHotkeyRefocus(),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(firstFocus.hasFocus, isTrue);

    await tester.tap(find.byType(TextField).last);
    await tester.pump();

    expect(secondFocus.hasFocus, isTrue);
    expect(hotkeyFocus.hasFocus, isFalse);
  });

  testWidgets('label accepts focus after its list row is recycled', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final keys = <int, GlobalKey<InlineLabelEditorState>>{
      for (var index = 0; index < 20; index++)
        index: GlobalKey<InlineLabelEditorState>(),
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 180,
            child: ListView.builder(
              controller: scrollController,
              itemExtent: 72,
              itemCount: 20,
              itemBuilder: (context, index) => InlineLabelEditor(
                key: keys[index],
                initial: 'LABEL $index',
                onChangedCommitted: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(keys[1]!.currentState, isNotNull);
    scrollController.jumpTo(15 * 72);
    await tester.pump();
    expect(keys[1]!.currentState, isNull);

    scrollController.jumpTo(72);
    await tester.pump();
    expect(keys[1]!.currentState, isNotNull);

    await tester.tap(find.text('LABEL 1'));
    await tester.pump();

    expect(keys[1]!.currentState!.hasFocus, isTrue);
  });
}
