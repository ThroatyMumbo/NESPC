// TinyUSB host for a USB keyboard, mouse and MIDI keyboard; CFG_TUSB_MCU, CFG_TUSB_OS and RP2040_USB_HOST_MODE come from the SDK's cmake.
#ifndef _TUSB_CONFIG_H_
#define _TUSB_CONFIG_H_

#ifndef CFG_TUSB_MCU
#error "CFG_TUSB_MCU must come from the tinyusb_host cmake target"
#endif

#define CFG_TUH_ENABLED             1
#define CFG_TUD_ENABLED             0
#define CFG_TUH_MAX_SPEED           OPT_MODE_FULL_SPEED
#define BOARD_TUH_RHPORT            0

#define CFG_TUH_MEM_SECTION
#define CFG_TUH_MEM_ALIGN           __attribute__ ((aligned(4)))

#define CFG_TUH_HUB                 2   // an external hub plus the one inside some keyboards
#define CFG_TUH_DEVICE_MAX          8
#define CFG_TUH_ENUMERATION_BUFSIZE 512 // audio-class configs of MIDI keyboards run past 256
#define CFG_TUH_HID                 8   // keyboard and mouse, each with its media/vendor interfaces, behind a hub
#define CFG_TUH_HID_EPIN_BUFSIZE    64
#define CFG_TUH_HID_EPOUT_BUFSIZE   64
#define CFG_TUH_MIDI                2
#define CFG_TUH_CDC                 0
#define CFG_TUH_MSC                 0
#define CFG_TUH_VENDOR              0

#endif
