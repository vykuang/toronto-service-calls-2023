with daily_count as (
  select
    service_request_type,
    date(creation_datetime) as request_date,
    count(1) daily 
  FROM {{ ref("stg_service_calls") }}
  group by date(creation_datetime), service_request_type
)
SELECT 
  *,
  sum(daily_count.daily)
  over (
    partition by service_request_type 
    order by request_date
    rows between unbounded preceding and current row
  ) as type_cum_total
FROM daily_count
order by service_request_type, request_date