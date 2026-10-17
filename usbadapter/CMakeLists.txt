cmake_minimum_required(VERSION 3.13)

# one image for Tiny 2350 and PGA2350: RP2350A + 4 MB is the subset both boards run, and no board pins are used
set(PICO_BOARD pimoroni_tiny2350 CACHE STRING "Board type")
set(PICO_PLATFORM rp2350 CACHE STRING "Pico platform")
if (NOT PICO_SDK_PATH)
    set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})
endif ()
if (NOT PICO_SDK_PATH)
    message(FATAL_ERROR "set PICO_SDK_PATH to a pico-sdk 2.2.0 checkout")
endif ()

# TinyUSB master efab607 for its MIDI host and RP2 host fixes (SDK 2.2.0 ships 0.18.0), plus patches/: in lib/, clone
# https://github.com/hathach/tinyusb, checkout efab607, git apply ../../patches/tinyusb-rp2-ls-behind-hub.patch
if (NOT PICO_TINYUSB_PATH)
    set(PICO_TINYUSB_PATH ${CMAKE_CURRENT_LIST_DIR}/lib/tinyusb)
endif ()

include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(usbadapter C CXX ASM)
set(CMAKE_C_STANDARD 11)

pico_sdk_init()

add_executable(usbadapter
    src/main.c
    src/keymap.c
    src/link.c
    src/midi.c
    src/mouse.c
    src/port.c
)
pico_generate_pio_header(usbadapter ${CMAKE_CURRENT_LIST_DIR}/src/nespad.pio)
target_include_directories(usbadapter PRIVATE src)
target_link_libraries(usbadapter
    pico_stdlib pico_multicore pico_util hardware_pio tinyusb_host
)

# the USB port is the keyboard's host, so stdio is UART0 (GP0/GP1) through the debugprobe bridge
pico_enable_stdio_usb(usbadapter 0)
pico_enable_stdio_uart(usbadapter 1)

pico_add_extra_outputs(usbadapter)
