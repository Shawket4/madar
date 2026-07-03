# BranchSettingsInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**in_mall_close_time** | Option<**String**> |  | [optional]
**in_mall_discount_id** | Option<**uuid::Uuid**> | Optional per-channel discount ids (must be active discounts in the caller's org). `null` clears the channel's discount. | [optional]
**in_mall_enabled** | **bool** |  | 
**in_mall_fee** | **i32** |  | 
**in_mall_open_time** | Option<**String**> |  | [optional]
**in_mall_require_location** | Option<**bool**> | When false, in-mall orders are accepted without a device GPS location. Defaults to true so an omitting client keeps the location check on. | [optional]
**max_road_distance_meters** | Option<**i32**> |  | [optional]
**otp_required** | Option<**bool**> | When false, the public checkout skips OTP for this branch. Defaults to true so an omitting client keeps verification on. | [optional]
**outside_close_time** | Option<**String**> |  | [optional]
**outside_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**outside_enabled** | **bool** |  | 
**outside_open_time** | Option<**String**> |  | [optional]
**pickup_close_time** | Option<**String**> |  | [optional]
**pickup_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**pickup_enabled** | Option<**bool**> |  | [optional]
**pickup_fee** | Option<**i32**> |  | [optional]
**pickup_open_time** | Option<**String**> |  | [optional]
**prep_time_minutes** | **i32** |  | 
**umbrella_close_time** | Option<**String**> |  | [optional]
**umbrella_discount_id** | Option<**uuid::Uuid**> |  | [optional]
**umbrella_enabled** | Option<**bool**> |  | [optional]
**umbrella_fee** | Option<**i32**> |  | [optional]
**umbrella_open_time** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


