#ifndef FLX10_USB_H
#define FLX10_USB_H

#include <stdint.h>
#include <IOKit/IOReturn.h>

/// Number of attached USB devices matching vendor/product that are not hubs (bDeviceClass != 9).
int flx10_usb_device_count(uint16_t vendorID, uint16_t productID);

/// Issue a vendor control request on the default pipe of every matching device.
///
/// Mirrors the original DDJ-FLX10Setup.framework: the device is opened with USBDeviceOpen, but an
/// exclusive-access failure (another client such as the audio driver holds it) is tolerated and
/// the request is still sent. Returns kIOReturnSuccess only if every device accepted the request,
/// kIOReturnNoDevice when nothing matched.
///
/// For IN requests (bmRequestType & 0x80) only the first matching device is queried and
/// `data`/`transferred` receive the response.
IOReturn flx10_usb_control_request(uint16_t vendorID,
                                   uint16_t productID,
                                   uint8_t bmRequestType,
                                   uint8_t bRequest,
                                   uint16_t wValue,
                                   uint16_t wIndex,
                                   void *data,
                                   uint16_t wLength,
                                   uint32_t *transferred);

#endif
