# BulkReviewResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**pending** | [**Vec<models::BulkReviewPending>**](BulkReviewPending.md) | An id this call could not resolve, and why. Never silently dropped. | 
**resolved** | **Vec<i64>** | Ids that are now reviewed (already reviewed counts as resolved too — resubmitting the same batch never fails or double-records). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


