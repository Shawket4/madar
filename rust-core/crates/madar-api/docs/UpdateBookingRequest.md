# UpdateBookingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**customer_name** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**party_size** | Option<**i32**> |  | [optional]
**quoted_ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**reserved_for** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | Option<**String**> | Drive the status machine: confirmed / notified / arrived / seated / completed / no_show / cancelled. The matching timestamp is stamped and, for terminals, assigned tables are freed. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


