# OrderItemInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | Option<[**Vec<models::AddonInput>**](AddonInput.md)> |  | [optional]
**bundle_components** | Option<[**Vec<models::BundleComponentInput>**](BundleComponentInput.md)> |  | [optional]
**bundle_id** | Option<**uuid::Uuid**> |  | [optional]
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**optional_field_ids** | Option<**Vec<uuid::Uuid>**> |  | [optional]
**quantity** | **i32** |  | 
**size_label** | Option<**String**> |  | [optional]
**unit_price** | Option<**i32**> | What the customer was actually charged, in piastres.  Read ONLY when a queued offline sale is replayed — see [`ClientPrices`]. On the live path the server prices the line and this is ignored, so a till cannot charge a price of its own choosing and no manual override exists to let anyone try. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


