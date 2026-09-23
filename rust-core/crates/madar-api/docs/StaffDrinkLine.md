# StaffDrinkLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**comp_minor** | Option<**i32**> | What the TILL comped on this line (whole line, minor units). Read ONLY when a queued offline sale is replayed; live, the server prices the comp and this is ignored. | [optional]
**id** | **uuid::Uuid** | Client-minted; the idempotency key AND the `staff_drinks` row's id. A row an older flow already recorded under this id is reused and the order attached to it — never a second drink off the allowance. | 
**note** | **String** | REQUIRED. Who the drink is for and why, in the teller's own words. | 
**overspent** | Option<**bool**> | Whether the till believed this drink went past the allowance. Replay only, and only to tell a convergence from a surprise. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


