# PlanTill

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**active** | **bool** | `false`: the plan switched this till off (not its branch's active one). Always `true` on Paid. | 
**code** | **String** | The till's short code on receipts (`T1`). | 
**device_id** | **uuid::Uuid** |  | 
**label** | Option<**String**> |  | [optional]
**last_sale_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the till last rang a sale, if it ever did. | [optional]
**last_seen_at** | **chrono::DateTime<chrono::FixedOffset>** | When the till last talked to the server. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


