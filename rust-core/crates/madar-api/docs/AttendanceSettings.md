# AttendanceSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absence_deduction_days** | **f64** |  | 
**advance_cap_percent** | **f64** | Salary advances owed may reach this share of monthly salary (AV-5). | 
**auto_checkout_buffer_minutes** | **i32** |  | 
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**default_overtime_multiplier** | **f64** |  | 
**excused_time_paid_default** | **bool** | Whether an approved mid-shift permission or early departure is PAID by default. The approver may override it on any individual request. | 
**gender_mode** | **String** | `off` · `soft` · `hard`: how the gender default weighs in suggestions (SC-12). | 
**half_day_leave_counts** | **String** | `half_shift` · `whole_day`: what a half-day leave counts as (RQ-8). | 
**holiday_multiplier** | **f64** | What working a set-up holiday pays (RU-10). | 
**id** | **uuid::Uuid** |  | 
**late_deduction_tiers** | Option<**serde_json::Value**> |  | 
**limit_day_hours** | **f64** | Labour limits, hours (RU-13). They warn, never block, and stay unconfirmed until a lawyer signs them off. | 
**limit_overtime_day_hours** | **f64** |  | 
**limit_presence_hours** | **f64** |  | 
**limit_rest_hours** | **f64** |  | 
**limit_week_hours** | **f64** |  | 
**night_end** | **String** |  | 
**night_start** | **String** | Night for the night overtime rate and for suggestions (RU-8, RU-9). | 
**orders_per_staff** | **i32** | POS-derived coverage: one person per this many orders an hour. | 
**org_id** | **uuid::Uuid** |  | 
**overtime_day_multiplier** | **f64** |  | 
**overtime_mode** | **String** | `off` · `automatic` · `approval` (RU-7). | 
**overtime_night_multiplier** | **f64** |  | 
**period_start_day** | **i32** | Day of the month a pay period opens (PAY-1): 26 = a 26th–25th cycle. | 
**require_geofence** | **bool** |  | 
**rules_saved_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the business saved its rules; nobody clocks in before (RU-1). | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**working_days_per_month** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


