# TillPreFill

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**has_open_till** | **bool** |  | 
**last_close_declared** | Option<**i32**> |  | [optional]
**open_at_branch** | Option<[**Vec<models::TillBrief>**](TillBrief.md)> | EVERY open till of the person at THIS branch, newest first (whatever the device). Normally zero or one; two or more only after an offline open was replayed while another was open — the newer is flagged (`opened_while_another_open`) and both stay open, so both are listed. | [optional]
**open_bills_notice** | [**models::OpenBillsNotice**](OpenBillsNotice.md) |  | 
**open_elsewhere** | [**Vec<models::TillBrief>**](TillBrief.md) |  | 
**open_till** | Option<[**models::Till**](Till.md)> |  | [optional]
**suggested_opening_cash** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


