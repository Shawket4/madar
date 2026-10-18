// The driver for `integration_test/perf_test.dart`: writes every flow's frame
// summary (build / raster p90, p99, worst, frames over budget) to
// `build/integration_response_data.json`.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
