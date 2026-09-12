# TicketBill

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**discount_amount** | **i32** | The waiter's discount, resolved (a `discount_id` is looked up the way the settle looks it up). A cashier who clears it at settle will see a different total than this one, and that is the point of showing it. | 
**service_charge_amount** | **i32** |  | 
**service_charge_rate** | **f64** |  | 
**subtotal** | **i32** | Live lines as charged, before discount. Gross when tax-inclusive. | 
**tax_amount** | **i32** | Inside the total when `tax_inclusive`, on top of it otherwise. | 
**tax_inclusive** | **bool** |  | 
**tax_rate** | **f64** | The rates the figures were computed under, for the printed bill. | 
**total** | **i32** | What the drawer must collect. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


