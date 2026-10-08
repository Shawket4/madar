// Host-side gate for the dashboard bridge's transport and xlsx surface: loads
// the cargo-built library and drives `xlsx_write` / `xlsx_read`, and an
// `api_request` / `api_stream` to a port nothing listens on, so every new type
// crosses the FFI both ways without a backend. Build the library first:
//   cargo build -p madar_frb_dashboard --release --manifest-path rust-core/Cargo.toml
// or point MADAR_DASHBOARD_DYLIB at a build (a debug one is fine).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

File _library() {
  final explicit = Platform.environment['MADAR_DASHBOARD_DYLIB'];
  if (explicit != null && explicit.isNotEmpty) return File(explicit);
  final name = Platform.isWindows
      ? 'madar_frb_dashboard.dll'
      : Platform.isMacOS
      ? 'libmadar_frb_dashboard.dylib'
      : 'libmadar_frb_dashboard.so';
  return File('${Directory.current.path}/../../rust-core/target/release/$name');
}

ApiCall _call(String method, String path) => ApiCall(
  method: method,
  path: path,
  query: const [ApiPair(key: 'page', value: '1')],
  headers: const [],
  jsonBody: '{"a":1}',
  formFields: const [],
  files: const [],
);

void main() {
  final library = _library();
  if (!library.existsSync()) {
    test('dashboard transport smoke (skipped: no library)', () {
      markTestSkipped('Looked for ${library.path}');
    });
    return;
  }

  setUpAll(() => MadarCore.initForTest(dylibPath: library.path));

  test('a workbook round-trips through the core', () async {
    final spec = {
      'creator': 'Madar',
      'rtl': true,
      'sheets': [
        {
          'name': 'الطلبات',
          'title': 'الطلبات',
          'subtitle': 'تم الإنشاء: 08 أكتوبر 2026',
          'columns': [
            {'header': 'الطلب', 'width': 14, 'num_fmt': null},
            {'header': 'الإجمالي', 'width': 20, 'num_fmt': '#,##0.00 "EGP"'},
          ],
          'padding_widths': [18, 18, 18, 18],
          'stats': <Object?>[],
          'rows': [
            ['HEL-0001', 125.5],
            ['HEL-0002', 40],
          ],
          'totals_row': [
            'الإجماليات',
            {'formula': 'SUM(B8:B9)'},
          ],
          'header_row': 7,
          'first_data_row': 8,
        },
      ],
    };
    final bytes = await xlsxWrite(specJson: jsonEncode(spec));
    expect(bytes.sublist(0, 2), [0x50, 0x4B], reason: 'an xlsx is a zip');
    final sheets = jsonDecode(await xlsxRead(bytes: bytes)) as List<Object?>;
    final sheet = sheets.single! as Map<String, Object?>;
    expect(sheet['name'], 'الطلبات');
    final rows = sheet['rows']! as List<Object?>;
    expect(rows.first, ['الطلبات']);
    expect(rows.last, ['الإجماليات', 165.5]);
  });

  test("a bad spec is the core's validation error", () async {
    await expectLater(
      xlsxWrite(specJson: '{"sheets": 3}'),
      throwsA(isA<MadarError_Validation>()),
    );
  });

  test("a call nobody answers is an ApiFailure in the core's words", () async {
    final core = await MadarCore.start(
      config: const MadarConfig(
        baseUrl: 'http://127.0.0.1:9',
        environment: 'dev',
        dbPath: '',
        locale: 'ar',
      ),
    );
    await expectLater(
      core.bridge.apiRequest(call: _call('GET', '/orders')),
      throwsA(
        isA<ApiFailure>()
            .having((f) => f.status, 'status', 0)
            .having((f) => f.kind, 'kind', ApiFailureKind.offline)
            .having(
              (f) => f.message,
              'message',
              'خطأ في الشبكة — يرجى التحقق من الاتصال.',
            ),
      ),
    );
    final items = await core.bridge
        .apiStream(call: _call('GET', '/realtime/stream'), streamId: 's1')
        .toList();
    expect(items, hasLength(1));
    expect(items.single.opened, isFalse);
    expect(items.single.failure?.kind, ApiFailureKind.offline);
    core.bridge.apiStreamCancel(streamId: 's1');
  });
}
