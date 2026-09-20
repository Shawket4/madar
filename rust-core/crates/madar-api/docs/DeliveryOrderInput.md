# DeliveryOrderInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**channel** | **String** |  | 
**contact_device_token** | Option<**String**> | A one-time order to a different phone, at a branch that requires OTP: the device token proving THAT phone. | [optional]
**customer_lat** | Option<**f64**> |  | [optional]
**customer_lng** | Option<**f64**> |  | [optional]
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**delivery_notes** | Option<**String**> |  | [optional]
**device_token** | **String** | Device-trust token from OTP verify (proves the phone). With `member_token` it must prove the CUSTOMER's phone, not the typed one. | 
**floor** | Option<**String**> |  | [optional]
**identity_change** | Option<**String**> | What a typed name/phone that differs from the customer's MEANS: `\"one_time\"` (ordering for someone else: the order's snapshot carries the typed contact, the profile is untouched) or `\"update_name\"` (correct the stored name). A different PHONE with no choice is refused with 409 `IDENTITY_CHOICE_REQUIRED` (`kind: \"phone\"`); a different name alone defaults to one-time. Ignored without `member_token`. | [optional]
**items** | [**Vec<models::CartLineInput>**](CartLineInput.md) |  | 
**landmark** | Option<**String**> |  | [optional]
**member_token** | Option<**String**> | Ordering from a loyalty card (\"order now\"): the order belongs to the card's customer whatever name and phone are typed. The server compares the typed contact with the customer's and classifies the difference — see `identity_change`. | [optional]
**payment_method_hint** | **String** | \"cash\" | \"card\" — a hint the teller can change at finalize. | 
**place_name** | Option<**String**> |  | [optional]
**save_address** | Option<**bool**> | Keep the address on the customer's profile. Defaults to yes for an ordinary order and to NO for a one-time order for someone else. | [optional]
**unit_number** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


