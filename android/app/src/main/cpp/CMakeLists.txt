# Uy360 native library: the shared ios/Runner/PanoCore sources + a thin JNI bridge.
#
# OpenCV comes from the prebuilt Android SDK (android/third_party/OpenCV-android-sdk, static
# libraries).  Its OpenCVConfig.cmake defines imported targets (opencv_core, opencv_imgproc, ...)
# whose INTERFACE_LINK_LIBRARIES already pull in the 3rdparty static libs (libjpeg-turbo, tbb,
# kleidicv, tegra_hal, ...), so linking ${OpenCV_LIBS} is enough.
cmake_minimum_required(VERSION 3.22.1)
project(uy360 CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Location of the shared core sources (passed from Gradle; defaults to the repo layout).
if(NOT DEFINED UY360_CORE_DIR)
  get_filename_component(UY360_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../ios/Runner/PanoCore" ABSOLUTE)
endif()
message(STATUS "Uy360 core dir: ${UY360_CORE_DIR}")

# ---- OpenCV (prebuilt Android SDK, static) --------------------------------------------------
# OpenCVConfig.cmake picks its ABI subdirectory from ANDROID_NDK_ABI_NAME (legacy toolchain) —
# make it explicit so the new toolchain file works too, and give it the API level it checks.
set(OpenCV_CONFIG_SUBDIR "/abi-${ANDROID_ABI}")
if(NOT DEFINED ANDROID_NATIVE_API_LEVEL)
  set(ANDROID_NATIVE_API_LEVEL ${ANDROID_PLATFORM_LEVEL})
endif()
if(NOT DEFINED ANDROID_NATIVE_API_LEVEL OR "${ANDROID_NATIVE_API_LEVEL}" STREQUAL "")
  set(ANDROID_NATIVE_API_LEVEL 26)
endif()
set(OpenCV_STATIC ON)
# Modules used by the core: core, imgproc, imgcodecs (JPEG), features (SIFT), stitching
# (GraphCutSeamFinder, MultiBandBlender), photo (inpaint), video (DISOpticalFlow). flann/geometry/dnn are their
# transitive dependencies in OpenCV 5.
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs features stitching photo video flann geometry dnn)
message(STATUS "OpenCV ${OpenCV_VERSION} libs: ${OpenCV_LIBS}")

# ---- sources ----------------------------------------------------------------------------------
file(GLOB UY360_CORE_SOURCES CONFIGURE_DEPENDS "${UY360_CORE_DIR}/*.cpp")
list(FILTER UY360_CORE_SOURCES EXCLUDE REGEX ".*/cli/.*")
message(STATUS "Uy360 core sources: ${UY360_CORE_SOURCES}")

add_library(uy360 SHARED
  ${UY360_CORE_SOURCES}
  uy360_jni.cpp
)
target_include_directories(uy360 PRIVATE "${UY360_CORE_DIR}" ${OpenCV_INCLUDE_DIRS})
target_compile_options(uy360 PRIVATE -O2 -fexceptions -frtti -Wall -Wno-unused-function)
target_compile_definitions(uy360 PRIVATE UY360_ANDROID=1)

find_library(log-lib log)
find_library(jnigraphics-lib jnigraphics)
find_library(android-lib android)
find_library(z-lib z)

target_link_libraries(uy360
  ${OpenCV_LIBS}
  ${log-lib}
  ${jnigraphics-lib}
  ${android-lib}
  ${z-lib}
)

# Android 16 KiB pages, including when linking prebuilt static OpenCV.
target_link_options(uy360 PRIVATE "-Wl,-z,max-page-size=16384")

# Only the opt-in device test build packages the synthetic fixture generator.
if(UY360_DEVICE_TESTS)
  add_library(astra_fixtures SHARED ../../androidTest/cpp/fixture_generator.cpp)
  target_include_directories(astra_fixtures PRIVATE "${UY360_CORE_DIR}" ${OpenCV_INCLUDE_DIRS})
  target_link_libraries(astra_fixtures ${OpenCV_LIBS} ${log-lib} ${z-lib})
  target_compile_options(astra_fixtures PRIVATE -O2)
  target_link_options(astra_fixtures PRIVATE "-Wl,-z,max-page-size=16384")
endif()
