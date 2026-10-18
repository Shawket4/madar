// Typing a key at a time, as a person does: `tester.enterText` replaces the
// whole text in one edit, so it cannot catch a box that loses focus (or is
// rebuilt as a new box) after the first character.
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text of the box [box] (an accessible name or the box itself).
String fieldText(WidgetTester tester, Finder box) =>
    tester.widget<EditableText>(_editable(box)).controller.text;

Finder _editable(Finder box) => find
    .descendant(of: box, matching: find.byType(EditableText), matchRoot: true)
    .first;

/// One box being typed into: it is focused once, then every key is sent to
/// whichever box holds the keyboard, and the session checks that this is
/// still the same box.
class TypingSession {
  TypingSession._(this._h, this._state, this._label);

  final DashHarness _h;
  final EditableTextState _state;
  final String? _label;

  /// Focuses [box] (a tap) and opens the keyboard on it.
  static Future<TypingSession> start(DashHarness h, Finder box) async {
    final field = _editable(box);
    await h.tester.showKeyboard(field);
    await h.settle(rounds: 2);
    final state = h.tester.state<EditableTextState>(field);
    final label = _labelOf(state.context);
    final session = TypingSession._(h, state, label);
    session.expectFocusHeld();
    return session;
  }

  /// The box's text now.
  String get text => _state.widget.controller.text;

  /// The accessible name of the box that has focus now.
  String? get focusedLabel {
    for (final e in find.byType(EditableText).evaluate()) {
      final w = e.widget as EditableText;
      if (w.focusNode.hasFocus) return _labelOf(e);
    }
    return null;
  }

  static String? _labelOf(BuildContext context) {
    String? label;
    context.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Semantics && w.properties.label != null) {
        label = w.properties.label;
        return false;
      }
      return true;
    });
    return label;
  }

  /// Types [chars] one key at a time after what the box holds (its caret at
  /// the end), checking after every key that the box kept its focus.
  Future<void> type(String chars) async {
    for (final ch in chars.split('')) {
      // A focused box selects its text: the first key replaces a selection.
      final sel = _state.textEditingValue.selection;
      final before = text;
      final next = sel.isValid && !sel.isCollapsed
          ? before.replaceRange(sel.start, sel.end, ch)
          : before + ch;
      await _send(next);
      expectFocusHeld();
    }
  }

  /// Deletes everything in the box (select all, then delete).
  Future<void> clear() => _send('');

  Future<void> _send(String value) async {
    _h.tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    await _h.settle(rounds: 2);
  }

  /// The box typed into is still mounted, still the same box, still focused
  /// and still the keyboard's target, and it is still the cell it was.
  void expectFocusHeld() {
    expect(_state.mounted, isTrue, reason: 'the box was rebuilt as a new one');
    expect(
      _state.widget.focusNode.hasFocus,
      isTrue,
      reason: 'the box lost focus',
    );
    expect(focusedLabel, _label, reason: 'focus moved to another cell');
    expect(_label, isNotNull);
    expect(
      _labelOf(_state.context),
      _label,
      reason: 'the focused box now shows another cell',
    );
  }
}
