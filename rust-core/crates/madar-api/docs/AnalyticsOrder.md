# AnalyticsOrder

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**business_date** | **chrono::NaiveDate** | Calendar day the order belongs to, in the branch's timezone. Derived from `created_at` — the SAME derivation the receipt's `order_ref` uses, so the date here always matches the date embedded in that reference. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**discount_amount** | **i32** |  | 
**order_id** | **uuid::Uuid** |  | 
**order_number** | **i32** | Per-shift sequence number shown on the POS. | 
**order_ref** | Option<**String**> | The human-readable reference printed on the receipt (`<BRANCHCODE>-<YYMMDD>-<NNNN>`). Null for orders predating it. | [optional]
**service_charge** | **i32** | Always 0: Madar has no service-charge concept. Present so the field is stable if one is ever introduced. | 
**status** | **String** |  | 
**subtotal** | **i32** | Piastres. Sum of the line items before discount and tax. | 
**tax_amount** | **i32** |  | 
**total_amount** | **i32** | `subtotal - discount_amount + tax_amount`. Deliberately COMPUTED rather than read from `orders.total_amount`, which also carries the delivery fee — this figure is the order's own value and nothing else. Tips are excluded too (they are not part of `total_amount` in the first place). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


