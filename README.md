# Zygote

In biology, the [zygote](https://en.wikipedia.org/wiki/Zygote) is the earliest
developmental stage. This project also represents the first stage of development
for [Toit](https://toitlang.org)-based projects that need to provide WiFi-based
services that can be deployed on production devices and configured by the
end-user.

The source code for this project is governed by a very permissive [license](LICENSE),
so feel free to copy the code and use it for your own purposes.

# Architecture

The functionality of this example is split in two: The [application](src/main.toit)
and the [setup](src/setup.toit). They are independent and installed in separate
containers, because they never actually run at the same time. The idea is that the
application can decide to go into setup mode and it does that by updating state
stored in flash and rebooting. When the setup has completed, the setup does the
reverse transition which reactivates the application with a (potentially) new
configuration.

### Container: Application
The application is a small network-connected service that contacts an NTP
server on the public internet as an example of using the configured WiFi. It can
easily be extended to read measurements from sensors and publishing them through
protocols like MQTT.

### Container: Setup
The setup functionality relies on establishing a WiFi in AP (access point) mode
and running a captive portal that redirects users that connect to the WiFi to
a web page that asks them to update the WiFi credentials.

It uses a simple DNS server to capture users and it runs an HTTP server that
serves a web page with a submittable form that contains the updated SSID and
password. The web page also lists the access points the device can see to make
it easier to pick the right one.

## Customizing the Portal

You can customize the captive portal webpage by providing an `assets` payload
when installing the setup container. The `src/setup.toit` script decodes these
assets and serves them appropriately.

There are three main ways to customize the portal:

1. **CSS Customization**:
   If you only want to restyle the default portal, you can provide a  
   `style.css` file in your assets. The default portal will automatically  
   include `<link rel="stylesheet" href="style.css">`.
   See `assets/style.css` for an example.

2. **HTML Injection**:
   You can provide your own `index.html` (along with any other assets like  
   images or CSS). If `index.html` is present in the assets, it will be served  
   instead of the default portal.
   To display the list of scanned access points, include the  
   `{{access-points}}` tag in your HTML. The server will replace this tag with  
   the generated HTML list of access points.
   See `assets/index.html` for an example.

3. **JS Data Injection**:
   For more dynamic pages, you can fetch the list of access points using  
   JavaScript. The setup server provides a `/access-points.json` endpoint  
   that returns a JSON array containing the `ssid` and `rssi` of each  
   scanned network.
   This allows you to dynamically build the DOM and refresh the list without  
   reloading the entire page (though the actual network scan is only  
   performed when the setup container starts, so reloading or re-fetching  
   simply returns the cached scan results).
   See `assets/dynamic.html` and `assets/app.js` for an example.

### Setting Assets
To inject these assets during development, you can create them with the 
`toit tool assets` command, or simply pass the `--assets` flag to Jaguar.
Assets may also be pre-compressed with `gzip` before adding them (detected
automatically by the `0x1f 0x8b` gzip header and served with
`Content-Encoding: gzip`). Note that `{{access-points}}` template substitution
only runs on uncompressed `index.html`; gzip-compressed `index.html` pages
should fetch `/access-points.json` via JavaScript instead.

However, since the Jaguar command line might not directly pack a folder of
assets, you can create an encoded assets file first:
``` sh
toit tool assets create --assets portal.assets
toit tool assets add --assets portal.assets index.html assets/index.html
toit tool assets add --assets portal.assets style.css assets/style.css
```

Then install the setup container with the encoded assets:
``` sh
jag container install setup src/setup.toit -D jag.disabled -D jag.timeout=2m --assets portal.assets
```

# Development

For development, I recommend using [Jaguar](https://github.com/toitlang/jaguar) and
the Visual Studio code extension for Toit. You can find more information on how to
get started in this [brief guide](https://github.com/toitlang/toit/discussions/244).

Start by installing the packages the example depends on using:

``` sh
jag pkg install
```

As the next step, you will need to flash your device with firmware that contains
the Jaguar service via a serial connection. Doing this will ask you for your WiFi
credentials and you need to make sure that the device and your development host
are on the same network:

``` sh
jag flash
```

You can configure the default WiFi credentials using `jag config wifi set`, so
Jaguar will stop nagging you about this information whenever you flash.

Now that Jaguar runs on your device, you can install the development version of
the setup container that takes care of provisioning the WiFi in case your device
loses connectivity. The setup container will establish a WiFi access point, so
it needs to run with Jaguar disabled in order to not fight over the network. We
provide a timeout to it too, so that any bugs in the code will lead to giving
back control to Jaguar. Using the `jag.timeout` parameter jag will shut down
the container automatically and give control back to `jag`.

You install it like this:

``` sh
jag container install setup src/setup.toit -D jag.disabled -D jag.timeout=2m
```

Now you can start iterating on the main application by installing and
re-installing the application container to test out the new code:

``` sh
jag container install app src/main.toit
```

# Deployment

To flash the deployment firmware onto your device, you first need to build
it. This involves compiling your app and adding it to a firmware envelope
that contains the necessary

``` sh
make firmware
```

Now that you've built the firmware, you can flash it onto your device and
leave the Jaguar service out of it. This will ask you for the default
WiFi credentials again unless you have configured them using `jag config wifi set`.
Upgrade to the deployment image via WiFi:

```
jag firmware update --exclude-jaguar build/firmware.envelope
```

or flash via a serial connection:

```
jag flash --exclude-jaguar build/firmware.envelope
```

# Using Zygote as a package

The setup container and the `mode` helpers can be reused as a
[Toit package](https://docs.toit.io/language/package). Add the
package to your project:

``` sh
toit pkg install github.com/kasperl/toit-zygote
```

Your setup container can then be as small as:

``` toit
import zygote.setup show run-captive-portal-setup

main:
  // Use an empty password to bring up an open access point. The
  // captive portal is the only thing the user needs to reach in order
  // to complete provisioning, and shipping a default password that has
  // to be looked up in the documentation tends to confuse end users.
  run-captive-portal-setup --ssid="my-device" --password=""
```

In your application container, drive the retry loop and hand control
over to the setup container when WiFi keeps failing:

``` toit
import net
import zygote.mode as mode

main:
  if not mode.RUNNING: return

  // Devices that have never been configured (no firmware-baked WiFi
  // credentials and no recorded `wifi-configured` flag) should hand
  // control to the setup container immediately. We rely on the
  // recorded flag rather than waiting for `net.open` to throw,
  // because the SDK's WiFi service can hang indefinitely when no
  // credentials are available instead of returning the
  // "wifi ssid not provided" error to the caller.
  if not mode.has-wifi-configuration:
    mode.run-setup
    return

  retries := 0
  while ++retries < RETRIES:
    network/net.Interface? := null
    exception := catch --trace:
      network = net.open
      mode.mark-wifi-configured
      run network
      retries = 0
    if network: network.close
    if exception and mode.is-missing-wifi-configuration-error exception:
      mode.clear-wifi-configured
      mode.run-setup
    sleep PERIOD

  // Persistently failing means the saved credentials are likely
  // wrong; reboot into setup mode.
  mode.run-setup
```

`mode.run-setup` reboots the device into setup mode, and
`mode.run-application` does the reverse. `mode.has-wifi-configuration`
returns true if either the firmware was built with WiFi credentials
(`wifi.ssid` in the firmware config) or `mode.mark-wifi-configured`
has been called previously.
