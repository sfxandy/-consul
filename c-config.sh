CONSUL=http://<one-of-your-servers>:8500

# 1) Virtual mesh service (the “name” Service-A will call)
curl -sS -X PUT "$CONSUL/v1/config/service-defaults/dev-credit-foo-bar" \
  -H 'Content-Type: application/json' \
  -d '{"Kind":"service-defaults","Name":"dev-credit-foo-bar","Protocol":"http"}'

# 2) Authorize this TGW to serve that service
curl -sS -X PUT "$CONSUL/v1/config/terminating-gateway/egress-tgw" \
  -H 'Content-Type: application/json' \
  -d '{"Kind":"terminating-gateway","Name":"egress-tgw","Services":[{"Name":"dev-credit-foo-bar"}]}'

# 3) Tell Consul where that virtual service actually goes (external host:port)
# Simple, direct mapping using a resolver override in 1.21.x
curl -sS -X PUT "$CONSUL/v1/config/service-resolver/dev-credit-foo-bar" \
  -H 'Content-Type: application/json' \
  -d '{
        "Kind":"service-resolver",
        "Name":"dev-credit-foo-bar",
        "Redirect": { "Service": "dev-credit-foo-bar-external" }
      }'

curl -sS -X PUT "$CONSUL/v1/config/service-defaults/dev-credit-foo-bar-external" \
  -H 'Content-Type: application/json' \
  -d '{
        "Kind":"service-defaults",
        "Name":"dev-credit-foo-bar-external",
        "Protocol":"http"
      }'

curl -sS -X PUT "$CONSUL/v1/config/service-resolver/dev-credit-foo-bar-external" \
  -H 'Content-Type: application/json' \
  -d "{
        \"Kind\":\"service-resolver\",
        \"Name\":\"dev-credit-foo-bar-external\",
        \"Subsets\": {
          \"default\": {
            \"Service\":\"dev-credit-foo-bar-external\",
            \"Override\": { \"Address\":\"ggdgsswpo350.foodc.emea.bank.com\", \"Port\":49519 }
          }
        }
      }"
