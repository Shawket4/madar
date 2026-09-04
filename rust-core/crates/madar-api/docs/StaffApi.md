# \StaffApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**attendance_summary**](StaffApi.md#attendance_summary) | **GET** /staff/attendance/summary | 
[**check_in**](StaffApi.md#check_in) | **POST** /staff/me/check-in | 
[**check_out**](StaffApi.md#check_out) | **POST** /staff/me/check-out | 
[**correct_record**](StaffApi.md#correct_record) | **PATCH** /staff/attendance/{id} | 
[**create_advance_admin**](StaffApi.md#create_advance_admin) | **POST** /staff/payroll/advances | 
[**create_assignment**](StaffApi.md#create_assignment) | **POST** /staff/schedules | 
[**create_bonus**](StaffApi.md#create_bonus) | **POST** /staff/payroll/bonuses | 
[**create_deduction**](StaffApi.md#create_deduction) | **POST** /staff/payroll/deductions | 
[**create_department**](StaffApi.md#create_department) | **POST** /staff/departments | 
[**create_document**](StaffApi.md#create_document) | **POST** /staff/employees/{user_id}/documents | 
[**create_leave_type**](StaffApi.md#create_leave_type) | **POST** /staff/leave/types | 
[**create_manual_record**](StaffApi.md#create_manual_record) | **POST** /staff/attendance | 
[**create_my_advance**](StaffApi.md#create_my_advance) | **POST** /staff/me/advances | 
[**create_my_request**](StaffApi.md#create_my_request) | **POST** /staff/me/requests | 
[**create_period**](StaffApi.md#create_period) | **POST** /staff/payroll/periods | 
[**create_request_admin**](StaffApi.md#create_request_admin) | **POST** /staff/requests | 
[**create_work_shift**](StaffApi.md#create_work_shift) | **POST** /staff/work-shifts | 
[**decide_advance**](StaffApi.md#decide_advance) | **PATCH** /staff/payroll/advances/{id}/decision | 
[**decide_request**](StaffApi.md#decide_request) | **PATCH** /staff/requests/{id}/decision | 
[**delete_assignment**](StaffApi.md#delete_assignment) | **DELETE** /staff/schedules/{id} | 
[**delete_bonus**](StaffApi.md#delete_bonus) | **DELETE** /staff/payroll/bonuses/{id} | 
[**delete_deduction**](StaffApi.md#delete_deduction) | **DELETE** /staff/payroll/deductions/{id} | 
[**delete_department**](StaffApi.md#delete_department) | **DELETE** /staff/departments/{id} | 
[**delete_document**](StaffApi.md#delete_document) | **DELETE** /staff/documents/{id} | 
[**delete_employee**](StaffApi.md#delete_employee) | **DELETE** /staff/employees/{user_id} | 
[**delete_leave_type**](StaffApi.md#delete_leave_type) | **DELETE** /staff/leave/types/{id} | 
[**delete_override**](StaffApi.md#delete_override) | **DELETE** /staff/schedules/overrides/{id} | 
[**delete_period**](StaffApi.md#delete_period) | **DELETE** /staff/payroll/periods/{id} | 
[**delete_record**](StaffApi.md#delete_record) | **DELETE** /staff/attendance/{id} | 
[**delete_work_shift**](StaffApi.md#delete_work_shift) | **DELETE** /staff/work-shifts/{id} | 
[**export_period_csv**](StaffApi.md#export_period_csv) | **GET** /staff/payroll/periods/{id}/export.csv | The generated period as a bank-ready CSV.
[**generate_period**](StaffApi.md#generate_period) | **POST** /staff/payroll/periods/{id}/generate | 
[**get_attendance_settings**](StaffApi.md#get_attendance_settings) | **GET** /staff/attendance/settings | 
[**get_employee**](StaffApi.md#get_employee) | **GET** /staff/employees/{user_id} | 
[**get_scheduled_day**](StaffApi.md#get_scheduled_day) | **GET** /staff/schedules/day | 
[**list_advances**](StaffApi.md#list_advances) | **GET** /staff/payroll/advances | 
[**list_assignments**](StaffApi.md#list_assignments) | **GET** /staff/schedules | 
[**list_attendance**](StaffApi.md#list_attendance) | **GET** /staff/attendance | 
[**list_balances**](StaffApi.md#list_balances) | **GET** /staff/leave/balances | 
[**list_bonuses**](StaffApi.md#list_bonuses) | **GET** /staff/payroll/bonuses | 
[**list_deductions**](StaffApi.md#list_deductions) | **GET** /staff/payroll/deductions | 
[**list_departments**](StaffApi.md#list_departments) | **GET** /staff/departments | 
[**list_documents**](StaffApi.md#list_documents) | **GET** /staff/employees/{user_id}/documents | 
[**list_employees**](StaffApi.md#list_employees) | **GET** /staff/employees | 
[**list_leave_types**](StaffApi.md#list_leave_types) | **GET** /staff/leave/types | 
[**list_payslips**](StaffApi.md#list_payslips) | **GET** /staff/payroll/periods/{id}/payslips | 
[**list_periods**](StaffApi.md#list_periods) | **GET** /staff/payroll/periods | 
[**list_requests**](StaffApi.md#list_requests) | **GET** /staff/requests | 
[**list_work_shifts**](StaffApi.md#list_work_shifts) | **GET** /staff/work-shifts | 
[**my_advances**](StaffApi.md#my_advances) | **GET** /staff/me/advances | 
[**my_attendance**](StaffApi.md#my_attendance) | **GET** /staff/me/attendance | 
[**my_leave_balances**](StaffApi.md#my_leave_balances) | **GET** /staff/me/leave-balances | 
[**my_payslips**](StaffApi.md#my_payslips) | **GET** /staff/me/payslips | 
[**my_requests**](StaffApi.md#my_requests) | **GET** /staff/me/requests | 
[**my_schedule**](StaffApi.md#my_schedule) | **GET** /staff/me/schedule | The employee's OWN roster for a date range — what the app's Shifts tab shows.
[**my_today**](StaffApi.md#my_today) | **GET** /staff/me/today | 
[**override_deduction**](StaffApi.md#override_deduction) | **PATCH** /staff/payroll/deductions/{id}/override | 
[**preview_period**](StaffApi.md#preview_period) | **GET** /staff/payroll/periods/{id}/preview | 
[**put_attendance_settings**](StaffApi.md#put_attendance_settings) | **PUT** /staff/attendance/settings | 
[**put_balance**](StaffApi.md#put_balance) | **PUT** /staff/leave/balances | 
[**put_employee**](StaffApi.md#put_employee) | **PUT** /staff/employees/{user_id} | 
[**put_override**](StaffApi.md#put_override) | **PUT** /staff/schedules/overrides | 
[**set_period_status**](StaffApi.md#set_period_status) | **PATCH** /staff/payroll/periods/{id}/status | 
[**team_presence**](StaffApi.md#team_presence) | **GET** /staff/team/presence | Who is in, late, absent or on leave right now.
[**update_department**](StaffApi.md#update_department) | **PATCH** /staff/departments/{id} | 
[**update_leave_type**](StaffApi.md#update_leave_type) | **PATCH** /staff/leave/types/{id} | 
[**update_work_shift**](StaffApi.md#update_work_shift) | **PATCH** /staff/work-shifts/{id} | 
[**waive_deduction**](StaffApi.md#waive_deduction) | **PATCH** /staff/payroll/deductions/{id}/waive | 



## attendance_summary

> Vec<models::AttendanceSummary> attendance_summary(from, to, branch_id, user_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**user_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::AttendanceSummary>**](AttendanceSummary.md)

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


## create_advance_admin

> models::SalaryAdvance create_advance_admin(create_advance_request)


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


## create_bonus

> models::PayrollAdjustment create_bonus(create_adjustment_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_adjustment_request** | [**CreateAdjustmentRequest**](CreateAdjustmentRequest.md) |  | [required] |

### Return type

[**models::PayrollAdjustment**](PayrollAdjustment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_deduction

> models::PayrollAdjustment create_deduction(create_adjustment_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_adjustment_request** | [**CreateAdjustmentRequest**](CreateAdjustmentRequest.md) |  | [required] |

### Return type

[**models::PayrollAdjustment**](PayrollAdjustment.md)

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

> models::StaffDocument create_document(user_id, create_document_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | The employee's user ID | [required] |
**create_document_request** | [**CreateDocumentRequest**](CreateDocumentRequest.md) |  | [required] |

### Return type

[**models::StaffDocument**](StaffDocument.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_leave_type

> models::LeaveType create_leave_type(upsert_leave_type_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upsert_leave_type_request** | [**UpsertLeaveTypeRequest**](UpsertLeaveTypeRequest.md) |  | [required] |

### Return type

[**models::LeaveType**](LeaveType.md)

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


## decide_advance

> models::SalaryAdvance decide_advance(id, advance_decision)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Advance ID | [required] |
**advance_decision** | [**AdvanceDecision**](AdvanceDecision.md) |  | [required] |

### Return type

[**models::SalaryAdvance**](SalaryAdvance.md)

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

> delete_employee(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | The employee's user ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_leave_type

> delete_leave_type(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Leave type ID | [required] |

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

> delete_record(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Attendance record ID | [required] |

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


## export_period_csv

> export_period_csv(id)
The generated period as a bank-ready CSV.

Deliberately serves the PAYSLIPS, not a fresh computation: the file handed to a bank must be exactly what was approved, even if a deduction has been edited since. A period that has not been generated has nothing to export.

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
- **Accept**: text/csv, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## generate_period

> Vec<models::Payslip> generate_period(id)


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


## get_employee

> models::Employee get_employee(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | The employee's user ID | [required] |

### Return type

[**models::Employee**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_scheduled_day

> Vec<models::ResolvedShift> get_scheduled_day(user_id, date, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** |  | [required] |
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


## list_advances

> Vec<models::SalaryAdvance> list_advances(user_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
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

> Vec<models::ScheduleAssignment> list_assignments(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> | Omit for the WHOLE org's roster — what a schedule grid needs, and the only way to draw one without a request per employee. |  |

### Return type

[**Vec<models::ScheduleAssignment>**](ScheduleAssignment.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_attendance

> Vec<models::AttendanceRecord> list_attendance(from, to, branch_id, user_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** |  | [required] |
**to** | **chrono::NaiveDate** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**user_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::AttendanceRecord>**](AttendanceRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_balances

> Vec<models::LeaveBalance> list_balances(user_id, year)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
**year** | Option<**i32**> | Defaults to the current calendar year. |  |

### Return type

[**Vec<models::LeaveBalance>**](LeaveBalance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bonuses

> Vec<models::PayrollAdjustment> list_bonuses(user_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
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


## list_deductions

> Vec<models::PayrollAdjustment> list_deductions(user_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
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

> Vec<models::StaffDocument> list_documents(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | The employee's user ID | [required] |

### Return type

[**Vec<models::StaffDocument>**](StaffDocument.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_employees

> Vec<models::Employee> list_employees(department_id, employment_status, search)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**department_id** | Option<**uuid::Uuid**> |  |  |
**employment_status** | Option<**String**> | `active` | `suspended` | `terminated`. Omitted = every status. |  |
**search** | Option<**String**> | Case-insensitive substring over name, employee code, and job title. |  |

### Return type

[**Vec<models::Employee>**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_leave_types

> Vec<models::LeaveType> list_leave_types()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::LeaveType>**](LeaveType.md)

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

> Vec<models::StaffRequest> list_requests(user_id, kind, status, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
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


## my_leave_balances

> Vec<models::LeaveBalance> my_leave_balances(user_id, year)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | Option<**uuid::Uuid**> |  |  |
**year** | Option<**i32**> | Defaults to the current calendar year. |  |

### Return type

[**Vec<models::LeaveBalance>**](LeaveBalance.md)

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


## my_schedule

> Vec<models::ScheduledDay> my_schedule(from, to)
The employee's OWN roster for a date range — what the app's Shifts tab shows.

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


## put_balance

> models::LeaveBalance put_balance(put_balance_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**put_balance_request** | [**PutBalanceRequest**](PutBalanceRequest.md) |  | [required] |

### Return type

[**models::LeaveBalance**](LeaveBalance.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_employee

> models::Employee put_employee(user_id, put_employee_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | The employee's user ID | [required] |
**put_employee_request** | [**PutEmployeeRequest**](PutEmployeeRequest.md) |  | [required] |

### Return type

[**models::Employee**](Employee.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_override

> models::ScheduleOverride put_override(put_override_request)


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


## set_period_status

> models::PayrollPeriod set_period_status(id, period_status_request)


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


## update_leave_type

> models::LeaveType update_leave_type(id, upsert_leave_type_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Leave type ID | [required] |
**upsert_leave_type_request** | [**UpsertLeaveTypeRequest**](UpsertLeaveTypeRequest.md) |  | [required] |

### Return type

[**models::LeaveType**](LeaveType.md)

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

