# Device

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_version** | Option<**String**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**code** | **String** |  | 
**code_conflict** | **bool** | Another live device at the same branch uses the same code. | 
**first_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | [**models::DeviceKind**](DeviceKind.md) |  | 
**label** | Option<**String**> |  | [optional]
**last_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**org_id** | **uuid::Uuid** |  | 
**platform** | Option<**String**> |  | [optional]
**retired_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


