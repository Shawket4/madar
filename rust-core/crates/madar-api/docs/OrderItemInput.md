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
**unit_price** | Option<**i32**> | Charged unit price (piastres) the POS applied for this item/bundle line. When present it is RECORDED as the line's unit_price; absent → the server's expected (catalog + branch override) price is used. Recording what the customer was actually charged keeps the DB equal to the printed receipt even when the POS's synced menu/override prices are stale or it was offline at sale time. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


