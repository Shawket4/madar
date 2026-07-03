# DeliveryMenu

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | [**Vec<models::DeliveryAddonOption>**](DeliveryAddonOption.md) | Org-wide addon catalog (global, POS model): channel-effective, grouped by `type`, applicable to every item. Channel-unavailable options are excluded. | 
**categories** | [**Vec<models::DeliveryMenuCategory>**](DeliveryMenuCategory.md) |  | 
**discount** | Option<[**models::DeliveryMenuDiscount**](DeliveryMenuDiscount.md)> | The active discount for this channel (customer-facing) or `null`. Applies to the item subtotal only — the delivery fee is always charged in full. | [optional]
**items** | [**Vec<models::DeliveryMenuItem>**](DeliveryMenuItem.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


