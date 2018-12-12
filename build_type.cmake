include_guard(GLOBAL)
cmake_policy(VERSION 3.11)
get_property(isMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(NOT isMultiConfig) 
  if(NOT CMAKE_BUILD_TYPE) 
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "" FORCE)
  endif()
endif()

function(add_custom_build_type build_type)
  if(isMultiConfig) 
    if(NOT ${build_type} IN_LIST CMAKE_CONFIGURATION_TYPES) 
      list(APPEND CMAKE_CONFIGURATION_TYPES ${build_type})
    endif() 
  endif()
endfunction()
