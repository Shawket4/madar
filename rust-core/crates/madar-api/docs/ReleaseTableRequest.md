# ReleaseTableRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**bus** | Option<**bool**> | The party ATE here and has paid: the table needs bussing before anyone else sits, so it lands `dirty` rather than `free`. The same fork the till makes locally when a parked order checks out versus is discarded -- a discard means nobody ever sat, and the table goes straight back to the room. Without this the dashboard would show a table with dirty plates on it as ready for the next party. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


