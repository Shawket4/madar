# PresenceRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_name** | Option<**String**> |  | [optional]
**check_in_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**check_out_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**job_title** | Option<**String**> |  | [optional]
**late_minutes** | **i32** |  | 
**scheduled_minutes** | **i64** | Minutes this person is rostered for today — the denominator of the labour-vs-plan bar. | 
**state** | **String** | `in` | `late` | `absent` | `on_leave` | `off` | `done`. | 
**user_id** | **uuid::Uuid** |  | 
**user_name** | **String** |  | 
**worked_minutes** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


