# TaxReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**discount_amount** | **i64** |  | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**net_revenue** | **i64** | `total_amount`, net of refunds, across every branch. | 
**net_tax_due** | **i64** | `tax_collected - refunded_tax` — what is actually owed for the period. | 
**order_count** | **i64** |  | 
**org_tax_rate** | **f64** | The org's current tax rate, as a decimal fraction. Informational only — individual orders carry the rate that was actually applied at sale time (`tax_rate_applied`), which may differ if the rate changed since. | 
**refunded_tax** | **i64** |  | 
**service_charge_amount** | **i64** | Net of refunded service charge. | 
**subtotal** | **i64** | Sum of `orders.subtotal` across every branch, before discount or tax. | 
**tax_collected** | **i64** | Tax on every non-voided sale in the range, before refunds (a sale later refunded in full included). | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


