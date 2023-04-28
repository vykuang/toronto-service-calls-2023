# Visualization

Whiteboard for basic data viz of the service call dataset

- Requests by ward
- Requests by season
- Wards by request
- Total service call by status

Let's focus on the choropleth:

- use ward map as the basis
- add control filter for season
- tool-tip for top-`n` request types?
  - stick with ward name; use color depth to differentiate
- color depth for subtotal count of that ward

## Time-series

Charts how the requests pile up

- use the facts table as basisfor their `creation_datetime`
- subtotal count for each day

## Requests by ward

Map of the wards

- color depth - total count
- tool-tip - top `n` most frequent request types

## Requests by season

Bar? Pie? Table? Control for season? Combine with ward map?

## Wards by request

Table?

Select one request type - show the top wards

## total service by status

Show YTD count for each status type in a pie chart
