// Imports every generated library so a compile error in generated code fails
// this test (lib/src/generated is excluded from lint, never from compilation).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/src/generated/apis.dart' as apis;
import 'package:dashboard_api/src/generated/facade.dart' as facade;
import 'package:dashboard_api/src/generated/mock_capabilities.dart' as caps;
import 'package:dashboard_api/src/generated/models.dart' as models;
import 'package:dashboard_api/src/generated/operations.dart' as ops;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generated libraries load', () {
    expect(ops.apiOperations, isNotEmpty);
    expect(caps.mockCapabilities, isNotEmpty);
    expect(facade.DashboardApi, isNotNull);
    expect(apis.OrdersApi, isNotNull);
    expect(models.Branch, isNotNull);
    expect(apiOperations.length, ops.apiOperations.length);
  });
}
