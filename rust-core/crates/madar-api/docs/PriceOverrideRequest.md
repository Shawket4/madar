# PriceOverrideRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**channel** | Option<**String**> | delivery_channel: 'in_mall' | 'outside' | 'umbrella' | 'pickup'. | [optional]
**is_available** | Option<**bool**> |  | [optional]
**price** | Option<**i32**> |  | [optional]
**scope** | **String** | 'branch' | 'channel' | 'branch_channel'. | 
**target_id** | **uuid::Uuid** |  | 
**target_type** | **String** | 'menu_item_size' | 'modifier_option'. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


