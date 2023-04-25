# upload ward.geojson for bq load
resource "google_storage_bucket_object" "ward-geojson" {
  name = "code/city_wards.geojson"
  source = var.geojson_path
  bucket = google_storage_bucket.data-lake.name
}

# destination table for geojson
resource "google_bigquery_table" "ward-geojson" {
  deletion_protection = false
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id = "city_wards_map"
}

# load geojson from bucket into table
resource "google_bigquery_job" "load_geojson" {
  job_id = "load_geojson"
  load {
    source_uris = [
      "gs://${google_storage_bucket_object.ward-geojson.bucket}/${google_storage_bucket_object.ward-geojson.name}"
    ]
    
    destination_table {
      project_id = google_bigquery_table.ward-geojson.project
      dataset_id = google_bigquery_table.ward-geojson.dataset_id.
      table_id =   google_bigquery_table.ward-geojson.table_id
    }

    write_disposition = "WRITE_TRUNCATE"
    autodetect = true
    source_format = "NEWLINE_DELIMITED_JSON"
    json_extension = "GEOJSON"
  }
  depends_on = ["google_storage_bucket_object.ward-geojson"]
}
