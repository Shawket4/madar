# LastPrice

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ordered_at** | **chrono::DateTime<chrono::FixedOffset>** | When the purchase order was raised. | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**po_id** | **uuid::Uuid** | The purchase order the price comes from. | 
**po_status** | **String** |  | 
**prices** | [**Vec<models::LastUnitPrice>**](LastUnitPrice.md) | The same price in every unit a new line for this ingredient can be ordered in (its measure's units and its named pack), converted through the ingredient's units. A unit that does not convert is left out: the client then offers no default for it. | 
**received** | **bool** | True when the price is what a delivery was actually invoiced at (a goods receipt), false when it is only what was ordered. | 
**received_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the delivery the price comes from was received (`received` only). | [optional]
**source** | [**models::LastPriceSource**](LastPriceSource.md) |  | 
**supplier_id** | Option<**uuid::Uuid**> |  | [optional]
**supplier_name** | Option<**String**> |  | [optional]
**unit** | **String** | The remembered line's purchase unit. | 
**unit_price** | **f64** | Piastres per one `unit`, exact (6 dp). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


