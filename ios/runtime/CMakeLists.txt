cmake_minimum_required(VERSION 3.24)
project(WindowSmashRuntime LANGUAGES C CXX OBJC ASM)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Use -DCMAKE_SYSTEM_NAME=iOS with the iPhone SDK")
endif()
set(RT "${CMAKE_CURRENT_SOURCE_DIR}/../../runtime")
add_library(RuntimeCore STATIC
  ${RT}/linux/win32.c ${RT}/linux/eh.cpp
  ${RT}/macos/memory.c ${RT}/macos/platform.c
  ${RT}/macos/fiber.c ${RT}/macos/fiber_arm64.S)
target_include_directories(RuntimeCore PUBLIC ${RT}/macos/include ${RT}/linux/include ${RT})
target_compile_options(RuntimeCore PRIVATE -fno-strict-aliasing -ffp-contract=off)
set_target_properties(RuntimeCore PROPERTIES CXX_STANDARD 20)
add_library(EmbeddedGuest STATIC ${RT}/host.c ${RT}/kernel.c)
target_compile_definitions(EmbeddedGuest PUBLIC WS_EMBEDDED_HOST)
target_link_libraries(EmbeddedGuest PUBLIC RuntimeCore)
target_compile_options(EmbeddedGuest PRIVATE -fno-strict-aliasing -ffp-contract=off)
# Graphics compile gate; graphics are not linked into the synthetic guest app.
add_library(AppleCompileAudit OBJECT ${RT}/gpu_shader.c ${RT}/macos/gpu_metal.m)
target_include_directories(AppleCompileAudit PRIVATE ${RT}/macos/include ${RT}/linux/include ${RT})
target_compile_options(AppleCompileAudit PRIVATE -fno-strict-aliasing -ffp-contract=off
  -Werror=unguarded-availability-new "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
add_executable(WindowSmashRuntime MACOSX_BUNDLE main.m core_test.c exception_test.cpp boot_test.c boot_services.c ${RT}/ios/window.m)
target_include_directories(WindowSmashRuntime PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(WindowSmashRuntime PRIVATE EmbeddedGuest "-framework UIKit" "-framework Metal" "-framework QuartzCore")
target_compile_options(WindowSmashRuntime PRIVATE -fno-strict-aliasing -ffp-contract=off "$<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>")
set_target_properties(WindowSmashRuntime PROPERTIES CXX_STANDARD 20
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "org.windowsmash.runtime-test"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1"
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE "Automatic")
add_dependencies(WindowSmashRuntime AppleCompileAudit)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(BOOT_IMAGES "${CMAKE_CURRENT_BINARY_DIR}/boot-fixtures")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/generate_boot_images.py" "${BOOT_IMAGES}"
  COMMAND_ERROR_IS_FATAL ANY)
foreach(MODULE main subsdk0 sdk)
  set(IMAGE "${BOOT_IMAGES}/${MODULE}.reloc.bin")
  target_sources(WindowSmashRuntime PRIVATE "${IMAGE}")
  set_source_files_properties("${IMAGE}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/boot-fixtures")
endforeach()
