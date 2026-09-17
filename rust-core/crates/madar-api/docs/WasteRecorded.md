# WasteRecorded

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**created** | **bool** | `false` when this id had already been recorded (nothing new was posted). | 
**id** | **uuid::Uuid** |  | 
**lines** | [**Vec<models::WasteLine>**](WasteLine.md) |  | 
**note** | Option<**String**> |  | [optional]
**occurred_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**quantity** | **f64** |  | 
**reason** | **String** |  | 
**recorded_by** | Option<**uuid::Uuid**> |  | [optional]
**size_label** | Option<**String**> |  | [optional]
**source** | **String** |  | 
**subject_kind** | **String** |  | 
**subject_name** | **String** |  | 
**unit** | **String** |  | 
**value_minor** | Option<**i64**> | Piastres at the branch's unit costs; `null` when no line had a cost. | [optional]
**value_partial** | **bool** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


