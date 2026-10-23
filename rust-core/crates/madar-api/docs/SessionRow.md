# SessionRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**branch_name** | Option<**String**> |  | [optional]
**client** | Option<**String**> | `X-Madar-Client`: `<app>/<version> (<platform>)`. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**device_id** | Option<**String**> |  | [optional]
**expires_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**ip** | Option<**String**> |  | [optional]
**kind** | **String** |  | 
**last_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**org_name** | Option<**String**> |  | [optional]
**revoke_reason** | Option<**String**> |  | [optional]
**revoked_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**revoked_by_name** | Option<**String**> |  | [optional]
**role** | **String** |  | 
**state** | **String** | `active` | `revoked` | `expired`. | 
**user_agent** | Option<**String**> |  | [optional]
**user_email** | Option<**String**> |  | [optional]
**user_id** | **uuid::Uuid** |  | 
**user_name** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


