# Broadcast

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**apple** | **i64** | Reached an Apple card (pushed). | 
**audience** | [**models::Audience**](Audience.md) |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by_name** | Option<**String**> |  | [optional]
**failed** | **i64** |  | 
**finished_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**google** | **i64** | Accepted by Google (Google gives no delivery signal). | 
**id** | **uuid::Uuid** |  | 
**line_ar** | **String** |  | 
**line_en** | **String** |  | 
**pending** | **i64** |  | 
**recipients** | **i64** |  | 
**scheduled_for** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**seen** | **i64** | Apple devices that fetched the card after the push: delivered. | 
**sent** | **i64** |  | 
**skipped_opted_out** | **i64** |  | 
**skipped_recent** | **i64** |  | 
**started_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** | `scheduled`, `sending`, `sent` or `cancelled`. | 
**unreachable** | **i64** | No card and no WhatsApp asked for. | 
**whatsapp** | **i64** |  | 
**whatsapp_fallback** | **bool** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


