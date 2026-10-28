// Copyright (C) 2023 Kasper Lund.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the LICENSE file.

import log
import monitor

import encoding.url

import net
import net.tcp
import net.udp
import net.wifi

import http
import dns_simple_server as dns

import encoding.json
import system.assets

import .mode as mode

ASSETS ::= assets.decode

DEFAULT-SSID_     ::= "mywifi"
DEFAULT-PASSWORD_ ::= "12345678"

TEMPORARY-REDIRECTS ::= {
  "generate_204": "/",    // Used by Android captive portal detection.
  "gen_204": "/",         // Used by Android captive portal detection.
}

DEFAULT-INDEX ::= """
<html>
  <head>
    <title>WiFi settings</title>
{{css-link}}  </head>
  <body>
    <h1>Update WiFi settings</h1>
    <form method="POST" action="/">
      <label for="ssid">SSID:</label><br>
      <input type="text" id="ssid" name="ssid" autocorrect="off" autocapitalize="none"><br>
      <label for="password">Password:</label><br>
      <input type="text" id="password" name="password" autocorrect="off" autocapitalize="none"><br>
      <br>
      <input type="submit" value="Update">
    </form>
    <p>
    {{access-points}}
  </body>
</html>
"""

DEFAULT-CONNECTING ::= """
<html>
  <head>
    <title>Connecting...</title>
{{css-link}}  </head>
  <body>
    <h1>Connecting to {{ssid}}...</h1>
    <p>The device is now trying to join the network. You can close this page.</p>
  </body>
</html>
"""

MAX-FORM-BODY-BYTES_ ::= 1024

main:
  run-captive-portal-setup

/**
Runs the captive portal WiFi setup.

Creates a WiFi access point with the given $ssid and $password,
  serves a captive portal for WiFi credential configuration, and
  reboots into application mode when done.
*/
run-captive-portal-setup --ssid/string=DEFAULT-SSID_ --password/string=DEFAULT-PASSWORD_:
  // We allow the setup container to start and eagerly terminate
  // if we don't need it yet. This makes it possible to have
  // the setup container installed always, but have it run with
  // the -D jag.disabled flag in development.
  if mode.RUNNING: return

  // Devices that were never configured should stay in setup mode
  // until credentials are entered successfully. Devices that used
  // to have WiFi credentials still time out so the main application
  // can continue its retry loop.
  timeout/Duration? := null
  if mode.has-wifi-configuration:
    // When running in development we run for less time before we
    // back to trying out the app. This makes it faster to correct
    // things and retry, but it does mean that you have less time
    // to connect to the established WiFi.
    timeout = mode.DEVELOPMENT ? (Duration --s=30) : (Duration --m=3)
  catch --unwind=(: it != DEADLINE-EXCEEDED-ERROR): run_ timeout --ssid=ssid --password=password

  // We're done trying to complete the setup. Go back to running
  // the application and let it choose when to re-initiate the
  // setup process.
  mode.run-application

run_ timeout/Duration? --ssid/string --password/string:
  log.info "scanning for wifi access points"
  channels := ByteArray 12: it + 1
  access-points/List := []
  scan-exception := catch:
    access-points = wifi.scan channels
    access-points.sort --in-place: | a b | b.rssi.compare-to a.rssi
  if scan-exception:
    log.warn "wifi access point scan failed; continuing without scan results"

  log.info "establishing wifi in AP mode ($ssid)"
  while true:
    network-ap := wifi.establish
        --ssid=ssid
        --password=password
    credentials/Map? := null
    try:
      if timeout:
        with-timeout timeout: credentials = run-captive-portal_ network-ap access-points
      else:
        credentials = run-captive-portal_ network-ap access-points
    finally:
      // Give the TCP stack and WiFi AP a brief moment to transmit the final
      // HTTP response packets before tearing down the SoftAP interface.
      if credentials: sleep --ms=100
      network-ap.close

    if credentials:
      tags := {"ssid": credentials["ssid"]}
      exception := catch:
        log.info "connecting to wifi in STA mode" --tags=tags
        network-sta/net.Interface? := null
        with-timeout (Duration --s=30):
          network-sta = wifi.open
              --save
              --ssid=credentials["ssid"]
              --password=credentials["password"]
        // The --save flag has now persisted the credentials to SDK
        // storage.  Mark the zygote bucket flag *before* closing the
        // interface so that even if `network-sta.close` throws, the
        // device will still know on next boot that the SDK has
        // credentials worth trying — otherwise the next boot would
        // re-enter setup mode despite valid credentials being saved.
        mode.mark-wifi-configured
        network-sta.close
        log.info "connecting to wifi in STA mode => success" --tags=tags
        return
      log.warn "connecting to wifi in STA mode => failed" --tags=tags

run-captive-portal_ network/net.Interface access-points/List -> Map:
  results := Task.group --required=1 [
    :: run-dns_ network,
    :: run-http network access-points,
  ]
  return results[1]  // Return the result from the HTTP server at index 1.

run-dns_ network/net.Interface -> none:
  device-ip-address := network.address
  socket := network.udp-open --port=53
  hosts := dns.SimpleDnsServer device-ip-address  // Answer the device IP to all queries.

  try:
    while not Task.current.is-canceled:
      datagram/udp.Datagram := socket.receive
      response := hosts.lookup datagram.data
      if not response: continue
      socket.send (udp.Datagram response datagram.address)
  finally:
    socket.close

/**
Runs the captive-portal HTTP server on $network and returns the
  WiFi credentials submitted by the user.

Listens on the given $port (defaults to 80) and serves either the
  bundled $DEFAULT-INDEX or the assets injected via `system.assets`.
  The server keeps running until a successful credential submission
  arrives, at which point the listening socket is closed and the
  submitted credentials are returned.

Exposed primarily so tests and advanced callers can drive the HTTP
  layer without bringing up an actual WiFi access point.
*/
run-http network/net.Interface access-points/List --port/int=80 -> Map:
  socket := network.tcp-listen port
  server := http.Server --max-tasks=4
  result/Map? := null
  try:
    server.listen socket:: | request writer |
      result = handle-http-request_ request writer access-points
      if result: socket.close
  finally:
    if result: return result
    socket.close
  unreachable

escape-html_ text/string -> string:
  text = text.replace --all "&" "&amp;"
  text = text.replace --all "<" "&lt;"
  text = text.replace --all ">" "&gt;"
  return text.replace --all "\"" "&quot;"

extract-credentials_ parameters/Map -> Map?:
  if parameters.is-empty: return null
  ssid := parameters.get "ssid"
  password := parameters.get "password" --if-absent=(: "")
  if ssid is string and password is string:
    trimmed-ssid := ssid.trim
    if trimmed-ssid != "":
      // Do not trim the password: leading/trailing spaces are legal in
      // WPA2 passphrases, and stripping them silently prevents the
      // device from ever associating.
      return { "ssid": trimmed-ssid, "password": password }
  return null

read-post-parameters_ request/http.Request -> Map:
  if request.method != "POST": return {:}
  bytes := #[]
  while chunk := request.body.read:
    if bytes.size + chunk.size > MAX-FORM-BODY-BYTES_: return {:}
    bytes += chunk
  if bytes.is-empty: return {:}
  str := ""
  catch: str = bytes.to-string
  if str == "": return {:}
  return (url.QueryString.parse "?$str").parameters

handle-http-request_ request/http.Request writer/http.ResponseWriter access-points/List -> Map?:
  writer.headers.set "Connection" "close"
  query := url.QueryString.parse request.path
  resource := query.resource
  if resource == "/": resource = "index.html"
  if resource == "/hotspot-detect.html": resource = "index.html"  // Needed for iPhones.
  if resource.starts-with "/": resource = resource[1..]

  TEMPORARY-REDIRECTS.get resource --if-present=:
    writer.headers.set "Location" it
    writer.write-headers 302
    return null

  if resource == "access-points.json":
    writer.headers.set "Content-Type" "application/json"
    writer.write (json.encode (access-points.map: { "ssid": it.ssid, "rssi": it.rssi }))
    return null

  if resource == "index.html":
    credentials := extract-credentials_ query.parameters
    if not credentials and request.method == "POST":
      credentials = extract-credentials_ (read-post-parameters_ request)
    if credentials:
      substitutions := {
        "ssid": escape-html_ credentials["ssid"],
        "css-link": (ASSETS.contains "style.css") ? "<link rel=\"stylesheet\" href=\"style.css\">\n" : "",
      }
      writer.headers.set "Content-Type" "text/html"
      writer.write (DEFAULT-CONNECTING.substitute: substitutions.get it --if-absent=(: "{{$it}}"))
      return credentials

  asset := ASSETS.get resource
  if asset:
    if resource.ends-with ".html":
      writer.headers.set "Content-Type" "text/html"
    else if resource.ends-with ".css":
      writer.headers.set "Content-Type" "text/css"
    else if resource.ends-with ".js":
      writer.headers.set "Content-Type" "application/javascript"
    else:
      writer.headers.set "Content-Type" "application/octet-stream"

    is-gzipped := asset is ByteArray and asset.size >= 2 and asset[0] == 0x1f and asset[1] == 0x8b
    if is-gzipped:
      writer.headers.set "Content-Encoding" "gzip"
      writer.write asset
    else if resource == "index.html":
      substitutions := {
        "access-points": (access-points.map: "$(escape-html_ it.ssid)<br>").join "\n"
      }
      str := asset.to-string
      writer.write (str.substitute: substitutions.get it --if-absent=(: "{{$it}}"))
    else:
      writer.write asset
    return null

  if resource != "index.html":
    writer.headers.set "Content-Type" "text/plain"
    writer.write-headers 404
    writer.write "Not found: $resource"
    return null

  substitutions := {
    "access-points": (access-points.map: "$(escape-html_ it.ssid)<br>").join "\n",
    "css-link": (ASSETS.contains "style.css") ? "<link rel=\"stylesheet\" href=\"style.css\">\n" : "",
  }
  writer.headers.set "Content-Type" "text/html"
  writer.write (DEFAULT-INDEX.substitute: substitutions.get it --if-absent=(: "{{$it}}"))
  return null
