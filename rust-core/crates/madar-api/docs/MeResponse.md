# MeResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | Option<**Vec<String>**> | Features the org has as add-ons beside its plan (Rewards by Madar: `[\"loyalty\"]`). | [optional]
**currency_code** | **String** | Org currency code (e.g. \"EGP\"). | 
**plan** | Option<**String**> | The organization's plan: `free` | `paid`. Re-read on every `/auth/me`. | [optional]
**require_table_for_orders** | Option<**bool**> | Every dine-in sale belongs to a table. Re-read on every `/auth/me`, so switching it on reaches a till that has been running for weeks. | [optional]
**tax_policy** | [**models::TaxPolicyPublic**](TaxPolicyPublic.md) | The full policy, including tax-inclusive pricing and service charge.  A till re-reads this whenever it syncs, which is what makes a rate changed in the dashboard reach a device that has not signed in for weeks. Without it the till prices under a stale rate and — now that the server refuses totals it disagrees with — cannot sell at all. | 
**tax_rate** | **f64** | Org tax rate as a decimal (e.g. 0.14 = 14% VAT); 0.0 when the user has no org. Exposed so the POS can compute a tax-inclusive cart total client-side. | 
**user** | [**models::UserPublic**](UserPublic.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


