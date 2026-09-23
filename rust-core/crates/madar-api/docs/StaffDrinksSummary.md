# StaffDrinksSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**comp_minor** | **i64** | What the pool comped, minor units (server-priced). | 
**comp_mismatches** | **i64** | Rows whose till-reported comp differs from the server's. | 
**cost_minor** | **i64** | What the drinks cost to make, where known. Counts in FULL: the drink was made whether or not anyone paid for it. | 
**drinks** | **i64** | Rows (lines put on the pool). | 
**extras_minor** | **i64** | What those lines were still charged — the only part that is revenue. | 
**overspent** | **i64** | Of those rows, how many went past the allowance. | 
**quantity** | **i64** | Drinks (the sum of their quantities) — what the allowance is measured in. | 
**unpriced** | **i64** | Record-only rows (no priced sale line behind them; POS ≤ v0.7.12). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


