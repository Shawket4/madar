# MaterialCostTrendRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_cost** | **i64** | Piastres per base stock unit, the receipt just before the streak began. | 
**cheaper_cost** | Option<**i64**> |  | [optional]
**cheaper_supplier_id** | Option<**uuid::Uuid**> |  | [optional]
**cheaper_supplier_name** | Option<**String**> |  | [optional]
**current_cost** | **i64** | Piastres per base stock unit, most recent receipt. | 
**current_supplier_id** | Option<**uuid::Uuid**> |  | [optional]
**current_supplier_name** | **String** |  | 
**ingredient_name** | **String** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**pct_increase** | **f64** | `(current_cost - base_cost) / base_cost * 100`, 1 dp. | 
**streak_length** | **i64** | Number of consecutive received deliveries, most recent first, each pricier than the one before it. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


