# ComboPickInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | Option<[**Vec<models::AddonInput>**](AddonInput.md)> |  | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**notes** | Option<**String**> |  | [optional]
**optional_field_ids** | Option<**Vec<uuid::Uuid>**> |  | [optional]
**quantity** | Option<**i32**> | Units per combo unit; the part line's quantity is this × the line's. | [optional]
**share** | Option<**i32**> | Replay only: this pick's share of P, per combo unit. | [optional]
**size_label** | Option<**String**> |  | [optional]
**slot_id** | **uuid::Uuid** |  | 
**surcharge** | Option<**i32**> | Replay only: this pick's surcharge (choice + size), per combo unit. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


