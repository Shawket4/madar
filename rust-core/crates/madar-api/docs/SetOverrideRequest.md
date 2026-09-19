# SetOverrideRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**capability** | **String** |  | 
**effect** | **String** | inherit | allow | deny | 
**limits** | Option<[**models::LimitsView**](LimitsView.md)> |  | [optional]
**reason** | Option<**String**> | Optional audit note. Never required: an absent or empty reason is accepted for every capability. Stored (trimmed) when it is sent. | [optional]
**valid_to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


