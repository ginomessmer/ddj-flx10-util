#include "flx10_usb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

#define USB_CLASS_HUB 9

typedef IOReturn (*flx10_device_fn)(IOUSBDeviceInterface **dev, void *ctx);

static CFMutableDictionaryRef make_matching(uint16_t vendorID, uint16_t productID) {
    CFMutableDictionaryRef matching = IOServiceMatching(kIOUSBDeviceClassName);
    if (!matching) return NULL;
    SInt32 vid = vendorID, pid = productID;
    CFNumberRef vidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &vid);
    CFNumberRef pidRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pid);
    CFDictionarySetValue(matching, CFSTR(kUSBVendorID), vidRef);
    CFDictionarySetValue(matching, CFSTR(kUSBProductID), pidRef);
    CFRelease(vidRef);
    CFRelease(pidRef);
    return matching;
}

/// Calls `fn` for each matching non-hub device. Stops at the first error, or after the first
/// device when `firstOnly` is set. Returns kIOReturnNoDevice when no device was visited.
static IOReturn for_each_device(uint16_t vendorID, uint16_t productID, int firstOnly,
                                flx10_device_fn fn, void *ctx, int *visited) {
    *visited = 0;
    CFMutableDictionaryRef matching = make_matching(vendorID, productID);
    if (!matching) return kIOReturnNoMemory;

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (kr != KERN_SUCCESS) return kr;

    IOReturn result = kIOReturnNoDevice;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                               kIOCFPlugInInterfaceID, &plugin, &score);
        IOObjectRelease(service);
        if (kr != KERN_SUCCESS || !plugin) continue;

        IOUSBDeviceInterface **dev = NULL;
        HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
                                               (LPVOID *)&dev);
        (*plugin)->Release(plugin);
        if (hr != S_OK || !dev) continue;

        UInt8 deviceClass = 0;
        if ((*dev)->GetDeviceClass(dev, &deviceClass) != kIOReturnSuccess || deviceClass == USB_CLASS_HUB) {
            (*dev)->Release(dev);
            continue;
        }

        (*visited)++;
        result = fn ? fn(dev, ctx) : kIOReturnSuccess;
        (*dev)->Release(dev);
        if (result != kIOReturnSuccess || firstOnly) break;
    }
    IOObjectRelease(iterator);
    return result;
}

int flx10_usb_device_count(uint16_t vendorID, uint16_t productID) {
    int visited = 0;
    for_each_device(vendorID, productID, 0, NULL, NULL, &visited);
    return visited;
}

typedef struct {
    IOUSBDevRequest request;
} request_ctx;

static IOReturn send_request(IOUSBDeviceInterface **dev, void *ctx) {
    request_ctx *rc = ctx;
    IOReturn openResult = (*dev)->USBDeviceOpen(dev);
    if (openResult != kIOReturnSuccess && openResult != kIOReturnExclusiveAccess) {
        return openResult;
    }
    rc->request.wLenDone = 0;
    IOReturn result = (*dev)->DeviceRequest(dev, &rc->request);
    if (openResult == kIOReturnSuccess) {
        (*dev)->USBDeviceClose(dev);
    }
    return result;
}

IOReturn flx10_usb_control_request(uint16_t vendorID, uint16_t productID, uint8_t bmRequestType,
                                   uint8_t bRequest, uint16_t wValue, uint16_t wIndex, void *data,
                                   uint16_t wLength, uint32_t *transferred) {
    request_ctx ctx = {
        .request = {
            .bmRequestType = bmRequestType,
            .bRequest = bRequest,
            .wValue = wValue,
            .wIndex = wIndex,
            .wLength = wLength,
            .pData = data,
            .wLenDone = 0,
        },
    };
    int visited = 0;
    int isIn = (bmRequestType & 0x80) != 0;
    IOReturn result = for_each_device(vendorID, productID, isIn, send_request, &ctx, &visited);
    if (transferred) *transferred = ctx.request.wLenDone;
    return result;
}
