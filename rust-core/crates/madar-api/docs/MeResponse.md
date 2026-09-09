# MeResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**currency_code** | **String** | Org currency code (e.g. \"EGP\"). | 
**tax_policy** | [**models::TaxPolicyPublic**](TaxPolicyPublic.md) | The full policy, including tax-inclusive pricing and service charge.  A till re-reads this whenever it syncs, which is what makes a rate changed in the dashboard reach a device that has not signed in for weeks. Without it the till prices under a stale rate and — now that the server refuses totals it disagrees with — cannot sell at all. | 
**tax_rate** | **f64** | Org tax rate as a decimal (e.g. 0.14 = 14% VAT); 0.0 when the user has no org. Exposed so the POS can compute a tax-inclusive cart total client-side. | 
**user** | [**models::UserPublic**](UserPublic.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


