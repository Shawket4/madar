# Device

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_version** | Option<**String**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**code** | **String** |  | 
**code_conflict** | **bool** | Another live device at the same branch uses the same code. | 
**first_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | [**models::DeviceKind**](DeviceKind.md) |  | 
**label** | Option<**String**> |  | [optional]
**last_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**org_id** | **uuid::Uuid** |  | 
**plan_inactive** | Option<**bool**> | The Free plan switched this till off (it is not its branch's active one): it shows \"This till isn't active\" instead of the sell screen. Always `false` on Paid. | [optional]
**platform** | Option<**String**> |  | [optional]
**retired_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


