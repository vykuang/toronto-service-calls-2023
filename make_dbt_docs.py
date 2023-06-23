import json
import re
from pathlib import Path

PATH_DBT_PROJECT = Path.cwd()

search_str = 'o=[i("manifest","manifest.json"+t),i("catalog","catalog.json"+t)]'

with open(PATH_DBT_PROJECT / "target" / "index.html") as f:
    content_index = f.read()

with open(PATH_DBT_PROJECT / "target" / "manifest.json") as f:
    json_manifest = json.loads(f.read())

with open(PATH_DBT_PROJECT / "target" / "catalog.json") as f:
    json_catalog = json.loads(f.read())

# create single docs file in ./public
pub_path = Path(PATH_DBT_PROJECT / "public")
if not pub_path.exists():
    pub_path.mkdir()
with open(pub_path / "index.html", "w") as f:
    new_str = "o=[{label: 'manifest', data: "+json.dumps(json_manifest)+"},{label: 'catalog', data: "+json.dumps(json_catalog)+"}]"
    new_content = content_index.replace(search_str, new_str)
    f.write(new_content)
