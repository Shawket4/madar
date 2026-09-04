# PutAttendanceSettingsRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absence_deduction_days** | Option<**f64**> |  | [optional]
**auto_checkout_buffer_minutes** | Option<**i32**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> | `None` = the org-wide default row. | [optional]
**default_overtime_multiplier** | Option<**f64**> |  | [optional]
**excused_time_paid_default** | Option<**bool**> |  | [optional]
**late_deduction_tiers** | Option<[**Vec<models::LateTier>**](LateTier.md)> |  | [optional]
**require_geofence** | Option<**bool**> |  | [optional]
**weekend_days** | Option<**Vec<i32>**> |  | [optional]
**working_days_per_month** | Option<**f64**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


