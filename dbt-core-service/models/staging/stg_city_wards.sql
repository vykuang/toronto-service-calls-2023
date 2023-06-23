{{ config(materialized="view") }}

select area_name as ward_name, area_short_code as ward_id, geometry
from {{ source("staging", "city_wards_map") }}
