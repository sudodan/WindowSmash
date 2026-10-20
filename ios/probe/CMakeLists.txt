cmake_minimum_required(VERSION 3.24)
project(WindowSmashProbe LANGUAGES C OBJC ASM)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Configure with -DCMAKE_SYSTEM_NAME=iOS on a Mac with Xcode.")
endif()
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(FIXTURE_DIR "${CMAKE_CURRENT_BINARY_DIR}/fixtures")
add_custom_command(
  OUTPUT "${FIXTURE_DIR}/fixtures.c" "${FIXTURE_DIR}/native_fixtures.S"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/generate_fixtures.py" "${FIXTURE_DIR}"
  DEPENDS generate_fixtures.py ../../tools/lift.py ../../tools/lift_simd.py ../../tools/a64.py
  VERBATIM)
add_executable(WindowSmashProbe MACOSX_BUNDLE main.m vm_probe.c ../../runtime/platform/vm_posix.c cpu_probe.c recompiled_probe.c metal_probe.m
  "${FIXTURE_DIR}/fixtures.c" "${FIXTURE_DIR}/native_fixtures.S")
target_compile_definitions(WindowSmashProbe PRIVATE WS_NATIVE_REFERENCE)
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
