# OfflineAuthBundle

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**generated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**lan_secret** | **String** | The org's stable LAN-relay secret, hex-encoded. Devices derive a per-branch HMAC-SHA256 subkey from it to sign every LAN message (Phase E), so only branch-provisioned devices are trusted on the shared Wi-Fi. | 
**org_id** | **uuid::Uuid** |  | 
**tellers** | [**Vec<models::OfflineTellerCredential>**](OfflineTellerCredential.md) | All PIN-login credentials for the org (tellers, waiters, and kitchen devices). Field name kept as `tellers` for wire compatibility; it carries every offline-capable role, distinguished by `role`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


