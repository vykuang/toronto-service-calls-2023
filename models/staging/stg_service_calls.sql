{{
    config(
        materialized="view",
        partition_by={
            "field": "creation_datetime",
            "data_type": "timestamp",
            "granularity": "day",
        },
    )
}}
-- dbt_utils updated surrogate_key to generate_surrogate_key
select
    {{
        dbt_utils.generate_surrogate_key(
            ["creation_datetime", "ward_id", "Service_Request_Type"]
        )
    }} as request_id,
    case
        when
            extract(month from creation_datetime) < 3
            or extract(month from creation_datetime) > 11
        then 'winter'
        when extract(month from creation_datetime) < 6
        then 'spring'
        when extract(month from creation_datetime) < 9
        then 'summer'
        else 'fall'
    end season,
    *
from
    {{ source("staging", "facts_2023_partitioned") }}

    -- dbt build --m <model.sql> --var 'is_test_run: false'
    {% if var("is_test_run", default=true) %} tablesample system(10 percent) {% endif %}

where
    ward_id is not null
    and creation_datetime is not null
    and service_request_type is not null
