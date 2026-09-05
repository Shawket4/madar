# TablePosition

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**expected_updated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Optimistic-concurrency token: the `updated_at` the client last saw for this table.  The dashboard autosaves every gesture, so two managers arranging the same room no longer collide rarely and visibly -- they collide often and silently, each overwriting the other's last drag. When this is sent, the write only lands if the row has not moved since; otherwise the whole request is rejected and the caller is told exactly which tables changed.  Optional so existing clients (and the POS) keep working unchanged: absent means \"no guard\", which is the previous last-write-wins behaviour. | [optional]
**height** | **f64** |  | 
**id** | **uuid::Uuid** |  | 
**pos_x** | **f64** |  | 
**pos_y** | **f64** |  | 
**rotation** | **f64** |  | 
**section_id** | Option<**uuid::Uuid**> |  | [optional]
**width** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


