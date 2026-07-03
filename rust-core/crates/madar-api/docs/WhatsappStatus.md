# WhatsappStatus

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**configured** | **bool** | `WHATSAPP_SERVICE_URL` is set on the backend. | 
**connected** | **bool** | Underlying socket is connected to WhatsApp. | 
**has_qr** | **bool** | A pairing QR is currently available to scan. | 
**logged_in** | **bool** | A number is linked and ready to send. | 
**paused** | **bool** | Sending is paused by an admin — the number stays linked but every outbound message (OTP + status) is suppressed until resumed. | 
**paused_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When sending was last paused (audit). | [optional]
**qr_image** | Option<**String**> | Current pairing QR as a `data:image/png;base64,…` URL (only when `has_qr`). | [optional]
**reachable** | **bool** | The gateway answered over HTTP (false = not configured or unreachable). | 
**session** | **String** | Session name the relay pairs/sends under. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


