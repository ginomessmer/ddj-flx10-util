# FLX10 Utility

A single native macOS app (SwiftUI, universal binary, macOS 14+) that replaces both
**DDJ-FLX10 Setup.app** (controller utility settings) and **DDJ-FLX10_ImageTransferTool.app**
(DJ logo upload) for the Pioneer DJ / AlphaTheta DDJ-FLX10. It needs neither the
`DDJ-FLX10Setup.framework` nor the `AutoLauncherd` launch agent.

```bash
./scripts/build-app.sh
```

```bash
open "build/FLX10 Utility.app"
```

For development, use `swift run FLX10Utility` and `swift test`, or generate an Xcode project with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (the `.xcodeproj` is generated, not committed):

```bash
xcodegen generate && open FLX10Utility.xcodeproj
```

Debug builds can render every pane to PNGs without screen-recording permission, which is
useful for checking layout changes:

```bash
FLX10_SNAPSHOT_DIR=/tmp/flx10-shots swift run FLX10Utility
```

## Layout

| Path | Purpose |
| --- | --- |
| `Sources/CFLX10USB` | C shim for vendor control requests through `IOUSBDeviceInterface` |
| `Sources/FLX10Kit` | Protocol, transfer state machine, image encoder, settings model, IOKit transports |
| `Sources/FLX10Utility` | SwiftUI app: sidebar window (General, DJ Logo, Jog Display, Performance, Recording), Controller menu, Settings window |
| `scripts/make-icon.swift` | Renders `Resources/AppIcon.icns` |
| `Tests/FLX10KitTests` | Packet framing, state machine, encoder and settings tests |

## Recovered protocol

The protocol was recovered by static analysis of the shipped binaries: ImageTransferTool 1.0.0
(x86_64, JUCE, symbols present), Setup 1.0.0 and DDJ-FLX10Setup.framework (arm64 slices).
None of it has been checked against a live controller yet.

### Device

USB `2B73:0041`. The logo uses the HID interface with top-level usage `0`. Settings go over the
default control pipe of the USB device (bDeviceClass ≠ 9).

### DJ logo (HID)

Every output report is 128 bytes, sent with `IOHIDDeviceSetReport(Output, reportID 0)`.
Responses are 64-byte input reports, and byte 1 holds the response code.

| Step | Host → device | Device → host |
| --- | --- | --- |
| Start transfer | `00 D0 01 len[3]le` | `D8` ×2 (ready) |
| Data | `00 D1 idx[2]le count[2]le` + payload | `DC` received, then `DC` stored (`DD` = failure) |
| Start delete | `00 D0 00` | `D8` ×2 |
| Execute delete | `00 D7` | `DE` ×2 (`DF` = failure) |

* The first data report also carries `len[3]le` after the count and holds 119 payload bytes.
  Every later report holds 122. Indices start at 1.
* The payload is a 240×240 JPEG (quality 1.0). The source image is aspect-fit onto a black
  canvas and must be at most 0x2A400 bytes.
* One 10 s timeout covers the whole operation. A response that arrives while data is still
  streaming fails the transfer.

### Settings (USB control)

`bmRequestType 0x40, bRequest 0x03, wValue = value << 8, wIndex = selector, wLength 0`

| Setting | wIndex | Values (default **bold**) |
| --- | --- | --- |
| Fader Start (sync) | `C013` | 1 = SYNC on, **2 = off** |
| REC OUT | `C01D` | **0 = with mic**, 1 = without mic |
| Time Mode | `C026` | 0 = elapsed, **1 = remaining** |
| Virtual Deck Mode | `C027` | 0 = off, **1 = on** |
| Slip Mode Flashing | `C028` | 0 = disable, **1 = enable** |
| Slip button LED | `C029` | **0 = lit**, 1 = blink |
| Jog Ring Color | `C02B` | **0–2 = MODE 1–3** |

Firmware version: `bmRequestType 0xC0, bRequest 0x00, wIndex 0xC001, wLength 2`, displayed as
`"%x.%.2x"` with `byte[0]`, `byte[1]`.

The controller cannot report these settings back. The original app keeps them in
`~/Library/Preferences/com.pioneerdj.DDJ-FLX10autosetup.plist` and re-sends them when the
controller connects. This app imports that file once, then stores settings in its own defaults.
By default (configurable) it re-sends them when the controller connects.

## Differences from the originals

* **Inferred:** the REC OUT and Virtual Deck labels come from string order and defaults, not from
  traced UI bindings.
* **Not carried over:** Fader Start value `0`, which the original sends only while its checkbox is
  disabled. The meaning of that disabled state is unknown.
* **Changed:** if the quality-1.0 JPEG is over the size limit, this app lowers the quality step by
  step. The original fails instead.
* **Simplified:** the original scales large images down in steps of 0.7 before the final fit.
  This app uses a single high-quality CoreGraphics draw, which looks equivalent.
* **Changed:** the HID manager opens without seizing the device. The original passes option 1
  (seize).
* **Not carried over:** the original's rotation transform (a sin/cos step near the encoder) was
  not fully traced. EXIF orientation is applied instead.

Not affiliated with AlphaTheta Corporation.
