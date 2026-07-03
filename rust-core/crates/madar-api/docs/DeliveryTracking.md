# DeliveryTracking

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_name** | **String** |  | 
**cancel_reason** | Option<**String**> |  | [optional]
**cancelled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**channel** | **String** |  | 
**confirmed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**customer_name** | **String** |  | 
**delivered_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**delivery_fee** | **i32** |  | 
**delivery_ref** | Option<**String**> |  | [optional]
**discount_amount** | **i32** |  | 
**estimated_prep_minutes** | **i32** | Branch base prep time + the teller's per-order addition (minutes). | 
**floor** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**org_id** | **uuid::Uuid** |  | 
**out_for_delivery_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**payment_method_hint** | Option<**String**> |  | [optional]
**place_name** | Option<**String**> |  | [optional]
**preparing_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**rejected_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**total** | **i32** |  | 
**unit_number** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


