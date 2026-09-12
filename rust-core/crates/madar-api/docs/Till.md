# Till

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**is_default** | **bool** |  | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**standard_float** | Option<**i32**> | The cash that should be in this drawer at the start of a shift, in minor units. The shift report proposes closing at it (\"leave the float, drop the rest into the safe\"); `None` means the shop has not decided and nothing is proposed. | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


