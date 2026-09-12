# DeliveryOrder

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**cancel_reason** | Option<**String**> |  | [optional]
**cancel_restocked** | Option<**bool**> |  | [optional]
**cancelled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**cart** | **serde_json::Value** | The frozen priced line snapshot the POS renders before finalize. | 
**channel** | **String** |  | 
**confirmed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**customer_lat** | Option<**f64**> |  | [optional]
**customer_lng** | Option<**f64**> |  | [optional]
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**delivered_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**delivery_fee** | **i32** |  | 
**delivery_notes** | Option<**String**> |  | [optional]
**delivery_ref** | Option<**String**> |  | [optional]
**delivery_zone_id** | Option<**uuid::Uuid**> |  | [optional]
**discount_amount** | Option<**i32**> |  | [optional]
**discount_id** | Option<**uuid::Uuid**> | Frozen channel discount on the item subtotal. `discount_amount` is 0 when none. | [optional]
**discount_rate** | Option<**f64**> | The stored value — a fraction for a percentage. Same column as [`DeliveryOrder::discount_value`]. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**i64**> | LEGACY SPELLING on the wire — an integer, 0-100 for a percentage. See `discounts::wire`: a double here fails to deserialise the whole DELIVERY ORDER on every shipped till, not just this field. | [optional]
**distance_source** | Option<**String**> | How `road_distance_meters` was measured: `osrm` (routed) or `haversine` (straight line — the routing fallback, and always the in-mall walking distance). `None` exactly when no distance was recorded. | [optional]
**extra_prep_minutes** | **i32** | Extra prep minutes the teller added on top of the branch base (multiples of 5). | 
**floor** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**landmark** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**otp_verified** | **bool** |  | 
**out_for_delivery_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**payment_method** | Option<**String**> | What was actually taken at the door. Set at finalize and only then; `Some` exactly when the order is `delivered`. | [optional]
**payment_method_hint** | Option<**String**> | What the customer SAID they would pay with, at checkout. Display only. | [optional]
**place_name** | Option<**String**> |  | [optional]
**preparing_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**receipt_printed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**rejected_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**road_distance_meters** | Option<**i32**> |  | [optional]
**service_charge_amount** | Option<**i32**> | Always 0: the service charge is dine-in only. Present so the till can render the same breakdown for every kind of sale. | [optional]
**service_charge_rate_applied** | Option<**f64**> |  | [optional]
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**tax_amount** | Option<**i32**> | The tax as priced at intake, under the policy frozen beside it. Inside `total` when `tax_inclusive`, added to it otherwise. Finalize does not re-price: a rate the shop changes between the quote and the door does not move a bill the customer already agreed. | [optional]
**tax_inclusive** | Option<**bool**> | Copy of the ONE inclusivity flag (org, branch override) as it stood at intake — not a setting of its own. | [optional]
**tax_rate_applied** | Option<**f64**> | Fraction, not a percentage: `0.14` is 14%. | [optional]
**total** | **i32** | The quote: `subtotal - discount_amount + delivery_fee`, plus `tax_amount` when the tax is exclusive. Replayed verbatim at finalize. | 
**unit_number** | Option<**String**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


