# JoinInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**birth_day** | Option<**i32**> |  | [optional]
**birth_month** | Option<**i32**> | The day of their birthday, 1–12 and 1–31. Accepted ONLY where the org asked for one: a field the shop turned off must not be storable by posting past the form.  No year, deliberately. A greeting needs to know WHEN, not how old — and a full date of birth is an identity credential, which is a great deal more than an annual message needs. | [optional]
**branch_id** | Option<**uuid::Uuid**> | The branch whose counter code was scanned, when one was. Absent for an org-wide code — see [`BranchQuery`]. | [optional]
**device_token** | Option<**String**> | Device-trust token from `/public/otp/verify`. Required only when the branch's `require_otp` is on. | [optional]
**locale** | Option<**String**> | 'en' or 'ar' — the language the pass is written in. | [optional]
**name** | **String** |  | 
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**phone** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


