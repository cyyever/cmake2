IF(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  message(WARNING "only clang can use libFuzzer")
  return()
endif()

INCLUDE(${CMAKE_CURRENT_LIST_DIR}/util.cmake)
ENABLE_TESTING()

if(NOT TARGET fuzzing)
  ADD_CUSTOM_TARGET(fuzzing ALL COMMAND ${CMAKE_CTEST_COMMAND} --no-compress-output --output-on-failure -C $<CONFIGURATION>)
endif()

LIST(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/module)
FIND_PACKAGE(Threads REQUIRED)
FIND_PACKAGE(ubsan)
FIND_PACKAGE(asan)
FIND_PACKAGE(tsan)
FIND_PACKAGE(msan)

function(add_fuzzing)
  set(oneValueArgs TARGET)
  set(cpu_analysis_tools UBSAN ASAN MSAN)
  set(oneValueArgs TARGET WITH_CPU_ANALYSIS ${cpu_analysis_tools})
  cmake_parse_arguments(this "" "${oneValueArgs}" "ARGS" ${ARGN})
  if("${this_TARGET}" STREQUAL "")
    message(FATAL_ERROR "no target specified")
    return()
  endif()

  if(NOT TARGET ${this_TARGET})
    message(FATAL_ERROR "${this_TARGET} is not a target")
    return()
  endif()

  separate_arguments(this_ARGS)

  if("${this_WITH_CPU_ANALYSIS}" STREQUAL "")
    set(this_WITH_CPU_ANALYSIS TRUE)
  endif()

  #set default values for runtime analysis
  if(NOT this_WITH_CPU_ANALYSIS)
    foreach(tool IN LISTS cpu_analysis_tools)
      set(this_${tool} FALSE)
    endforeach()
  endif()

  if("${this_TSAN}" STREQUAL "")
    set(this_TSAN FALSE)
  elseif(${this_TSAN} AND NOT tsan_FOUND)
    message(WARNING "no tsan")
    set(this_TSAN FALSE)
  endif()

  if("${this_UBSAN}" STREQUAL "")
    set(this_UBSAN ${ubsan_FOUND})
  elseif(${this_UBSAN} AND NOT ubsan_FOUND)
    message(WARNING "no ubsan")
    set(this_UBSAN FALSE)
  endif()

  if("${this_ASAN}" STREQUAL "")
    set(this_ASAN ${asan_FOUND})
  elseif(${this_ASAN} AND NOT asan_FOUND)
    message(WARNING "no asan")
    set(this_ASAN FALSE)
  endif()

  if("${this_MSAN}" STREQUAL "")
    set(this_MSAN FALSE)
  elseif(${this_MSAN} AND NOT msan_FOUND)
    message(WARNING "no msan")
    set(this_MSAN FALSE)
  endif()

  get_target_property(new_env ${this_TARGET} ENVIRONMENT)
  LIST(APPEND new_env ASAN_OPTIONS=protect_shadow_gap=0)

  target_compile_options(${this_TARGET} PRIVATE "-fno-omit-frame-pointer")
  target_compile_options(${this_TARGET} PRIVATE "-fsanitize=fuzzer")
  set_target_properties(${this_TARGET} PROPERTIES LINK_FLAGS "-fsanitize=fuzzer")

  foreach(tool IN LISTS cpu_analysis_tools)
    if(NOT ${this_${tool}})
      continue()
    endif()

    set(new_target "fuzzing_${tool}_${this_TARGET}")
    clone_target(OLD_TARGET ${this_TARGET} NEW_TARGET ${new_target})

    if(tool STREQUAL ASAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=fuzzer,address")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=fuzzer,address")
    elseif(tool STREQUAL MSAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=fuzzer,memory")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=fuzzer,memory")
    elseif(tool STREQUAL UBSAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=fuzzer,undefined")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=fuzzer,undefined")
    elseif(tool STREQUAL TSAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=fuzzer,thread")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=fuzzer,thread")
    endif()

    TARGET_LINK_LIBRARIES(${new_target} PRIVATE Threads::Threads)
    set_target_properties(${new_target} PROPERTIES INTERPROCEDURAL_OPTIMIZATION FALSE)

    if(NOT DEFINED $ENV{MAX_FUZZING_TIME})
      set(ENV{MAX_FUZZING_TIME} 60)
    endif()


    set(name "fuzzing_${new_target}")
    add_test(NAME ${name} WORKING_DIRECTORY $<TARGET_FILE_DIR:${new_target}> COMMAND $<TARGET_FILE:${new_target}> -jobs=4 -max_total_time=$ENV{MAX_FUZZING_TIME})
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "${new_env}")
    add_dependencies(fuzzing ${new_target})
  endforeach()
endfunction()
