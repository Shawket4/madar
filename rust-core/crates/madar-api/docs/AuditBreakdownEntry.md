# AuditBreakdownEntry

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_minor** | **i64** |  | 
**code** | Option<**String**> | A stable code for a label the SERVER wrote (`unspecified`, `correction_request`, `auto_closed`, a void reason), so a client words it in its own language (AT-13, E2E B-PAY-5). Absent for a person's own words (a typed reason, a name): `label` is the text. | [optional]
**count** | **i64** |  | 
**label** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


