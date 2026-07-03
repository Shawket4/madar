# AddonInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** |  | 
**quantity** | Option<**i32**> |  | [optional]
**unit_price** | Option<**i32**> | Charged unit price (piastres) the POS applied for this addon. When present it is RECORDED as the addon's unit_price; absent → the server's expected (catalog) price is used. Bundle-component addons ignore this (server-priced). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


