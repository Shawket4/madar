# MeResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**currency_code** | **String** | Org currency code (e.g. \"EGP\"). | 
**tax_rate** | **f64** | Org tax rate as a decimal (e.g. 0.14 = 14% VAT); 0.0 when the user has no org. Exposed so the POS can compute a tax-inclusive cart total client-side. | 
**user** | [**models::UserPublic**](UserPublic.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


