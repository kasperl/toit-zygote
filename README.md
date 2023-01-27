# Zygote

In biology, the [zygote](https://en.wikipedia.org/wiki/Zygote) is the earliest
developmental stage. This project also represents the first stage of development
for [Toit](https://toitlang.org)-based projects that need to provide WiFi-based
services that can be deployed on production devices and configured by the
end-user.

The source code for this project is governed by a very permissive [license](LICENSE),
so feel free to copy the code and use it for your own purposes.

# Development

For development, I recommend using [Jaguar](https://github.com/toitlang/jaguar) and
the Visual Studio code extension for Toit. You can find more information on how to
get started in this [brief guide](https://github.com/toitlang/toit/discussions/244).

To get going, you will need to flash your device with firmware that contains the
Jaguar service via a serial connection. Doing this will ask you for your WiFi credentials
and you need to make sure that the device and your development host are on the
same network:

```
jag flash
```

You can configure the default WiFi credentials using `jag config wifi set`, so
Jaguar will stop nagging you about this information whenever you flash.

Now that Jaguar runs on your device, you can run the development version of the main
application like this:

``` sh
jag run src/main.toit
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
