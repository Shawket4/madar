# LoginResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | Option<**Vec<String>**> | Features the org has as add-ons beside its plan (Rewards by Madar: `[\"loyalty\"]` on Free). Additive: an old client ignores it and sees the plan alone. | [optional]
**currency_code** | **String** |  | 
**open_till** | Option<[**models::TillBrief**](TillBrief.md)> | The person's open till at the branch they signed into (any device), so the device can resume it or show where it is open. | [optional]
**plan** | Option<**String**> | The organization's plan: `free` | `paid` (`madar-plan`; an old client that does not read it behaves as before, and a missing value is `paid`). A till also learns it from the sync feed's branch settings. | [optional]
**require_table_for_orders** | Option<**bool**> | Every dine-in sale belongs to a table.  The till needs this, not just the server: the rule changes what the POS puts in front of a teller — the floor becomes the home screen and a sale starts by picking a table — and a refusal AFTER the items are rung up is far too late to be useful. | [optional]
**tax_policy** | [**models::TaxPolicyPublic**](TaxPolicyPublic.md) | The full policy, including tax-inclusive pricing and service charge. Prefer this over the flat `tax_rate` above. | 
**tax_rate** | **f64** | Org tax rate as a decimal (e.g. 0.14 = 14% VAT); 0.0 when no org. Mirrors /auth/me so the POS has it immediately after login. | 
**token** | **String** | JWT to send as `Authorization: Bearer <token>` on subsequent requests. | 
**user** | [**models::UserPublic**](UserPublic.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


