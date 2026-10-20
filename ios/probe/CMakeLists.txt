cmake_minimum_required(VERSION 3.24)
project(WindowSmashProbe LANGUAGES C OBJC)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Configure with -DCMAKE_SYSTEM_NAME=iOS on a Mac with Xcode.")
endif()
add_executable(WindowSmashProbe MACOSX_BUNDLE main.m cpu_probe.c)
target_include_directories(WindowSmashProbe PRIVATE ../../runtime)
target_compile_options(WindowSmashProbe PRIVATE -fno-fast-math -ffp-contract=off "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
target_link_libraries(WindowSmashProbe PRIVATE "-framework UIKit" "-framework Metal")
set_target_properties(WindowSmashProbe PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "org.windowsmash.feasibility"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic")
option(WS_EXTENDED_ADDRESSING "Request Extended Virtual Addressing; requires a matching signing profile" OFF)
if(WS_EXTENDED_ADDRESSING)
  set_target_properties(WindowSmashProbe PROPERTIES XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS "${CMAKE_CURRENT_SOURCE_DIR}/Extended.entitlements")
endif()
