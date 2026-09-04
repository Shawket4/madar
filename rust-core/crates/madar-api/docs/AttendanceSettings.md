# AttendanceSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absence_deduction_days** | **f64** |  | 
**auto_checkout_buffer_minutes** | **i32** |  | 
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**default_overtime_multiplier** | **f64** |  | 
**excused_time_paid_default** | **bool** | Whether an approved mid-shift permission or early departure is PAID by default. The approver may override it on any individual request. | 
**id** | **uuid::Uuid** |  | 
**late_deduction_tiers** | Option<**serde_json::Value**> |  | 
**org_id** | **uuid::Uuid** |  | 
**require_geofence** | **bool** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**weekend_days** | **Vec<i32>** |  | 
**working_days_per_month** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


