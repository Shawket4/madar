import 'package:flutter/foundation.dart';
import 'package:rust_bridge/src/failure.dart';
import 'package:rust_bridge/src/generated/api/bridge.dart';
import 'package:rust_bridge/src/generated/api/error.dart';

/// A message a notifier keeps in its state for a screen to show LATER.
///
/// A notifier used to resolve its words the moment something failed and keep
/// the finished sentence (`error: bridge.tr(key: 'err.generic')`). The screen
/// then re-rendered that sentence on every language switch — so an Arabic
/// teller who had seen a failure in English kept reading English until the
/// next failure replaced it. State holds WHAT to say; the screen, which is
/// rebuilt on a language switch, decides how to say it.
@immutable
final class UiText {
  /// A core i18n key, resolved at render.
  const UiText.key(String this._key) : _error = null, _raw = null;

  /// A core failure, humanised at render ([MadarErrorMessage.humanMessage]).
  const UiText.error(MadarError this._error) : _key = null, _raw = null;

  /// Text that is not ours to translate — a server's own sentence, a name.
  const UiText.raw(String this._raw) : _key = null, _error = null;

  final String? _key;
  final MadarError? _error;
  final String? _raw;

  /// The words, in the language the bridge answers in right now.
  String of(MadarBridge bridge) {
    if (_key case final k?) return bridge.tr(key: k);
    if (_error case final e?) return bridge.humanMessage(e);
    return _raw ?? '';
  }

  @override
  bool operator ==(Object other) =>
      other is UiText &&
      other._key == _key &&
      other._error == _error &&
      other._raw == _raw;

  @override
  int get hashCode => Object.hash(_key, _error, _raw);

  @override
  String toString() => 'UiText(${_key ?? _error ?? _raw})';
}
