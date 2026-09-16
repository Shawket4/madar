# ActivationCode

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**code** | **String** | The 8 digits. Shown while free; kept afterwards so the list reads. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**expires_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | [**models::DeviceKind**](DeviceKind.md) |  | 
**label** | Option<**String**> |  | [optional]
**revoked_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**state** | [**models::ActivationCodeState**](ActivationCodeState.md) |  | 
**used_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**used_by_device** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


