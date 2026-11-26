# Microsoft Store satın alma köprüsü. C++/WinRT istisnalarla çalıştığı için
# Flutter'ın standart ayarlarından (_HAS_EXCEPTIONS=0) ayrı derlenir.
cmake_minimum_required(VERSION 3.14)
add_library(netice_msstore STATIC "ms_store.cpp")
# C++/WinRT, C++17'de kaldırılan deneysel eşyordamları kullanır; C++20 gerekir.
target_compile_features(netice_msstore PRIVATE cxx_std_20)
target_compile_options(netice_msstore PRIVATE /EHsc /permissive- /bigobj /utf-8)
target_compile_definitions(netice_msstore PRIVATE "NOMINMAX" "WIN32_LEAN_AND_MEAN")
target_include_directories(netice_msstore PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(netice_msstore PUBLIC "windowsapp.lib" "ole32.lib")
