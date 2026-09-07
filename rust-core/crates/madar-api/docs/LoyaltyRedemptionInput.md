# LoyaltyRedemptionInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**item_index** | Option<**u32**> | Index into `items`. An index rather than an id because a cart may hold the same menu item on two lines with different modifiers, and only the position tells them apart.  Optional because a TICKET settle names its lines by id instead (see `ticket_line_id`) and the server fills this in — a till settling a ticket cannot see the order the server will flatten its rounds into, and a guessed index takes the wrong item off the bill. | [optional]
**ticket_line_id** | Option<**uuid::Uuid**> | `open_ticket_items.id` — how a ticket settle names the line to cover. Resolved to `item_index` by `settle_open_ticket` before pricing. | [optional]
**units** | Option<**i32**> | How many of that line's units the reward covers. Defaults to one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


