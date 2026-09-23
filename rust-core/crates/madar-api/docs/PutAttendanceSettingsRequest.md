# PutAttendanceSettingsRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absence_deduction_days** | Option<**f64**> |  | [optional]
**advance_cap_percent** | Option<**f64**> |  | [optional]
**auto_checkout_buffer_minutes** | Option<**i32**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> | `None` = the org-wide default row. | [optional]
**default_overtime_multiplier** | Option<**f64**> |  | [optional]
**excused_time_paid_default** | Option<**bool**> |  | [optional]
**gender_mode** | Option<**String**> | `off` · `soft` · `hard`; owner only (`hr.roster.settings`). | [optional]
**half_day_leave_counts** | Option<**String**> | `half_shift` · `whole_day`. | [optional]
**holiday_multiplier** | Option<**f64**> |  | [optional]
**inherit** | Option<**Vec<String>**> | Branch only: rules to take from the business again (field names, as in `overridden`). | [optional]
**late_deduction_tiers** | Option<[**Vec<models::LateTier>**](LateTier.md)> |  | [optional]
**limit_day_hours** | Option<**f64**> |  | [optional]
**limit_overtime_day_hours** | Option<**f64**> |  | [optional]
**limit_presence_hours** | Option<**f64**> |  | [optional]
**limit_rest_hours** | Option<**f64**> |  | [optional]
**limit_week_hours** | Option<**f64**> |  | [optional]
**night_end** | Option<**String**> |  | [optional]
**night_start** | Option<**String**> |  | [optional]
**orders_per_staff** | Option<**i32**> |  | [optional]
**overtime_day_multiplier** | Option<**f64**> |  | [optional]
**overtime_mode** | Option<**String**> | `off` · `automatic` · `approval`. | [optional]
**overtime_night_multiplier** | Option<**f64**> |  | [optional]
**period_start_day** | Option<**i32**> |  | [optional]
**require_geofence** | Option<**bool**> |  | [optional]
**working_days_per_month** | Option<**f64**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


