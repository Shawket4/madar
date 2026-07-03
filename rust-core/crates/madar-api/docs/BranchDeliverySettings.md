# BranchDeliverySettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**in_mall_close_time** | Option<**String**> |  | [optional]
**in_mall_discount_id** | Option<**uuid::Uuid**> | Optional discount applied to each channel's item subtotal (reuses the org `discounts` table). Frozen onto the order at intake. `null` = none. | [optional]
**in_mall_enabled** | **bool** |  | 
**in_mall_fee** | **i32** |  | 
**in_mall_open_time** | Option<**String**> |  | [optional]
**in_mall_override** | **String** |  | 
**in_mall_require_location** | **bool** | When false, in-mall orders may be placed without a device GPS location (\"confirm you're at the branch\"). Shop/company + floor + unit are always required regardless. Default true. | 
**max_road_distance_meters** | Option<**i32**> |  | [optional]
**otp_required** | **bool** | When false, the public checkout skips OTP phone verification for this branch and accepts orders without a device token. Default true. | 
**outside_close_time** | Option<**String**> |  | [optional]
**outside_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**outside_enabled** | **bool** |  | 
**outside_open_time** | Option<**String**> |  | [optional]
**outside_override** | **String** |  | 
**pickup_close_time** | Option<**String**> |  | [optional]
**pickup_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**pickup_enabled** | **bool** |  | 
**pickup_fee** | **i32** |  | 
**pickup_open_time** | Option<**String**> |  | [optional]
**pickup_override** | **String** |  | 
**prep_time_minutes** | **i32** |  | 
**umbrella_close_time** | Option<**String**> |  | [optional]
**umbrella_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**umbrella_enabled** | **bool** |  | 
**umbrella_fee** | **i32** | Flat per-branch fees (piastres). Pickup defaults to free. | 
**umbrella_open_time** | Option<**String**> |  | [optional]
**umbrella_override** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


