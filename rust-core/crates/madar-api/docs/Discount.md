# Discount

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**dtype** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**value** | **i64** | LEGACY SPELLING — an integer, 0-100 for a percentage, minor units for `fixed`. What every shipped client was generated against; see `discounts::wire`. Read [`Discount::value_rate`] for the real stored number. | 
**value_rate** | Option<**f64**> | The stored value: a FRACTION for `percentage` (0.14 = 14%, like every other rate in this schema), or minor units for `fixed`. The same column as [`Discount::value`], spelled the way the engine holds it. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


