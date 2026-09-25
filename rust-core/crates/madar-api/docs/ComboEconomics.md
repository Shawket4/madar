# ComboEconomics

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**cost_default** | Option<**i64**> | `null` when any cost involved is unknown. | [optional]
**cost_max** | Option<**i64**> |  | [optional]
**list_default** | **i64** | À la carte value of the default picks at their included sizes. | 
**list_max** | **i64** |  | 
**list_min** | **i64** | The cheapest and dearest valid pick sets, at their included sizes. | 
**margin_default** | Option<**String**> | Fractions as strings (\"0.5933\"); `null` when the cost is unknown or P is 0. | [optional]
**margin_worst** | Option<**String**> |  | [optional]
**min_margin** | Option<**String**> |  | [optional]
**price** | **i64** | P at this branch. | 
**saving_default** | **i64** | `list_default − price`. | 
**warnings** | [**Vec<models::ComboWarning>**](ComboWarning.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


