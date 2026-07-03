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
**discount_id** | Option<**uuid::Uuid**> | Frozen channel discount on the item subtotal (`total == subtotal - discount_amount + delivery_fee`). `discount_amount` is 0 when none. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**i32**> |  | [optional]
**extra_prep_minutes** | **i32** | Extra prep minutes the teller added on top of the branch base (multiples of 5). | 
**floor** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**landmark** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**otp_verified** | **bool** |  | 
**out_for_delivery_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**payment_method_hint** | Option<**String**> |  | [optional]
**place_name** | Option<**String**> |  | [optional]
**preparing_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**receipt_printed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**rejected_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**road_distance_meters** | Option<**i32**> |  | [optional]
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**total** | **i32** |  | 
**unit_number** | Option<**String**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


