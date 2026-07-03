# UpdateBundleRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**available_from_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_from_time** | Option<**String**> | `null`  → clear the field (no start time restriction) omitted → keep the existing value a value → set to that time | [optional]
**available_until_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_until_time** | Option<**String**> |  | [optional]
**branch_ids** | Option<**Vec<uuid::Uuid>**> |  | [optional]
**components** | Option<[**Vec<models::CreateBundleComponentInput>**](CreateBundleComponentInput.md)> |  | [optional]
**description** | Option<**String**> |  | [optional]
**description_translations** | Option<**serde_json::Value**> |  | [optional]
**image_url** | Option<**String**> |  | [optional]
**name** | Option<**String**> |  | [optional]
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**price** | Option<**i32**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


