# SetOverrideRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**capability** | **String** |  | 
**effect** | **String** | inherit | allow | deny | 
**limits** | Option<[**models::LimitsView**](LimitsView.md)> |  | [optional]
**reason** | Option<**String**> |  | [optional]
**valid_to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


