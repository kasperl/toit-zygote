import expect show *
import net
import http
import encoding.json

import zygote.mode as mode
import zygote.setup as setup

class MockAccessPoint:
  ssid/string
  rssi/int
  constructor .ssid .rssi:

read_body_ response/http.Response -> string:
  bytes := #[]
  while data := response.body.read:
    bytes += data
  return bytes.to_string

main:
  expect (mode.is_missing_wifi_configuration_error "WIFI_CONNECT_FAILED: wifi ssid not provided")
  expect (not mode.is_missing_wifi_configuration_error "WIFI_CONNECT_FAILED: auth_fail")

  network := net.open
  access_points := [
    MockAccessPoint "MyNetwork" -50,
    MockAccessPoint "Other<script>alert(1)</script>" -70,
  ]

  // Start the HTTP server in a separate task on a fixed local port.
  submitted/Map? := null
  server_task := task::
    submitted = setup.run_http network access_points --port=8080

  // Give the server a moment to start listening.
  sleep --ms=500

  client := http.Client network
  try:
    // The default index is served when no custom assets are bundled,
    // and it should list the scanned access points with HTML escaping.
    response := client.get --host="127.0.0.1" --port=8080 --path="/"
    expect_equals 200 response.status_code
    expect_equals "close" (response.headers.single "Connection")
    body := read_body_ response
    expect (body.contains "Update WiFi settings")
    expect (body.contains "MyNetwork")
    expect (body.contains "Other&lt;script&gt;alert(1)&lt;/script&gt;")
    expect (not body.contains "<script>alert(1)</script>")

    // Apple captive-portal detection path serves index.html.
    response = client.get --host="127.0.0.1" --port=8080 --path="/hotspot-detect.html"
    expect_equals 200 response.status_code
    expect ((read_body_ response).contains "Update WiFi settings")

    // The access-points endpoint exposes the cached scan as JSON.
    response = client.get --host="127.0.0.1" --port=8080 --path="/access-points.json"
    expect_equals 200 response.status_code
    decoded := json.decode (read_body_ response).to_byte_array
    expect_equals 2 decoded.size
    expect_equals "MyNetwork" decoded[0]["ssid"]
    expect_equals -50 decoded[0]["rssi"]

    // Unknown resources return 404.
    response = client.get --host="127.0.0.1" --port=8080 --path="/does-not-exist.txt"
    expect_equals 404 response.status_code
    read_body_ response

    // Submitting credentials trims the SSID, but preserves leading and
    // trailing spaces in the WPA2 password.
    response = client.get --host="127.0.0.1" --port=8080 --path="/?ssid=%20MyNetwork%20&password=%20secret%20"
    expect_equals 200 response.status_code
    read_body_ response
  finally:
    client.close
    network.close
    server_task.cancel

  expect_not_null submitted
  expect_equals "MyNetwork" submitted["ssid"]
  expect_equals " secret " submitted["password"]
