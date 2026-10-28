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

read-body_ response/http.Response -> string:
  bytes := #[]
  while data := response.body.read:
    bytes += data
  return bytes.to-string

main:
  expect (mode.is-missing-wifi-configuration-error "WIFI_CONNECT_FAILED: wifi ssid not provided")
  expect (not mode.is-missing-wifi-configuration-error "WIFI_CONNECT_FAILED: auth_fail")

  network := net.open
  access-points := [
    MockAccessPoint "MyNetwork" -50,
    MockAccessPoint "Other<script>alert(1)</script>" -70,
  ]

  // Start the HTTP server in a separate task on a fixed local port.
  submitted/Map? := null
  server-task := task::
    submitted = setup.run-http network access-points --port=8080

  // Give the server a moment to start listening.
  sleep --ms=500

  client := http.Client network
  try:
    // The default index is served when no custom assets are bundled,
    // and it should list the scanned access points with HTML escaping.
    response := client.get --host="127.0.0.1" --port=8080 --path="/"
    expect-equals 200 response.status-code
    expect-equals "close" (response.headers.single "Connection")
    body := read-body_ response
    expect (body.contains "Update WiFi settings")
    expect (body.contains "MyNetwork")
    expect (body.contains "Other&lt;script&gt;alert(1)&lt;/script&gt;")
    expect (not body.contains "<script>alert(1)</script>")

    // Apple captive-portal detection path serves index.html.
    response = client.get --host="127.0.0.1" --port=8080 --path="/hotspot-detect.html"
    expect-equals 200 response.status-code
    expect ((read-body_ response).contains "Update WiFi settings")

    // The access-points endpoint exposes the cached scan as JSON.
    response = client.get --host="127.0.0.1" --port=8080 --path="/access-points.json"
    expect-equals 200 response.status-code
    decoded := json.decode (read-body_ response).to-byte-array
    expect-equals 2 decoded.size
    expect-equals "MyNetwork" decoded[0]["ssid"]
    expect-equals -50 decoded[0]["rssi"]

    // Unknown resources return 404.
    response = client.get --host="127.0.0.1" --port=8080 --path="/does-not-exist.txt"
    expect-equals 404 response.status-code
    read-body_ response

    // Submitting credentials via GET trims the SSID, preserves leading and
    // trailing spaces in the WPA2 password, and returns the confirmation page.
    response = client.get --host="127.0.0.1" --port=8080 --path="/?ssid=%20MyNetwork%20&password=%20secret%20"
    expect-equals 200 response.status-code
    confirm-body := read-body_ response
    expect (confirm-body.contains "Connecting to MyNetwork...")
  finally:
    client.close
    server-task.cancel

  expect-not-null submitted
  expect-equals "MyNetwork" submitted["ssid"]
  expect-equals " secret " submitted["password"]

  // Also test submitting credentials via POST application/x-www-form-urlencoded.
  submitted-post/Map? := null
  server-task-post := task::
    submitted-post = setup.run-http network access-points --port=8081

  sleep --ms=500

  client-post := http.Client network
  try:
    headers := http.Headers
    headers.set "Content-Type" "application/x-www-form-urlencoded"
    response := client-post.post "ssid=%20PostNet%20&password=p%2B1%20".to-byte-array
        --host="127.0.0.1"
        --port=8081
        --path="/"
        --headers=headers
    expect-equals 200 response.status-code
    expect ((read-body_ response).contains "Connecting to PostNet...")
  finally:
    client-post.close
    network.close
    server-task-post.cancel

  expect-not-null submitted-post
  expect-equals "PostNet" submitted-post["ssid"]
  expect-equals "p+1 " submitted-post["password"]
