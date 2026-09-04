# OrgPaymentMethod

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**color** | **String** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**icon** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**is_cash** | **bool** |  | 
**label_translations** | Option<**serde_json::Value**> |  | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**visible_in_integrations** | **bool** | When false, orders tendered with this method are excluded entirely from the partner analytics API (`/integrations/analytics/orders`) — rows and aggregates alike. Defaults to true. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


