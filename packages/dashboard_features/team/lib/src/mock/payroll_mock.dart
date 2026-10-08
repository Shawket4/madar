/// The mock backend of the Payroll incl. the money sheets (`/staff/payroll`, TEAM-PAY and TEAM-MNY rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/payroll/current`
/// - `GET|POST /staff/payroll/periods`
/// - `DELETE /staff/payroll/periods/{id}`
/// - `POST /staff/payroll/periods/{id}/generate`
/// - `GET /staff/payroll/periods/{id}/payslips`
/// - `GET /staff/payroll/periods/{id}/preview`
/// - `GET /staff/payroll/periods/{id}/export.csv`
/// - `PATCH /staff/payroll/periods/{id}/payslips/{employee_id}/paid`
/// - `PATCH /staff/payroll/periods/{id}/status`
/// - `GET /staff/payroll/bonuses`
/// - `DELETE /staff/payroll/bonuses/{id}`
/// - `GET /staff/payroll/deductions`
/// - `DELETE /staff/payroll/deductions/{id}`
/// - `PATCH /staff/payroll/deductions/{id}/override|waive|unwaive`
/// - `GET|POST /staff/payroll/advances` (the list is shared: team_reads_mock.dart)
/// - `POST /staff/advances/record`
/// - `PATCH /staff/advances/{id}/review`
/// - `GET|POST /staff/adjustments` (the list is shared: team_reads_mock.dart)
/// - `PATCH /staff/adjustments/{kind}/{id}/decision`
/// - `POST /staff/adjustments/{kind}/{id}/stop`
/// - `GET|POST /staff/expense-advances`
/// - `PATCH|DELETE /staff/expense-advances/{id}`
///
/// Read and extend the area seed's tables (`TeamTables`, `TeamSeed`); behave
/// like the backend (capability refusals, validation, state).
library;

import 'package:dashboard_api/mock.dart';

void registerPayrollMocks(MockServer server, MockDb db) {}
