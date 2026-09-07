url="http://localhost:3000"
until curl -fsS "$url" > /dev/null; do sleep 1; done

hydra-create-user admin --role admin --password admin

cookies="$(mktemp)"
trap 'rm -f "$cookies"' EXIT
hcurl() {
  curl -fsS --referer "$url" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    -b "$cookies" -c "$cookies" "$@"
}

hcurl -d '{"username": "admin", "password": "admin"}' "$url/login" > /dev/null

hcurl -X PUT "$url/project/demo" \
  -d '{"displayname": "Demo", "enabled": "1", "visible": "1"}' > /dev/null

hcurl -X PUT "$url/jobset/demo/trivial" -d @- > /dev/null <<EOF
{
  "description": "One instant build (integration test)",
  "checkinterval": "300",
  "enabled": "1",
  "visible": "1",
  "keepnr": "1",
  "nixexprinput": "jobs",
  "nixexprpath": "trivial.nix",
  "inputs": {
    "jobs": { "value": "$DEMO_JOBS", "type": "path" }
  }
}
EOF

hcurl -X POST "$url/api/push?jobsets=demo:trivial" > /dev/null
