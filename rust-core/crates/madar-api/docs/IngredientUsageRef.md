# IngredientUsageRef

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**detail** | Option<**String**> | Extra context: the size label, the option's group, the PO's branch, the transfer's route. | [optional]
**id** | **uuid::Uuid** | The using entity's id (menu item, option, base, rule, PO, count, transfer). | 
**kind** | **String** | `recipe` (a menu item size's recipe) | `modifier_option` (an add-on's or option's recipe line) | `swap` (an option that replaces it, e.g. a milk swap) | `recipe_base` | `packaging_rule` | `purchase_order` (open: draft, ordered, partially received) | `stocktake` (open count) | `transfer` (requested, draft or dispatched). | 
**name** | **String** | Its display name (menu item / option / base / rule name, PO reference or supplier, the count's branch, `#<number>` for a transfer). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


