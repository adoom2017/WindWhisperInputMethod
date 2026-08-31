cmake_minimum_required(VERSION 3.16)
project(WindWhisper LANGUAGES CXX)

enable_testing()
add_subdirectory(Core)

if(WIN32)
  add_subdirectory(Platform/Windows)
endif()
