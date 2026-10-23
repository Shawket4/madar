# BulkItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category** | **String** | A [`BulkCategory::key`]. | 
**description** | Option<**String**> |  | [optional]
**description_ar** | Option<**String**> |  | [optional]
**groups** | Option<[**Vec<models::BulkLink>**](BulkLink.md)> | The item's groups, in the order the till shows them. | [optional]
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_ar** | Option<**String**> |  | [optional]
**optionals** | Option<[**Vec<models::BulkOptional>**](BulkOptional.md)> | Free-form extras the item alone offers. | [optional]
**price** | **i64** | The item's price; with no `sizes` it is the one price it sells at. | 
**sizes** | Option<[**Vec<models::BulkSize>**](BulkSize.md)> | Each size's full price (not a difference over `price`). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


