# \StaffApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**accept_staff_privacy**](StaffApi.md#accept_staff_privacy) | **POST** /staff/me/privacy | The employee accepted the location notice on this phone (AT-5). Kept on the device row: a new phone asks again.
[**advances**](StaffApi.md#advances) | **GET** /staff/reports/advances | Advances given in range, and what is still owed.
[**answer_swap**](StaffApi.md#answer_swap) | **PATCH** /staff/me/swaps/{id} | The colleague agrees or declines.
[**ask_swap**](StaffApi.md#ask_swap) | **POST** /staff/me/swaps | Ask a colleague to swap: they agree first, then the manager (SC-8). Both shifts must be on the published roster, ahead, at a branch both work at, and must fit where they land.
[**attendance_summary**](StaffApi.md#attendance_summary) | **GET** /staff/attendance/summary | 
[**branch_people**](StaffApi.md#branch_people) | **GET** /staff/branches/{branch_id}/people | Active employees at a branch, names only: what a till shows to tag a pay-out as someone's expense advance (AV-8). Anyone who works the branch may read it; nothing about pay is in it.
[**cancel_open_shift**](StaffApi.md#cancel_open_shift) | **POST** /staff/open-shifts/{id}/cancel | Take an open shift back (open or claimed, never filled). A claimer hears.
[**cancel_swap**](StaffApi.md#cancel_swap) | **POST** /staff/me/swaps/{id}/cancel | The one who asked takes it back before the manager decides.
[**check_in**](StaffApi.md#check_in) | **POST** /staff/me/check-in | 
[**check_out**](StaffApi.md#check_out) | **POST** /staff/me/check-out | 
[**claim_open_shift**](StaffApi.md#claim_open_shift) | **POST** /staff/open-shifts/{id}/claim | Claim an open shift; the manager approves the claim (SC-9). Only a published week's, and only one that fits beside the person's own shifts.
[**correct_record**](StaffApi.md#correct_record) | **PATCH** /staff/attendance/{id} | 
[**create_adjustment**](StaffApi.md#create_adjustment) | **POST** /staff/adjustments | Add a bonus or deduction. Over the caller's limit it is created pending and waits for the owner (AD-5). Bonuses and deductions have separate limits.
[**create_advance_admin**](StaffApi.md#create_advance_admin) | **POST** /staff/payroll/advances | Record an ask on someone's behalf: it still waits for a decision (`PATCH /staff/advances/{id}/review`). To hand one over at once, use `POST /staff/advances/record`.
[**create_assignment**](StaffApi.md#create_assignment) | **POST** /staff/schedules | 
[**create_department**](StaffApi.md#create_department) | **POST** /staff/departments | 
[**create_document**](StaffApi.md#create_document) | **POST** /staff/employees/{employee_id}/documents | 
[**create_employee**](StaffApi.md#create_employee) | **POST** /staff/employees | Add an employee: linked to an existing user, or without one (with or without the staff app). Used by the Employees page, the set-up wizard and the spreadsheet import (DSH-7). Never creates a login.
[**create_manual_record**](StaffApi.md#create_manual_record) | **POST** /staff/attendance | 
[**create_my_advance**](StaffApi.md#create_my_advance) | **POST** /staff/me/advances | 
[**create_my_request**](StaffApi.md#create_my_request) | **POST** /staff/me/requests | 
[**create_period**](StaffApi.md#create_period) | **POST** /staff/payroll/periods | 
[**create_request_admin**](StaffApi.md#create_request_admin) | **POST** /staff/requests | 
[**create_work_shift**](StaffApi.md#create_work_shift) | **POST** /staff/work-shifts | 
[**current**](StaffApi.md#current) | **GET** /staff/payroll/current | The running period with everyone's pay (PAY-1..PAY-5).
[**decide_adjustment**](StaffApi.md#decide_adjustment) | **PATCH** /staff/adjustments/{kind}/{id}/decision | The owner (or anyone whose limit covers it) decides a pending line. A percent line is judged at its value in piastres (audit B5).
[**decide_claim**](StaffApi.md#decide_claim) | **PATCH** /staff/open-shifts/{id}/decision | Approve a claim: the shift becomes theirs for that date, beside the rest of their day. Rejecting reopens it. One decision only.
[**decide_cover**](StaffApi.md#decide_cover) | **PATCH** /staff/attendance/{id}/cover | Confirm or reject a cover. Rejecting pays nothing (CV-5); the confirmer is neither person involved.
[**decide_holiday**](StaffApi.md#decide_holiday) | **PUT** /staff/holidays/{date} | 
[**decide_overtime**](StaffApi.md#decide_overtime) | **PATCH** /staff/attendance/{id}/overtime | Approve or reject a shift's overtime, within the approver's money limit.
[**decide_request**](StaffApi.md#decide_request) | **PATCH** /staff/requests/{id}/decision | 
[**decide_suggestion**](StaffApi.md#decide_suggestion) | **POST** /staff/roster/suggestions/decide | Accept (changes that date only) or reject; either way it is remembered. Only a suggestion the engine actually made for that branch-week is taken (a crafted id is refused), and accepting touches only the block it names.
[**decide_swap**](StaffApi.md#decide_swap) | **PATCH** /staff/swaps/{id}/decision | The manager approves: both rosters update for those dates (SC-8), in one transaction, once, and only if both shifts are still where they were.
[**delete_assignment**](StaffApi.md#delete_assignment) | **DELETE** /staff/schedules/{id} | 
[**delete_bonus**](StaffApi.md#delete_bonus) | **DELETE** /staff/payroll/bonuses/{id} | 
[**delete_branch_rules**](StaffApi.md#delete_branch_rules) | **DELETE** /staff/attendance/settings/branches/{branch_id} | 
[**delete_deduction**](StaffApi.md#delete_deduction) | **DELETE** /staff/payroll/deductions/{id} | 
[**delete_department**](StaffApi.md#delete_department) | **DELETE** /staff/departments/{id} | 
[**delete_document**](StaffApi.md#delete_document) | **DELETE** /staff/documents/{id} | 
[**delete_employee**](StaffApi.md#delete_employee) | **DELETE** /staff/employees/{employee_id} | 
[**delete_override**](StaffApi.md#delete_override) | **DELETE** /staff/schedules/overrides/{id} | Remove one row of a date's set: one block of a split day, or the date's last change (back to the pattern).
[**delete_period**](StaffApi.md#delete_period) | **DELETE** /staff/payroll/periods/{id} | Delete a DRAFT period. An approved month is reopened first (which is refused once anyone is paid), so a paid payslip can never be wiped (B3).
[**delete_record**](StaffApi.md#delete_record) | **DELETE** /staff/attendance/{id} | 
[**delete_work_shift**](StaffApi.md#delete_work_shift) | **DELETE** /staff/work-shifts/{id} | 
[**discipline_report**](StaffApi.md#discipline_report) | **GET** /staff/discipline-report | 
[**export_period_csv**](StaffApi.md#export_period_csv) | **GET** /staff/payroll/periods/{id}/export.csv | The generated period as a CSV: the bank file, the wallet list, or the whole run.
[**fairness**](StaffApi.md#fairness) | **GET** /staff/roster/fairness | Owner only, monthly: who works the nights, by gender, against who said they want them — for the business and branch by branch.
[**fairness_audits**](StaffApi.md#fairness_audits) | **GET** /staff/roster/fairness/audits | The kept monthly audits, newest first (owner).
[**generate_period**](StaffApi.md#generate_period) | **POST** /staff/payroll/periods/{id}/generate | Approve a DRAFT month: freeze every payslip and collect the advance installments in the ledger. An approved month is not regenerated — it is reopened (before anyone is paid) and approved again.
[**get_attendance_settings**](StaffApi.md#get_attendance_settings) | **GET** /staff/attendance/settings | 
[**get_coverage**](StaffApi.md#get_coverage) | **GET** /staff/roster/coverage | 
[**get_employee**](StaffApi.md#get_employee) | **GET** /staff/employees/{employee_id} | 
[**get_scheduled_day**](StaffApi.md#get_scheduled_day) | **GET** /staff/schedules/day | 
[**labour_vs_sales**](StaffApi.md#labour_vs_sales) | **GET** /staff/reports/labour-vs-sales | Labour cost vs sales, per branch and day. Only when POS is on (DSH-4).
[**linkable_users**](StaffApi.md#linkable_users) | **GET** /staff/employees/linkable | The org's users who are not employees yet: the \"make this user an employee\" picker.
[**list_adjustments**](StaffApi.md#list_adjustments) | **GET** /staff/adjustments | 
[**list_advances**](StaffApi.md#list_advances) | **GET** /staff/payroll/advances | 
[**list_assignments**](StaffApi.md#list_assignments) | **GET** /staff/schedules | 
[**list_attendance**](StaffApi.md#list_attendance) | **GET** /staff/attendance | 
[**list_attendance_flags**](StaffApi.md#list_attendance_flags) | **GET** /staff/flags | The flags a manager should look at, for their branches (RO-6).
[**list_audit**](StaffApi.md#list_audit) | **GET** /staff/payroll/audit | The money audit log: every delete, stop, waive, override, reopen and payment, with who and why (AD-9, AT-10).
[**list_bonuses**](StaffApi.md#list_bonuses) | **GET** /staff/payroll/bonuses | 
[**list_branch_rules**](StaffApi.md#list_branch_rules) | **GET** /staff/attendance/settings/branches | 
[**list_deductions**](StaffApi.md#list_deductions) | **GET** /staff/payroll/deductions | 
[**list_departments**](StaffApi.md#list_departments) | **GET** /staff/departments | 
[**list_documents**](StaffApi.md#list_documents) | **GET** /staff/employees/{employee_id}/documents | 
[**list_employees**](StaffApi.md#list_employees) | **GET** /staff/employees | 
[**list_expense_advances**](StaffApi.md#list_expense_advances) | **GET** /staff/expense-advances | 
[**list_open_shifts**](StaffApi.md#list_open_shifts) | **GET** /staff/open-shifts | Open shifts and their claims at the branches I run (SC-9) — the dashboard's approvals queue and schedule.
[**list_payslips**](StaffApi.md#list_payslips) | **GET** /staff/payroll/periods/{id}/payslips | 
[**list_periods**](StaffApi.md#list_periods) | **GET** /staff/payroll/periods | 
[**list_requests**](StaffApi.md#list_requests) | **GET** /staff/requests | 
[**list_swaps**](StaffApi.md#list_swaps) | **GET** /staff/swaps | 
[**list_work_shifts**](StaffApi.md#list_work_shifts) | **GET** /staff/work-shifts | 
[**log_expense_advance**](StaffApi.md#log_expense_advance) | **POST** /staff/expense-advances | 
[**mark_paid**](StaffApi.md#mark_paid) | **PATCH** /staff/payroll/periods/{id}/payslips/{employee_id}/paid | Mark one payslip paid; the period is paid once everyone is (PAY-7).
[**move_shift**](StaffApi.md#move_shift) | **POST** /staff/schedules/days/move | Give one person's shift on a date to someone else; both keep the rest of their day.
[**my_adjustments**](StaffApi.md#my_adjustments) | **GET** /staff/me/adjustments | 
[**my_advances**](StaffApi.md#my_advances) | **GET** /staff/me/advances | 
[**my_attendance**](StaffApi.md#my_attendance) | **GET** /staff/me/attendance | 
[**my_context**](StaffApi.md#my_context) | **GET** /staff/me/context | 
[**my_coverable**](StaffApi.md#my_coverable) | **GET** /staff/me/coverable | 
[**my_estimate**](StaffApi.md#my_estimate) | **GET** /staff/me/pay/estimate | What I've earned so far this period.
[**my_expense_advances**](StaffApi.md#my_expense_advances) | **GET** /staff/me/expense-advances | 
[**my_leave_balances**](StaffApi.md#my_leave_balances) | **GET** /staff/me/leave-balances | Deprecated (RQ-3): Dawam has no leave balances. This shows what older data holds and is never written any more.
[**my_notifications**](StaffApi.md#my_notifications) | **GET** /staff/me/notifications | 
[**my_payslips**](StaffApi.md#my_payslips) | **GET** /staff/me/payslips | 
[**my_requests**](StaffApi.md#my_requests) | **GET** /staff/me/requests | 
[**my_roster**](StaffApi.md#my_roster) | **GET** /staff/me/roster | My published shifts, open shifts to claim, and my swaps.
[**my_schedule**](StaffApi.md#my_schedule) | **GET** /staff/me/schedule | The employee's OWN roster for a date range, published weeks only (SC-3).
[**my_today**](StaffApi.md#my_today) | **GET** /staff/me/today | 
[**open_cover**](StaffApi.md#open_cover) | **POST** /staff/me/cover | Open a colleague's missed shift as a cover: the same phone and geofence checks as a clock-in; flagged for the manager; paid only once confirmed (CV-1..CV-5, CV-7).
[**override_deduction**](StaffApi.md#override_deduction) | **PATCH** /staff/payroll/deductions/{id}/override | 
[**payroll_history**](StaffApi.md#payroll_history) | **GET** /staff/reports/payroll-history | Overtime and payroll history: one row per pay period in range.
[**ping**](StaffApi.md#ping) | **POST** /staff/me/pings | A location every 15 minutes between clock-in and clock-out (CL-4, CL-17).
[**post_open_shift**](StaffApi.md#post_open_shift) | **POST** /staff/open-shifts | 
[**preference_log**](StaffApi.md#preference_log) | **GET** /staff/employees/{id}/preferences/log | Who changed someone's preferences, and when (SC-12, newest first).
[**preview_period**](StaffApi.md#preview_period) | **GET** /staff/payroll/periods/{id}/preview | 
[**publish**](StaffApi.md#publish) | **POST** /staff/roster/publish | Publish a week: staff see it and are told (SC-3), and the week's open shifts are announced now that people can see them (SC-9).
[**punch_for**](StaffApi.md#punch_for) | **POST** /staff/attendance/punch | Clock someone in, or out if they are in; marked as made by the manager (`manager`) with the reason (CL-13, CL-16). The check-in window, the night shift's business date and the shift's own branch apply exactly as for the app.
[**put_attendance_settings**](StaffApi.md#put_attendance_settings) | **PUT** /staff/attendance/settings | 
[**put_coverage**](StaffApi.md#put_coverage) | **PUT** /staff/roster/coverage | 
[**put_day**](StaffApi.md#put_day) | **PUT** /staff/schedules/days | Set every shift a person works on a date: a split day, one shift with its own times, or a day off (SC-5, SC-11).
[**put_employee**](StaffApi.md#put_employee) | **PUT** /staff/employees/{employee_id} | 
[**put_employee_preferences**](StaffApi.md#put_employee_preferences) | **PUT** /staff/employees/{id}/preferences | A manager overrides someone's preferences (SC-12). Logged, and the person is told.
[**put_override**](StaffApi.md#put_override) | **PUT** /staff/schedules/overrides | Set a date to exactly one shift, or a day off (the older single-shift form of `PUT /staff/schedules/days`).
[**put_preferences**](StaffApi.md#put_preferences) | **PUT** /staff/me/preferences | Preferred times and days I can't work; managers see them (SC-12). Logged.
[**put_times**](StaffApi.md#put_times) | **PUT** /staff/schedules/days/times | One assignment's own from/to (one person, one date, one block), without changing the block. Both null = back to the block's times.
[**read_notifications**](StaffApi.md#read_notifications) | **POST** /staff/me/notifications/read | 
[**record_advance**](StaffApi.md#record_advance) | **POST** /staff/advances/record | A manager hands an advance over directly (AV-2): recorded and approved in ONE call under the same cap and limit as a review, so a refusal never leaves a stray pending advance behind (audit B10).
[**reset_day**](StaffApi.md#reset_day) | **DELETE** /staff/schedules/days | Put a date back on the standing pattern.
[**resolve_flag**](StaffApi.md#resolve_flag) | **PATCH** /staff/flags/{id} | Handle a flag. Nothing is ever charged automatically (CL-6).
[**review_advance**](StaffApi.md#review_advance) | **PATCH** /staff/advances/{id}/review | Decide an advance within the cap: the approver's limit is a % of the employee's salary owed after this one (AV-4, AV-5).
[**revoke_device**](StaffApi.md#revoke_device) | **DELETE** /staff/employees/{employee_id}/device | Sign a person's phone out now (RO-4): the device, every staff token minted for it, and its pushes.
[**roster**](StaffApi.md#roster) | **GET** /staff/roster | The manager's roster for one branch (SC-7, RO-6).
[**set_period_status**](StaffApi.md#set_period_status) | **PATCH** /staff/payroll/periods/{id}/status | Reopen an approved month (before anyone is paid) or close a paid one.
[**set_staff_push_token**](StaffApi.md#set_staff_push_token) | **PUT** /staff/me/push-token | `PUT /staff/me/push-token` — the staff app registers its phone for the employee through the same `push_devices` table as `PUT /push/token` (app = `\"dawam\"`).
[**staff_sign_out**](StaffApi.md#staff_sign_out) | **POST** /staff/me/sign-out | `POST /staff/me/sign-out` — the staff app signs out (APP-6, 06 B3): this phone's device is revoked, so its token can't be refreshed again, and the employee's Dawam pushes stop at once — a signed-out phone never shows the next person's names or amounts. Idempotent.
[**stop_adjustment**](StaffApi.md#stop_adjustment) | **POST** /staff/adjustments/{kind}/{id}/stop | Stop a monthly line from the next period on; past payslips keep it (AD-3).
[**suggestions**](StaffApi.md#suggestions) | **GET** /staff/roster/suggestions | 
[**team_presence**](StaffApi.md#team_presence) | **GET** /staff/team/presence | Who is in, late, absent or on leave right now.
[**till_punch**](StaffApi.md#till_punch) | **POST** /staff/attendance/till-punch | A dead or forgotten phone in a Madar org: the person clocks in or out on the branch till with their till PIN (CL-13). Marked `till` (CL-16). The till is at the branch, so there is no geofence to check — which is why it is accepted ONLY from a real till (audit 03 P0): a POS session (never the Dawam app's) on the branch's registered POS device, proven by its credential when it has one, with a till session open on that device at that branch. Online only: a PIN is never queued. Wrong PINs slow down like the till's own sign-in, and the branch's managers are told.
[**unwaive_deduction**](StaffApi.md#unwaive_deduction) | **PATCH** /staff/payroll/deductions/{id}/unwaive | Undo a waiver, with a reason (AT-7): the line counts again at the amount it had. Only while the month is open.
[**update_department**](StaffApi.md#update_department) | **PATCH** /staff/departments/{id} | 
[**update_work_shift**](StaffApi.md#update_work_shift) | **PATCH** /staff/work-shifts/{id} | 
[**waive_deduction**](StaffApi.md#waive_deduction) | **PATCH** /staff/payroll/deductions/{id}/waive | 



## accept_staff_privacy

> models::PrivacyAccepted accept_staff_privacy()
The employee accepted the location notice on this phone (AT-5). Kept on the device row: a new phone asks again.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::PrivacyAccepted**](PrivacyAccepted.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## advances

> models::AdvancesReport advances(from, to, branch_id)
Advances given in range, and what is still owed.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::AdvancesReport**](AdvancesReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## answer_swap

> models::Swap answer_swap(id, decide_roster)
The colleague agrees or declines.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**decide_roster** | [**DecideRoster**](DecideRoster.md) |  | [required] |

### Return type

[**models::Swap**](Swap.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## ask_swap

> models::Swap ask_swap(ask_swap)
Ask a colleague to swap: they agree first, then the manager (SC-8). Both shifts must be on the published roster, ahead, at a branch both work at, and must fit where they land.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ask_swap** | [**AskSwap**](AskSwap.md) |  | [required] |

### Return type

[**models::Swap**](Swap.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## attendance_summary

> Vec<models::AttendanceSummary> attendance_summary(from, to, branch_id, employee_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**employee_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::AttendanceSummary>**](AttendanceSummary.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_people

> Vec<models::BranchPerson> branch_people(branch_id)
Active employees at a branch, names only: what a till shows to tag a pay-out as someone's expense advance (AV-8). Anyone who works the branch may read it; nothing about pay is in it.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::BranchPerson>**](BranchPerson.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## cancel_open_shift

> cancel_open_shift(id)
Take an open shift back (open or claimed, never filled). A claimer hears.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## cancel_swap

> models::Swap cancel_swap(id)
The one who asked takes it back before the manager decides.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::Swap**](Swap.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## check_in

> models::AttendanceRecord check_in(check_in_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**check_in_request** | [**CheckInRequest**](CheckInRequest.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## check_out

> models::AttendanceRecord check_out(check_out_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**check_out_request** | [**CheckOutRequest**](CheckOutRequest.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## claim_open_shift

> models::OpenShift claim_open_shift(id)
Claim an open shift; the manager approves the claim (SC-9). Only a published week's, and only one that fits beside the person's own shifts.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::OpenShift**](OpenShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## correct_record

> models::AttendanceRecord correct_record(id, correct_record_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Attendance record ID | [required] |
**correct_record_request** | [**CorrectRecordRequest**](CorrectRecordRequest.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_adjustment

> models::Adjustment create_adjustment(new_adjustment)
Add a bonus or deduction. Over the caller's limit it is created pending and waits for the owner (AD-5). Bonuses and deductions have separate limits.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**new_adjustment** | [**NewAdjustment**](NewAdjustment.md) |  | [required] |

### Return type

[**models::Adjustment**](Adjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_advance_admin

> models::SalaryAdvance create_advance_admin(create_advance_request)
Record an ask on someone's behalf: it still waits for a decision (`PATCH /staff/advances/{id}/review`). To hand one over at once, use `POST /staff/advances/record`.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_advance_request** | [**CreateAdvanceRequest**](CreateAdvanceRequest.md) |  | [required] |

### Return type

[**models::SalaryAdvance**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_assignment

> models::ScheduleAssignment create_assignment(create_assignment_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_assignment_request** | [**CreateAssignmentRequest**](CreateAssignmentRequest.md) |  | [required] |

### Return type

[**models::ScheduleAssignment**](ScheduleAssignment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_department

> models::Department create_department(upsert_department_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upsert_department_request** | [**UpsertDepartmentRequest**](UpsertDepartmentRequest.md) |  | [required] |

### Return type

[**models::Department**](Department.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_document

> models::StaffDocument create_document(employee_id, create_document_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** | The employee's id | [required] |
**create_document_request** | [**CreateDocumentRequest**](CreateDocumentRequest.md) |  | [required] |

### Return type

[**models::StaffDocument**](StaffDocument.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_employee

> models::Employee create_employee(create_employee_request)
Add an employee: linked to an existing user, or without one (with or without the staff app). Used by the Employees page, the set-up wizard and the spreadsheet import (DSH-7). Never creates a login.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_employee_request** | [**CreateEmployeeRequest**](CreateEmployeeRequest.md) |  | [required] |

### Return type

[**models::Employee**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_manual_record

> models::AttendanceRecord create_manual_record(manual_record_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**manual_record_request** | [**ManualRecordRequest**](ManualRecordRequest.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_my_advance

> models::SalaryAdvance create_my_advance(create_advance_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_advance_request** | [**CreateAdvanceRequest**](CreateAdvanceRequest.md) |  | [required] |

### Return type

[**models::SalaryAdvance**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_my_request

> models::StaffRequest create_my_request(create_staff_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_staff_request** | [**CreateStaffRequest**](CreateStaffRequest.md) |  | [required] |

### Return type

[**models::StaffRequest**](StaffRequest.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_period

> models::PayrollPeriod create_period(create_period_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_period_request** | [**CreatePeriodRequest**](CreatePeriodRequest.md) |  | [required] |

### Return type

[**models::PayrollPeriod**](PayrollPeriod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_request_admin

> models::StaffRequest create_request_admin(create_staff_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_staff_request** | [**CreateStaffRequest**](CreateStaffRequest.md) |  | [required] |

### Return type

[**models::StaffRequest**](StaffRequest.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_work_shift

> models::WorkShift create_work_shift(upsert_work_shift_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upsert_work_shift_request** | [**UpsertWorkShiftRequest**](UpsertWorkShiftRequest.md) |  | [required] |

### Return type

[**models::WorkShift**](WorkShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## current

> models::CurrentPayroll current()
The running period with everyone's pay (PAY-1..PAY-5).

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::CurrentPayroll**](CurrentPayroll.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_adjustment

> models::Adjustment decide_adjustment(kind, id, decide_pay)
The owner (or anyone whose limit covers it) decides a pending line. A percent line is judged at its value in piastres (audit B5).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**kind** | **String** |  | [required] |
**id** | **uuid::Uuid** |  | [required] |
**decide_pay** | [**DecidePay**](DecidePay.md) |  | [required] |

### Return type

[**models::Adjustment**](Adjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_claim

> decide_claim(id, decide_roster)
Approve a claim: the shift becomes theirs for that date, beside the rest of their day. Rejecting reopens it. One decision only.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**decide_roster** | [**DecideRoster**](DecideRoster.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_cover

> models::AttendanceRecord decide_cover(id, decide)
Confirm or reject a cover. Rejecting pays nothing (CV-5); the confirmer is neither person involved.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**decide** | [**Decide**](Decide.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_holiday

> models::HolidayView decide_holiday(date, holiday_decision)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**date** | **chrono::NaiveDate** |  | [required] |
**holiday_decision** | [**HolidayDecision**](HolidayDecision.md) |  | [required] |

### Return type

[**models::HolidayView**](HolidayView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_overtime

> models::AttendanceRecord decide_overtime(id, decide)
Approve or reject a shift's overtime, within the approver's money limit.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**decide** | [**Decide**](Decide.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_request

> models::StaffRequest decide_request(id, request_decision)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Request ID | [required] |
**request_decision** | [**RequestDecision**](RequestDecision.md) |  | [required] |

### Return type

[**models::StaffRequest**](StaffRequest.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_suggestion

> decide_suggestion(decide_suggestion)
Accept (changes that date only) or reject; either way it is remembered. Only a suggestion the engine actually made for that branch-week is taken (a crafted id is refused), and accepting touches only the block it names.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**decide_suggestion** | [**DecideSuggestion**](DecideSuggestion.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decide_swap

> decide_swap(id, decide_roster)
The manager approves: both rosters update for those dates (SC-8), in one transaction, once, and only if both shifts are still where they were.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**decide_roster** | [**DecideRoster**](DecideRoster.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_assignment

> delete_assignment(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Assignment ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_bonus

> delete_bonus(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bonus ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_branch_rules

> delete_branch_rules(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch whose overrides go | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_deduction

> delete_deduction(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Deduction ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_department

> delete_department(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Department ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_document

> delete_document(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Document ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_employee

> delete_employee(employee_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** | The employee's id | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_override

> delete_override(id)
Remove one row of a date's set: one block of a split day, or the date's last change (back to the pattern).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Override ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_period

> delete_period(id)
Delete a DRAFT period. An approved month is reopened first (which is refused once anyone is paid), so a paid payslip can never be wiped (B3).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_record

> delete_record(id, reason)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Attendance record ID | [required] |
**reason** | Option<**String**> | Why the day goes (kept with the tombstone the absence sweep honours). |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_work_shift

> delete_work_shift(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Work shift ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## discipline_report

> models::DisciplineReport discipline_report(from, to, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> | Omit for every branch in the org. |  |

### Return type

[**models::DisciplineReport**](DisciplineReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## export_period_csv

> export_period_csv(id, method)
The generated period as a CSV: the bank file, the wallet list, or the whole run.

Deliberately serves the PAYSLIPS, not a fresh computation: the file handed to a bank must be exactly what was approved, even if a deduction has been edited since. A period that has not been generated has nothing to export.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |
**method** | Option<**String**> | `bank` (a transfer file: name, account, amount) · `wallet` (numbers and amounts) · `cash`; omitted = everyone, every figure (PAY-8). |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: text/csv, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## fairness

> models::FairnessView fairness(month, branch_id)
Owner only, monthly: who works the nights, by gender, against who said they want them — for the business and branch by branch.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**month** | **chrono::NaiveDate** | Any day of the month. | [required] |
**branch_id** | Option<**uuid::Uuid**> | One branch; omit for every branch and the business as a whole. |  |

### Return type

[**models::FairnessView**](FairnessView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## fairness_audits

> Vec<models::FairnessAudit> fairness_audits()
The kept monthly audits, newest first (owner).

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::FairnessAudit>**](FairnessAudit.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## generate_period

> Vec<models::Payslip> generate_period(id)
Approve a DRAFT month: freeze every payslip and collect the advance installments in the ledger. An approved month is not regenerated — it is reopened (before anyone is paid) and approved again.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |

### Return type

[**Vec<models::Payslip>**](Payslip.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_attendance_settings

> models::AttendanceSettings get_attendance_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::AttendanceSettings**](AttendanceSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_coverage

> models::CoverageView get_coverage(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::CoverageView**](CoverageView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_employee

> models::Employee get_employee(employee_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** | The employee's id | [required] |

### Return type

[**models::Employee**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_scheduled_day

> Vec<models::ResolvedShift> get_scheduled_day(employee_id, date, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | [required] |
**date** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> | Which branch's timezone the day is measured in. Defaults to the employee's only branch assignment when they have exactly one. |  |

### Return type

[**Vec<models::ResolvedShift>**](ResolvedShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## labour_vs_sales

> Vec<models::LabourDay> labour_vs_sales(from, to, branch_id)
Labour cost vs sales, per branch and day. Only when POS is on (DSH-4).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::LabourDay>**](LabourDay.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## linkable_users

> Vec<models::LinkableUser> linkable_users()
The org's users who are not employees yet: the \"make this user an employee\" picker.

### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::LinkableUser>**](LinkableUser.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_adjustments

> Vec<models::Adjustment> list_adjustments(employee_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::Adjustment>**](Adjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_advances

> Vec<models::SalaryAdvance> list_advances(employee_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**from** | Option<**chrono::NaiveDate**> |  |  |
**to** | Option<**chrono::NaiveDate**> |  |  |

### Return type

[**Vec<models::SalaryAdvance>**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_assignments

> Vec<models::ScheduleAssignment> list_assignments(employee_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> | Omit for the WHOLE org's roster — what a schedule grid needs, and the only way to draw one without a request per employee. |  |

### Return type

[**Vec<models::ScheduleAssignment>**](ScheduleAssignment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_attendance

> Vec<models::AttendanceRecord> list_attendance(from, to, branch_id, employee_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**employee_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::AttendanceRecord>**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_attendance_flags

> Vec<models::AttendanceFlag> list_attendance_flags(branch_id, all)
The flags a manager should look at, for their branches (RO-6).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |
**all** | Option<**bool**> | Include handled flags. |  |

### Return type

[**Vec<models::AttendanceFlag>**](AttendanceFlag.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_audit

> Vec<models::AuditRow> list_audit(employee_id, period_id)
The money audit log: every delete, stop, waive, override, reopen and payment, with who and why (AD-9, AT-10).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**period_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::AuditRow>**](AuditRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bonuses

> Vec<models::PayrollAdjustment> list_bonuses(employee_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**from** | Option<**chrono::NaiveDate**> |  |  |
**to** | Option<**chrono::NaiveDate**> |  |  |

### Return type

[**Vec<models::PayrollAdjustment>**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branch_rules

> Vec<models::BranchRules> list_branch_rules()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::BranchRules>**](BranchRules.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_deductions

> Vec<models::PayrollAdjustment> list_deductions(employee_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**from** | Option<**chrono::NaiveDate**> |  |  |
**to** | Option<**chrono::NaiveDate**> |  |  |

### Return type

[**Vec<models::PayrollAdjustment>**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_departments

> Vec<models::Department> list_departments()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::Department>**](Department.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_documents

> Vec<models::StaffDocument> list_documents(employee_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** | The employee's id | [required] |

### Return type

[**Vec<models::StaffDocument>**](StaffDocument.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_employees

> Vec<models::Employee> list_employees(department_id, employment_status, search, branch_id, kind)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**department_id** | Option<**uuid::Uuid**> |  |  |
**employment_status** | Option<**String**> | `active` | `suspended` | `terminated`. Omitted = every status. |  |
**search** | Option<**String**> | Case-insensitive substring over name, employee code, and job title. |  |
**branch_id** | Option<**uuid::Uuid**> | Only the people of this branch. |  |
**kind** | Option<**String**> | `linked` · `app` · `manual`. |  |

### Return type

[**Vec<models::Employee>**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_expense_advances

> Vec<models::ExpenseAdvance> list_expense_advances(employee_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::ExpenseAdvance>**](ExpenseAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_open_shifts

> Vec<models::OpenShift> list_open_shifts(from, to)
Open shifts and their claims at the branches I run (SC-9) — the dashboard's approvals queue and schedule.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |

### Return type

[**Vec<models::OpenShift>**](OpenShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_payslips

> Vec<models::Payslip> list_payslips(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |

### Return type

[**Vec<models::Payslip>**](Payslip.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_periods

> Vec<models::PayrollPeriod> list_periods()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::PayrollPeriod>**](PayrollPeriod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_requests

> Vec<models::StaffRequest> list_requests(employee_id, kind, status, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**kind** | Option<**String**> |  |  |
**status** | Option<**String**> |  |  |
**from** | Option<**chrono::NaiveDate**> |  |  |
**to** | Option<**chrono::NaiveDate**> |  |  |

### Return type

[**Vec<models::StaffRequest>**](StaffRequest.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_swaps

> Vec<models::Swap> list_swaps(status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::Swap>**](Swap.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_work_shifts

> Vec<models::WorkShift> list_work_shifts()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::WorkShift>**](WorkShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## log_expense_advance

> models::ExpenseAdvance log_expense_advance(new_expense_advance)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**new_expense_advance** | [**NewExpenseAdvance**](NewExpenseAdvance.md) |  | [required] |

### Return type

[**models::ExpenseAdvance**](ExpenseAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## mark_paid

> models::Payslip mark_paid(id, employee_id, mark_paid)
Mark one payslip paid; the period is paid once everyone is (PAY-7).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**employee_id** | **uuid::Uuid** |  | [required] |
**mark_paid** | [**MarkPaid**](MarkPaid.md) |  | [required] |

### Return type

[**models::Payslip**](Payslip.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## move_shift

> models::MoveView move_shift(move_shift_request)
Give one person's shift on a date to someone else; both keep the rest of their day.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**move_shift_request** | [**MoveShiftRequest**](MoveShiftRequest.md) |  | [required] |

### Return type

[**models::MoveView**](MoveView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_adjustments

> Vec<models::Adjustment> my_adjustments()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::Adjustment>**](Adjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_advances

> Vec<models::SalaryAdvance> my_advances()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::SalaryAdvance>**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_attendance

> Vec<models::AttendanceRecord> my_attendance(from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |

### Return type

[**Vec<models::AttendanceRecord>**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_context

> models::StaffContext my_context()


### Parameters

This endpoint does not need any parameter.

### Return type

[**models::StaffContext**](StaffContext.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_coverable

> Vec<models::CoverableShift> my_coverable()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::CoverableShift>**](CoverableShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_estimate

> models::PayEstimate my_estimate()
What I've earned so far this period.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::PayEstimate**](PayEstimate.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_expense_advances

> Vec<models::ExpenseAdvance> my_expense_advances()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::ExpenseAdvance>**](ExpenseAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_leave_balances

> Vec<models::LeaveBalance> my_leave_balances(employee_id, year)
Deprecated (RQ-3): Dawam has no leave balances. This shows what older data holds and is never written any more.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | Option<**uuid::Uuid**> |  |  |
**year** | Option<**i32**> | Defaults to the current calendar year. |  |

### Return type

[**Vec<models::LeaveBalance>**](LeaveBalance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_notifications

> Vec<models::StaffNotification> my_notifications()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::StaffNotification>**](StaffNotification.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_payslips

> Vec<models::Payslip> my_payslips()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::Payslip>**](Payslip.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_requests

> Vec<models::StaffRequest> my_requests()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::StaffRequest>**](StaffRequest.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_roster

> models::MyRosterView my_roster(from, to)
My published shifts, open shifts to claim, and my swaps.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |

### Return type

[**models::MyRosterView**](MyRosterView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_schedule

> Vec<models::ScheduledDay> my_schedule(from, to)
The employee's OWN roster for a date range, published weeks only (SC-3).

Own-row scoped like the rest of `/staff/me/_*`: it needs no permission grant, because seeing when you are expected at work is not an admin capability.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |

### Return type

[**Vec<models::ScheduledDay>**](ScheduledDay.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## my_today

> models::MyAttendanceToday my_today()


### Parameters

This endpoint does not need any parameter.

### Return type

[**models::MyAttendanceToday**](MyAttendanceToday.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## open_cover

> models::AttendanceRecord open_cover(open_cover)
Open a colleague's missed shift as a cover: the same phone and geofence checks as a clock-in; flagged for the manager; paid only once confirmed (CV-1..CV-5, CV-7).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**open_cover** | [**OpenCover**](OpenCover.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## override_deduction

> models::PayrollAdjustment override_deduction(id, override_deduction_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Deduction ID | [required] |
**override_deduction_request** | [**OverrideDeductionRequest**](OverrideDeductionRequest.md) |  | [required] |

### Return type

[**models::PayrollAdjustment**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## payroll_history

> Vec<models::PayrollHistoryRow> payroll_history(from, to, branch_id)
Overtime and payroll history: one row per pay period in range.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::PayrollHistoryRow>**](PayrollHistoryRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## ping

> models::PingResult ping(ping_request)
A location every 15 minutes between clock-in and clock-out (CL-4, CL-17).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ping_request** | [**PingRequest**](PingRequest.md) |  | [required] |

### Return type

[**models::PingResult**](PingResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## post_open_shift

> models::OpenShift post_open_shift(post_open_shift)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**post_open_shift** | [**PostOpenShift**](PostOpenShift.md) |  | [required] |

### Return type

[**models::OpenShift**](OpenShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## preference_log

> Vec<models::PreferenceChange> preference_log(id)
Who changed someone's preferences, and when (SC-12, newest first).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::PreferenceChange>**](PreferenceChange.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## preview_period

> Vec<models::ComputedPayslip> preview_period(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |

### Return type

[**Vec<models::ComputedPayslip>**](ComputedPayslip.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## publish

> publish(publish_week)
Publish a week: staff see it and are told (SC-3), and the week's open shifts are announced now that people can see them (SC-9).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**publish_week** | [**PublishWeek**](PublishWeek.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## punch_for

> models::AttendanceRecord punch_for(punch_for)
Clock someone in, or out if they are in; marked as made by the manager (`manager`) with the reason (CL-13, CL-16). The check-in window, the night shift's business date and the shift's own branch apply exactly as for the app.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**punch_for** | [**PunchFor**](PunchFor.md) |  | [required] |

### Return type

[**models::AttendanceRecord**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_attendance_settings

> models::AttendanceSettings put_attendance_settings(put_attendance_settings_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_attendance_settings_request** | [**PutAttendanceSettingsRequest**](PutAttendanceSettingsRequest.md) |  | [required] |

### Return type

[**models::AttendanceSettings**](AttendanceSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_coverage

> put_coverage(put_coverage)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_coverage** | [**PutCoverage**](PutCoverage.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_day

> models::DayView put_day(put_day_request)
Set every shift a person works on a date: a split day, one shift with its own times, or a day off (SC-5, SC-11).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_day_request** | [**PutDayRequest**](PutDayRequest.md) |  | [required] |

### Return type

[**models::DayView**](DayView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_employee

> models::Employee put_employee(employee_id, put_employee_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** | The employee's id | [required] |
**put_employee_request** | [**PutEmployeeRequest**](PutEmployeeRequest.md) |  | [required] |

### Return type

[**models::Employee**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_employee_preferences

> put_employee_preferences(id, preferences)
A manager overrides someone's preferences (SC-12). Logged, and the person is told.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**preferences** | [**Preferences**](Preferences.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_override

> models::ScheduleOverride put_override(put_override_request)
Set a date to exactly one shift, or a day off (the older single-shift form of `PUT /staff/schedules/days`).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_override_request** | [**PutOverrideRequest**](PutOverrideRequest.md) |  | [required] |

### Return type

[**models::ScheduleOverride**](ScheduleOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_preferences

> put_preferences(preferences)
Preferred times and days I can't work; managers see them (SC-12). Logged.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**preferences** | [**Preferences**](Preferences.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_times

> models::DayView put_times(put_times_request)
One assignment's own from/to (one person, one date, one block), without changing the block. Both null = back to the block's times.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_times_request** | [**PutTimesRequest**](PutTimesRequest.md) |  | [required] |

### Return type

[**models::DayView**](DayView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## read_notifications

> read_notifications(read_notifications)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**read_notifications** | [**ReadNotifications**](ReadNotifications.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## record_advance

> models::SalaryAdvance record_advance(record_advance)
A manager hands an advance over directly (AV-2): recorded and approved in ONE call under the same cap and limit as a review, so a refusal never leaves a stray pending advance behind (audit B10).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**record_advance** | [**RecordAdvance**](RecordAdvance.md) |  | [required] |

### Return type

[**models::SalaryAdvance**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## reset_day

> models::DayView reset_day(employee_id, on_date)
Put a date back on the standing pattern.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | [required] |
**on_date** | **chrono::NaiveDate** |  | [required] |

### Return type

[**models::DayView**](DayView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## resolve_flag

> models::AttendanceFlag resolve_flag(id, resolve_flag)
Handle a flag. Nothing is ever charged automatically (CL-6).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**resolve_flag** | [**ResolveFlag**](ResolveFlag.md) |  | [required] |

### Return type

[**models::AttendanceFlag**](AttendanceFlag.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## review_advance

> models::SalaryAdvance review_advance(id, review_advance)
Decide an advance within the cap: the approver's limit is a % of the employee's salary owed after this one (AV-4, AV-5).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**review_advance** | [**ReviewAdvance**](ReviewAdvance.md) |  | [required] |

### Return type

[**models::SalaryAdvance**](SalaryAdvance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_device

> revoke_device(employee_id)
Sign a person's phone out now (RO-4): the device, every staff token minted for it, and its pushes.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## roster

> models::RosterView roster(branch_id, from, to)
The manager's roster for one branch (SC-7, RO-6).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |

### Return type

[**models::RosterView**](RosterView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_period_status

> models::PayrollPeriod set_period_status(id, period_status_request)
Reopen an approved month (before anyone is paid) or close a paid one.

Reopening DROPS the frozen payslips: their advance collections go with them (the ledger trigger refunds), so the live preview reads exactly what re-approving will collect (PAY-2, PAY-6, audit B7).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Period ID | [required] |
**period_status_request** | [**PeriodStatusRequest**](PeriodStatusRequest.md) |  | [required] |

### Return type

[**models::PayrollPeriod**](PayrollPeriod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_staff_push_token

> set_staff_push_token(push_token)
`PUT /staff/me/push-token` — the staff app registers its phone for the employee through the same `push_devices` table as `PUT /push/token` (app = `\"dawam\"`).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**push_token** | [**PushToken**](PushToken.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## staff_sign_out

> staff_sign_out()
`POST /staff/me/sign-out` — the staff app signs out (APP-6, 06 B3): this phone's device is revoked, so its token can't be refreshed again, and the employee's Dawam pushes stop at once — a signed-out phone never shows the next person's names or amounts. Idempotent.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## stop_adjustment

> models::Adjustment stop_adjustment(kind, id, stop_adjustment)
Stop a monthly line from the next period on; past payslips keep it (AD-3).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**kind** | **String** |  | [required] |
**id** | **uuid::Uuid** |  | [required] |
**stop_adjustment** | [**StopAdjustment**](StopAdjustment.md) |  | [required] |

### Return type

[**models::Adjustment**](Adjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## suggestions

> Vec<models::Suggestion> suggestions(branch_id, week_start)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**week_start** | **chrono::NaiveDate** |  | [required] |

### Return type

[**Vec<models::Suggestion>**](Suggestion.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## team_presence

> models::TeamPresence team_presence(branch_id)
Who is in, late, absent or on leave right now.

Computed from TODAY'S attendance rows joined against the roster, so someone rostered with no row yet is `absent` only once their shift has actually started — before that they are simply `off`, not a red number on a manager's dashboard at 6am.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for every branch in the org. |  |

### Return type

[**models::TeamPresence**](TeamPresence.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## till_punch

> models::TillPunchResult till_punch(x_madar_device, till_punch, x_madar_device_token)
A dead or forgotten phone in a Madar org: the person clocks in or out on the branch till with their till PIN (CL-13). Marked `till` (CL-16). The till is at the branch, so there is no geofence to check — which is why it is accepted ONLY from a real till (audit 03 P0): a POS session (never the Dawam app's) on the branch's registered POS device, proven by its credential when it has one, with a till session open on that device at that branch. Online only: a PIN is never queued. Wrong PINs slow down like the till's own sign-in, and the branch's managers are told.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**x_madar_device** | **String** | The till's device id | [required] |
**till_punch** | [**TillPunch**](TillPunch.md) |  | [required] |
**x_madar_device_token** | Option<**String**> | The device credential, when it has one |  |

### Return type

[**models::TillPunchResult**](TillPunchResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## unwaive_deduction

> models::PayrollAdjustment unwaive_deduction(id, waive_deduction_request)
Undo a waiver, with a reason (AT-7): the line counts again at the amount it had. Only while the month is open.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Deduction ID | [required] |
**waive_deduction_request** | [**WaiveDeductionRequest**](WaiveDeductionRequest.md) |  | [required] |

### Return type

[**models::PayrollAdjustment**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_department

> models::Department update_department(id, upsert_department_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Department ID | [required] |
**upsert_department_request** | [**UpsertDepartmentRequest**](UpsertDepartmentRequest.md) |  | [required] |

### Return type

[**models::Department**](Department.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_work_shift

> models::WorkShift update_work_shift(id, upsert_work_shift_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Work shift ID | [required] |
**upsert_work_shift_request** | [**UpsertWorkShiftRequest**](UpsertWorkShiftRequest.md) |  | [required] |

### Return type

[**models::WorkShift**](WorkShift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## waive_deduction

> models::PayrollAdjustment waive_deduction(id, waive_deduction_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Deduction ID | [required] |
**waive_deduction_request** | [**WaiveDeductionRequest**](WaiveDeductionRequest.md) |  | [required] |

### Return type

[**models::PayrollAdjustment**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

