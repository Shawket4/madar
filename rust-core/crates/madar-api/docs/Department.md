# Department

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**employee_count** | **i64** | Live employees currently assigned. Not stored. | 
**id** | **uuid::Uuid** |  | 
**manager_name** | Option<**String**> | Denormalised for the dashboard list; not stored. | [optional]
**manager_user_id** | Option<**uuid::Uuid**> |  | [optional]
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


