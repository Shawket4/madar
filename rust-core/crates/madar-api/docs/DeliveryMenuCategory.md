# DeliveryMenuCategory

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**display_order** | **i32** | The dashboard's drag-and-drop position (lower first). `categories` already comes in the POS's order (madar-catalog `order`: this, then the English name, then `id`); a page shown in another language re-orders by the name it shows (madar-web `category_order`). | 
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


