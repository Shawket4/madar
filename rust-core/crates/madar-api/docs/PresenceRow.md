# PresenceRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_name** | Option<**String**> |  | [optional]
**check_in_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**check_out_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**job_title** | Option<**String**> |  | [optional]
**late_minutes** | **i32** |  | 
**punch_opens_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When a punch for them opens: the next shift of their today (not yet ended; else the first) less its check-in window (CL-3). Null when not rostered. The dashboard offers Punch from then, as the app does (minor default M15). | [optional]
**scheduled_minutes** | **i64** | Minutes this person is rostered for today — the denominator of the labour-vs-plan bar. | 
**state** | **String** | `in` | `late` | `absent` | `on_leave` | `off` | `done`. | 
**worked_minutes** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


