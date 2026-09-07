# RewardItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_price** | **i32** | Menu price in piastres — what the reward is worth, for the admin's sake. | 
**cost_amount** | **i32** | How much of that currency it costs. Per item, so one catalogue holds \"espresso, 5 visits\" beside \"cake, 10 visits\". | 
**cost_currency** | **String** | `\"points\"` or `\"visits\"` — what this reward is bought with. | 
**image_url** | Option<**String**> |  | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**name** | **String** | Denormalised for display so the teller and the pass need no menu join. | 
**sort_order** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


