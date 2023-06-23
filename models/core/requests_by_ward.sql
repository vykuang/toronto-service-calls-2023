{{ config(materialized="table", cluster_by="ward_name") }}

with
    w_count as (
        select ward_name, service_request_type, count(1) as ward_count,
        from {{ ref("stg_service_calls") }}
        where ward_name is not null
        group by ward_name, service_request_type
    ),
    w_rank as (
        select
            ward_name,
            service_request_type,
            ward_count,
            rank() over (
                -- ranks wards if partition by type
                partition by service_request_type order by ward_count desc
            ) as ward_rank,
            ward_count / sum(ward_count) over (partition by ward_name) as percentage
        from w_count
    )
select
    w.ward_name as ward_name,
    service_request_type,
    ward_count,
    ward_rank,
    round(percentage, 3) as percentage,
    map.geometry as geometry
from w_rank as w
join {{ ref("stg_city_wards") }} map on w.ward_name = map.ward_name
