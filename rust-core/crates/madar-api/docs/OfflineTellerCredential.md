# OfflineTellerCredential

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**is_active** | **bool** |  | 
**name** | **String** |  | 
**offline_pin_hash** | Option<**String**> | argon2id verifier of the user's PIN (derived at online login). `null` until the user has logged in online at least once. | [optional]
**role** | **String** | PIN-login role: `teller`, `waiter`, or `kitchen`. The device uses this to route the offline session (a waiter lands on tickets, a kitchen device on the KDS) without re-querying the backend. | 
**user_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


