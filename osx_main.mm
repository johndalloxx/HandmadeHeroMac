#include <AppKit/AppKit.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#include <IOKit/IOReturn.h>
#include <IOKit/IOTypes.h>
#include <IOKit/hid/IOHIDBase.h>
#include <IOKit/hid/IOHIDDevice.h>
#include <IOKit/hid/IOHIDElement.h>
#include <IOKit/hid/IOHIDKeys.h>
#import <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hid/IOHIDValue.h>
#include <cstdint>
#include <cstdio>

#define internal static
#define local_persist static
#define global_variable static

global_variable float globalRenderWidth = 1024;
global_variable float globalRenderHeight = 768;
global_variable bool running = true;
global_variable uint8_t *buffer;

global_variable int bitmapHeight;
global_variable int bitmapWidth;
global_variable int bytesPerPixel = 4;
global_variable int pitch;
global_variable int offsetX;
global_variable int offsetY;

typedef int32_t bool32;
typedef float real32;
typedef double real64;

void macOSRefreshBuffer(NSWindow *window) {
  if (buffer) {
    free(buffer);
  }

  bitmapWidth = window.contentView.bounds.size.width;
  bitmapHeight = window.contentView.bounds.size.height;
  pitch = bitmapWidth * bytesPerPixel;
  buffer = (uint8_t *)malloc(pitch * bitmapHeight);
}

void renderWeirdGradient() {
  int width = bitmapWidth;
  int height = bitmapHeight;

  uint8_t *row = (uint8_t *)buffer;

  for (int y = 0; y < height; y++) {

    uint8_t *pixelChannel = (uint8_t *)row;

    for (int x = 0; x < width; x++) {
      // Red
      *pixelChannel = 0;
      ++pixelChannel;

      // Green
      *pixelChannel = (uint8_t)y + (uint8_t)offsetY;
      ++pixelChannel;

      // Blue
      *pixelChannel = (uint8_t)x + (uint8_t)offsetX;
      ++pixelChannel;

      // Alpha
      *pixelChannel = 255;
      ++pixelChannel;
    }

    row += pitch;
  }
}

void macOSRedrawBuffer(NSWindow *window) {

  @autoreleasepool {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:&buffer
                      pixelsWide:bitmapWidth
                      pixelsHigh:bitmapHeight
                   bitsPerSample:8
                 samplesPerPixel:bytesPerPixel
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                     bytesPerRow:pitch
                    bitsPerPixel:32] autorelease];

    NSSize imageSize = NSMakeSize(bitmapWidth, bitmapHeight);
    NSImage *image = [[[NSImage alloc] initWithSize:imageSize] autorelease];
    [image addRepresentation:rep];
    window.contentView.layer.contents = image;
  };
}

@interface HandmadeWindowDelegate : NSObject <NSWindowDelegate>
;
@end

@implementation HandmadeWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
  running = false;
}
- (void)windowDidResize:(NSNotification *)notification {
  NSWindow *window = (NSWindow *)notification.object;
  macOSRefreshBuffer(window);
  renderWeirdGradient();
  macOSRedrawBuffer(window);
}

@end

struct mac_game_controller {
  uint32_t LeftSymbolButtonUsageID;
  uint32_t DownSymbolButtonUsageID;
  uint32_t RightSymbolButtonUsageID;
  uint32_t UpSymbolButtonUsageID;
  uint32 LeftShoulderButtonUsageID;
  uint32 RightShoulderButtonUsageID;

  uint32 LeftThumbXUsageID;
  uint32 LeftThumbYUsageID;

  bool32 LeftSymbolButtonState;
  bool32 DownSymbolButtonState;
  bool32 RightSymbolButtonState;
  bool32 UpSymbolButtonState;

  real32 LeftThumbstickX;
  real32 LeftThumbstickY;

  uint32_t DPadX;
  uint32_t DPadY;
};

internal void ControllerInput(void *context, IOReturn result, void *sender,
                              IOHIDValueRef value) {
  if (result != kIOReturnSuccess) {
    return;
  }

  mac_game_controller *MacGameController = (mac_game_controller *)context;

  IOHIDElementRef Element = IOHIDValueGetElement(value);
  uint32_t UsagePage = IOHIDElementGetUsagePage(Element);
  uint32_t Usage = IOHIDElementGetUsage(Element);

  // buttons
  if (UsagePage == kHIDPage_Button) {
    BOOL ButtonState = (BOOL)IOHIDValueGetIntegerValue(value);

    if (Usage == MacGameController->LeftSymbolButtonUsageID) {
      MacGameController->LeftSymbolButtonState = ButtonState;
    } else if (Usage == MacGameController->DownSymbolButtonUsageID) {
      MacGameController->DownSymbolButtonState = ButtonState;
    } else if (Usage == MacGameController->UpSymbolButtonUsageID) {
      MacGameController->UpSymbolButtonState = ButtonState;
    } else if (Usage == MacGameController->RightSymbolButtonUsageID) {
      MacGameController->RightSymbolButtonState = ButtonState;
    }
  }

  else if (UsagePage == kHIDPage_GenericDesktop) {
    NSLog(@"Generic Desktop Usage: 0x%X", Usage);
    double_t Analog =
        IOHIDValueGetScaledValue(value, kIOHIDValueScaleTypeCalibrated);

    // NOTE: (ted)  It seems like slamming the stick left gives me a value of
    // zero
    //              and slamming it all the way right gives a value of 255.
    //
    //              I would gather this is being mapped to an eight bit unsigned
    //              integer

    //              Max Y up is zero. Max Y down is 255. Not moving Y is 128.
    if (Usage == MacGameController->LeftThumbXUsageID) {
      MacGameController->LeftThumbstickX = (real32)Analog;
    }

    if (Usage == MacGameController->LeftThumbYUsageID) {
      MacGameController->LeftThumbstickY = (real32)Analog;
    }

    if (Usage == kHIDUsage_GD_Hatswitch) {
      int DPadState = (int)IOHIDValueGetIntegerValue(value);
      int32_t DPadX = 0;
      int32_t DPadY = 0;

      switch (DPadState) {
      case 0:
        DPadX = 0;
        DPadY = 1;
        break;
      case 1:
        DPadX = 1;
        DPadY = 1;
        break;
      case 2:
        DPadX = 1;
        DPadY = 0;
        break;
      case 3:
        DPadX = 1;
        DPadY = -1;
        break;
      case 4:
        DPadX = 0;
        DPadY = -1;
        break;
      case 5:
        DPadX = -1;
        DPadY = -1;
        break;
      case 6:
        DPadX = -1;
        DPadY = 0;
        break;
      case 7:
        DPadX = -1;
        DPadY = 1;
        break;
      default:
        DPadX = 0;
        DPadY = 0;
        break;
      }

      MacGameController->DPadX = DPadX;
      MacGameController->DPadY = DPadY;
    }
  }
}

internal void ControllerConnected(void *context, IOReturn result, void *sender,
                                  IOHIDDeviceRef device) {
  if (result != kIOReturnSuccess) {
    return;
  }

  NSUInteger vendorID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(
      device, CFSTR(kIOHIDVendorIDKey)) unsignedIntegerValue];
  NSUInteger productID = [(__bridge NSNumber *)IOHIDDeviceGetProperty(
      device, CFSTR(kIOHIDProductIDKey)) unsignedIntegerValue];

  NSLog(@"Vendor ID: %lu", vendorID);
  NSLog(@"Product ID: %lu", productID);

  mac_game_controller *MacGameController = (mac_game_controller *)context;

  if (vendorID == 0x054c && productID == 0x09cc) {
    NSLog(@"Playstation Controller Connected");

    MacGameController->LeftSymbolButtonUsageID = 0x01;
    MacGameController->DownSymbolButtonUsageID = 0x02;
    MacGameController->RightSymbolButtonUsageID = 0x03;
    MacGameController->UpSymbolButtonUsageID = 0x04;

    MacGameController->LeftThumbXUsageID = kHIDUsage_GD_X;
    MacGameController->LeftThumbYUsageID = kHIDUsage_GD_Y;
  }

  MacGameController->LeftThumbstickX = 128.0f;
  MacGameController->LeftThumbstickY = 128.0f;

  IOHIDDeviceRegisterInputValueCallback(device, ControllerInput,
                                        (void *)MacGameController);

  IOHIDDeviceSetInputValueMatchingMultiple(device, (__bridge CFArrayRef) @[
    @{@(kIOHIDElementUsagePageKey) : @(kHIDPage_GenericDesktop)},
    @{@(kIOHIDElementUsagePageKey) : @(kHIDPage_Button)},
  ]);
}

internal void MacSetupGameController(mac_game_controller *MacGameController) {
  IOHIDManagerRef HIDManager = IOHIDManagerCreate(kCFAllocatorDefault, 0);

  // TODO: Handle error better
  if (IOHIDManagerOpen(HIDManager, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
    NSLog(@"Error Initializing HandMade Controller");
    return;
  }

  IOHIDManagerRegisterDeviceMatchingCallback(HIDManager, ControllerConnected,
                                             (void *)MacGameController);

  IOHIDManagerSetDeviceMatchingMultiple(HIDManager, (__bridge CFArrayRef) @[
    @{
      @kIOHIDDeviceUsagePageKey : @(kHIDPage_GenericDesktop),
      @kIOHIDDeviceUsageKey : @(kHIDUsage_GD_GamePad)
    },
    @{
      @kIOHIDDeviceUsagePageKey : @(kHIDPage_GenericDesktop),
      @kIOHIDDeviceUsageKey : @(kHIDUsage_GD_MultiAxisController)
    },
  ]);

  IOHIDManagerScheduleWithRunLoop(HIDManager, CFRunLoopGetCurrent(),
                                  kCFRunLoopDefaultMode);
};

int main(int argc, const char *argv[]) {
  HandmadeWindowDelegate *windowDelegate =
      [[HandmadeWindowDelegate alloc] init];

  NSRect screenRect = [[NSScreen mainScreen] frame];
  NSRect windowRect =
      NSMakeRect((screenRect.size.width - globalRenderWidth) * 0.5,
                 (screenRect.size.height - globalRenderHeight) * 0.5,
                 globalRenderWidth, globalRenderHeight);

  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:windowRect
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable |
                          NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered
                    defer:NO];

  [window setBackgroundColor:NSColor.blackColor];
  [window setTitle:@"Handmade Hero"];
  [window makeKeyAndOrderFront:nil];
  [window setDelegate:windowDelegate];
  window.contentView.wantsLayer = YES;

  macOSRefreshBuffer(window);
  offsetX = 0;
  offsetY = 0;

  // Todo: Setup Playstation Controller USB Handling
  mac_game_controller MacGameController = {};
  MacSetupGameController(&MacGameController);

  while (running) {
    renderWeirdGradient();

    macOSRedrawBuffer(window);

    if (MacGameController.LeftSymbolButtonState) {
      offsetX--;
    } else if (MacGameController.RightSymbolButtonState) {
      offsetX++;
    } else if (MacGameController.UpSymbolButtonState) {
      offsetY--;
    } else if (MacGameController.DownSymbolButtonState) {
      offsetY++;
    }
    if (MacGameController.DPadX == 1) {
      offsetX++;
    } else if (MacGameController.DPadX == -1) {
      offsetX--;
    }
    if (MacGameController.DPadY == 1) {
      offsetY++;
    } else if (MacGameController.DPadY == -1) {
      offsetY--;
    }

    NSEvent *Event;

    do {
      Event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                 untilDate:nil
                                    inMode:NSDefaultRunLoopMode
                                   dequeue:YES];

      switch ([Event type]) {
      default:
        [NSApp sendEvent:Event];
      }
    } while (Event != nil);
  }

  printf("HandmadeHero Finished Running");
}
