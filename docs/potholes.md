# Potholes

Summary of problems along the way

## Fetch

- Field in `Ward` not following the `ward name (ward_id)` format
    - add `try/except` block
- certain rows having more than expected field
    - add `on_bad_lines='skip'` in `pd.read_csv`
- FileNotFound: Zip in lower case, but csv in upper case
    - more robust method to look for csv - glob `*.csv` instead

## Terraform

- Remote backend must already exist for terraform to initialize; bucket must be separate from `main.tf`, as it cannot use a bucket it built as its own backend