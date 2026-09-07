{ pkgs, demoJobs }:
pkgs.writeShellApplication {
  name = "demo-trigger-wave";
  runtimeInputs = [
    pkgs.curl
    pkgs.coreutils
  ];
  text = ''
    tag="''${1:-$(date +%s)}"
    url="http://localhost:3000"
    cookies="$(mktemp)"
    trap 'rm -f "$cookies"' EXIT

    hcurl() {
      curl -fsS --referer "$url" \
        -H "Accept: application/json" -H "Content-Type: application/json" \
        -b "$cookies" -c "$cookies" "$@"
    }

    hcurl -d '{"username": "admin", "password": "admin"}' "$url/login" > /dev/null

    hcurl -X PUT "$url/jobset/demo/wave" -d @- > /dev/null <<EOF
    {
      "description": "Demo wave (sleep jobs)",
      "checkinterval": "300",
      "enabled": "1",
      "visible": "1",
      "keepnr": "1",
      "nixexprinput": "jobs",
      "nixexprpath": "wave.nix",
      "inputs": {
        "jobs": { "value": "${demoJobs}", "type": "path" },
        "wave": { "value": "$tag", "type": "string" }
      }
    }
    EOF

    hcurl -X POST "$url/api/push?jobsets=demo:wave" > /dev/null
    echo "wave '$tag' triggered: 60 builds queued for demo:wave"
  '';
}
