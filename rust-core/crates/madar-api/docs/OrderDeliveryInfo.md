# OrderDeliveryInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**channel** | **String** | \"in_mall\" or \"outside\". | 
**customer_phone** | **String** |  | 
**delivery_notes** | Option<**String**> |  | [optional]
**delivery_ref** | Option<**String**> | Human-readable delivery reference (e.g. \"D-DT-260614-0042\"). | [optional]
**floor** | Option<**String**> |  | [optional]
**landmark** | Option<**String**> |  | [optional]
**payment_method_hint** | Option<**String**> | Payment method the customer indicated at intake (\"cash\"/\"card\"); the teller confirms the actual method at finalize. | [optional]
**place_name** | Option<**String**> |  | [optional]
**road_distance_meters** | Option<**i32**> | Road distance (meters) used to price the delivery, when known. | [optional]
**unit_number** | Option<**String**> |  | [optional]
**zone_name** | Option<**String**> | Name of the matched delivery zone ring, when an outside order matched one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


