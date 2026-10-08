import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controls.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// The clock vocabulary of the web's input kit (`inputs/time.ts`): reading
/// what a person typed and the wire's `HH:MM`.
abstract final class DashTime {
  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Arabic-Indic and Persian digits to Latin.
  static String latinDigits(String s) =>
      s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
        final u = m.group(0)!.codeUnitAt(0);
        return '${u >= 0x06f0 ? u - 0x06f0 : u - 0x0660}';
      });

  /// `HH:MM[:SS]` → `HH:MM`, or `''`.
  static String toHHMM(String? v) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v ?? '');
    if (m == null) return '';
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    return h <= 23 && min <= 59 ? '${_pad(h)}:${_pad(min)}' : '';
  }

  /// Minutes since midnight, or null.
  static int? minutesOf(String? v) {
    final s = toHHMM(v);
    if (s.isEmpty) return null;
    return int.parse(s.substring(0, 2)) * 60 + int.parse(s.substring(3, 5));
  }

  /// Minutes → `HH:MM`, wrapping the day.
  static String hhmmOf(int minutes) {
    final m = ((minutes % 1440) + 1440) % 1440;
    return '${_pad(m ~/ 60)}:${_pad(m % 60)}';
  }

  static final _am = RegExp(r'^(a|am|ص|صباحا|صباحًا|صباح)$');
  static final _pm = RegExp(r'^(p|pm|م|مساء|مساءً|مساءا)$');

  /// Read a time the way people type one (`930`, `9:30p`, `21:30`,
  /// `٩:٣٠ م`); `HH:MM` or null. Empty is null.
  static String? parse(String raw) {
    var s = latinDigits(
      raw,
    ).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAllMapped(
      RegExp(r'([ap])\.\s?m\.?$'),
      (m) => '${m.group(1)}m',
    );
    s = s.replaceAllMapped(
      RegExp(r'([ap])m?\.$'),
      (m) => m.group(0)!.substring(0, m.group(0)!.length - 1),
    );
    if (s.isEmpty) return null;
    String? meridiem;
    final tail = RegExp(r'^(.*?[0-9])\s*([^\d\s:.,٫]+)$').firstMatch(s);
    if (tail != null) {
      final word = tail.group(2)!.replaceAll(' ', '');
      if (_am.hasMatch(word)) {
        meridiem = 'am';
      } else if (_pm.hasMatch(word)) {
        meridiem = 'pm';
      } else {
        return null;
      }
      s = tail.group(1)!.trim();
    }
    int h;
    int m;
    final sep = RegExp(r'^(\d{1,2})\s*[:.,٫ ]\s*(\d{2})$').firstMatch(s);
    if (sep != null) {
      h = int.parse(sep.group(1)!);
      m = int.parse(sep.group(2)!);
    } else if (RegExp(r'^\d{1,4}$').hasMatch(s)) {
      if (s.length <= 2) {
        h = int.parse(s);
        m = 0;
      } else {
        h = int.parse(s.substring(0, s.length - 2));
        m = int.parse(s.substring(s.length - 2));
      }
    } else {
      return null;
    }
    if (m > 59) return null;
    if (meridiem != null) {
      if (h < 1 || h > 12) return null;
      if (meridiem == 'am') {
        h = h == 12 ? 0 : h;
      } else {
        h = h == 12 ? 12 : h + 12;
      }
    } else if (h == 24 && m == 0) {
      h = 0;
    } else if (h > 23) {
      return null;
    }
    return '${_pad(h)}:${_pad(m)}';
  }

  /// Quick-pick slots every [step] minutes.
  static List<String> slots([int step = 15]) => [
    for (var i = 0; i * step < 1440; i++) hhmmOf(i * step),
  ];

  /// The slot nearest [minutes].
  static String nearestSlot(int minutes, [int step = 15]) =>
      hhmmOf((minutes / step).round() * step);
}

/// A time of day you can type or pick (the web's `TimeField`): type it the
/// way you'd say it and it reads back on the app's 12-hour clock, or pick a
/// quarter hour from the list. Unreadable text stays on show in the invalid
/// state and reaches [onChanged] as typed, so a save refuses it.
class DashTimeField extends StatefulWidget {
  const DashTimeField({
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.semanticLabel,
    this.clearable = false,
    this.step = 15,
    this.h12 = true,
    this.invalid = false,
    this.enabled = true,
    this.anchorMinutes,
    this.describeOption,
    super.key,
  });

  /// `HH:MM` (seconds tolerated) or `''`.
  final String? value;

  /// `HH:MM`, `''` when cleared, or the unreadable text as typed.
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final String? semanticLabel;
  final bool clearable;
  final int step;
  final bool h12;
  final bool invalid;
  final bool enabled;

  /// Where the list opens with no value (defaults to now).
  final int? anchorMinutes;

  /// Extra text beside a pick (the shift length for an end time).
  final String? Function(String hhmm)? describeOption;

  @override
  State<DashTimeField> createState() => _DashTimeFieldState();
}

class _DashTimeFieldState extends State<DashTimeField> {
  final _popover = DashPopoverController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _draft;
  String? _bad;

  String get _current => DashTime.toHHMM(widget.value);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _settle();
    });
  }

  @override
  void dispose() {
    _popover.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _commit(String hhmm) {
    setState(() {
      _draft = null;
      _bad = null;
    });
    if (hhmm != _current) widget.onChanged(hhmm);
  }

  void _settle() {
    final d = _draft;
    if (d == null) return;
    final text = d.trim();
    if (text.isEmpty) {
      if (widget.clearable) {
        _commit('');
      } else {
        setState(() {
          _draft = null;
          _bad = null;
        });
      }
      return;
    }
    final parsed = DashTime.parse(text);
    if (parsed != null) {
      _commit(parsed);
    } else {
      setState(() => _bad = text);
      if (text != _current) widget.onChanged(text);
    }
  }

  void _open() {
    _popover.open();
    final now = TimeOfDay.now();
    final target = _current.isNotEmpty
        ? _current
        : DashTime.nearestSlot(
            widget.anchorMinutes ?? now.hour * 60 + now.minute,
            widget.step,
          );
    final i = DashTime.slots(widget.step).indexOf(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && i >= 0) {
        final rowH = DashMetrics.target - Space.xs;
        _scroll.jumpTo(
          (i * rowH - Space.xxl * 3).clamp(0, _scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final f = context.dashFormats;
    final shown = _current.isEmpty ? '' : f.time(_current, h12: widget.h12);
    final typed = _draft == null ? null : DashTime.parse(_draft!);
    final slots = DashTime.slots(widget.step);
    final rows = typed != null && !slots.contains(typed)
        ? [typed, ...slots]
        : slots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DashPopover(
          controller: _popover,
          matchAnchorWidth: true,
          width: DashMetrics.menu - Space.xxl,
          maxHeight: 264,
          autofocusContent: false,
          anchor: (context, ctl) => GestureDetector(
            onTap: widget.enabled ? _open : null,
            child: DashTextInput(
              value: _draft ?? shown,
              focusNode: _focus,
              enabled: widget.enabled,
              invalid: widget.invalid || _bad != null,
              semanticLabel: widget.semanticLabel,
              leadingIcon: 'clock',
              mono: false,
              selectAllOnFocus: true,
              placeholder:
                  widget.placeholder ??
                  (widget.h12 ? t.timePlaceholder : '09:30'),
              onChanged: (v) {
                setState(() {
                  _draft = v;
                  _bad = null;
                });
                if (!_popover.isOpen) _open();
              },
              onSubmitted: (_) {
                _settle();
                _popover.close();
              },
              onKeyEvent: (node, e) {
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _open();
                  return KeyEventResult.handled;
                }
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.escape) {
                  if (_popover.isOpen) {
                    _popover.close();
                  } else {
                    setState(() => _draft = null);
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              trailing:
                  widget.clearable && _current.isNotEmpty && widget.enabled
                  ? DashPressable(
                      onTap: () {
                        setState(() {
                          _draft = null;
                          _bad = null;
                        });
                        widget.onChanged('');
                      },
                      semanticLabel: t.clearTime,
                      excludeChildSemantics: true,
                      builder: (context, s) => SizedBox.square(
                        dimension: Space.xl,
                        child: Center(
                          child: DashIcon(
                            'x',
                            size: IconSize.xs,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          content: (context, ctl) => Semantics(
            label: widget.semanticLabel ?? t.times,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(Space.xs),
              itemCount: rows.length,
              itemExtent: DashMetrics.target - Space.xs,
              itemBuilder: (context, i) {
                final hhmm = rows[i];
                final selected = hhmm == _current;
                final extra = widget.describeOption?.call(hhmm);
                return DashPressable(
                  onTap: () {
                    _commit(hhmm);
                    ctl.close();
                  },
                  selected: selected,
                  pressScale: false,
                  semanticLabel: f.time(hhmm, h12: widget.h12),
                  excludeChildSemantics: true,
                  builder: (context, s) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm + DashMetrics.hair,
                    ),
                    decoration: BoxDecoration(
                      color: s.highlighted || hhmm == typed ? c.hover : null,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Row(
                      children: [
                        Text(
                          MadarFormat.isolate(f.time(hhmm, h12: widget.h12)),
                          style: DashType.body.copyWith(
                            color: c.textPrimary,
                            fontWeight: selected ? FontWeight.w600 : null,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Spacer(),
                        if (extra != null)
                          Text(
                            extra,
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (_bad != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Semantics(
              liveRegion: true,
              child: Text(
                t.timeUnreadable(_bad!),
                style: DashType.small.copyWith(color: c.errorText),
              ),
            ),
          ),
      ],
    );
  }
}
