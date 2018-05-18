INCLUDE(${CMAKE_CURRENT_LIST_DIR}/code_coverage.cmake)
INCLUDE(${CMAKE_CURRENT_LIST_DIR}/util.cmake)

ENABLE_TESTING()

if(NOT TARGET check)
  ADD_CUSTOM_TARGET(check ALL COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure -C $<CONFIGURATION>)
endif()

LIST(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/module)

FIND_PACKAGE(valgrind)
FIND_PACKAGE(ubsan)
FIND_PACKAGE(asan)
FIND_PACKAGE(tsan)
FIND_PACKAGE(cudamemcheck)
FIND_PACKAGE(drmemory)

if(valgrind_FOUND)
  FILE(GLOB suppression_files ${CMAKE_CURRENT_LIST_DIR}/valgrind_supp/*.supp)
endif()

macro(add_valgrind_suppression_dir dir)
  FILE(GLOB tmp_suppression_files ${dir}/*.supp)
  FOREACH(file ${tmp_suppression_files})
    LIST(APPEND suppression_files "${file}")
  endforeach()
endmacro()

function(add_test_with_runtime_analysis)
  set(cpu_analysis_tools MEMCHECK UBSAN HELGRIND ASAN TSAN DRMEMORY)
  set(gpu_analysis_tools CUDA-MEMCHECK CUDA-SYNCCHECK CUDA-INITCHECK CUDA-RACECHECK)
  set(oneValueArgs TARGET WITH_CPU_ANALYSIS WITH_GPU_ANALYSIS ${cpu_analysis_tools} ${gpu_analysis_tools})
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

  if("${this_WITH_GPU_ANALYSIS}" STREQUAL "")
    set(this_WITH_GPU_ANALYSIS TRUE)
  endif()

  #set default values for runtime analysis
  if(NOT this_WITH_CPU_ANALYSIS)
    foreach(tool IN LISTS cpu_analysis_tools)
      set(this_${tool} FALSE)
    endforeach()
  endif()

  if(NOT this_WITH_GPU_ANALYSIS)
    foreach(tool IN LISTS gpu_analysis_tools)
      set(this_${tool} FALSE)
    endforeach()
  endif()

  if("${this_MEMCHECK}" STREQUAL "")
    set(this_MEMCHECK ${valgrind_FOUND})
  elseif(${this_MEMCHECK} AND NOT valgrind_FOUND)
    message(WARNING "no valgrind")
    set(this_MEMCHECK FALSE)
  endif()

  if("${this_DRMEMORY}" STREQUAL "")
    set(this_DRMEMORY ${drmemory_FOUND})
  elseif(${this_DRMEMORY} AND NOT drmemory_FOUND)
    message(WARNING "no drmemory")
    set(this_DRMEMORY FALSE)
  endif()

  if("${this_TSAN}" STREQUAL "")
    set(this_TSAN FALSE)
  elseif(${this_TSAN} AND NOT tsan_FOUND)
    message(WARNING "no tsan")
    set(this_TSAN FALSE)
  endif()

  if("${this_HELGRIND}" STREQUAL "")
    set(this_HELGRIND FALSE)
  elseif(${this_HELGRIND} AND NOT valgrind_FOUND)
    message(WARNING "no valgrind")
    set(this_HELGRIND FALSE)
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

  if("${this_CUDA-MEMCHECK}" STREQUAL "")
    set(this_CUDA-MEMCHECK FALSE)
  elseif(${this_CUDA-MEMCHECK} AND NOT cudamemcheck_FOUND)
    message(WARNING "no cuda-memcheck")
    set(this_CUDA-MEMCHECK FALSE)
  endif()

  if("${this_CUDA-SYNCCHECK}" STREQUAL "")
    set(this_CUDA-SYNCCHECK FALSE)
  elseif(${this_CUDA-SYNCCHECK} AND NOT cudamemcheck_FOUND)
    message(WARNING "no cuda-memcheck")
    set(this_CUDA-SYNCCHECK FALSE)
  endif()

  if("${this_CUDA-INITCHECK}" STREQUAL "")
    set(this_CUDA-INITCHECK FALSE)
  elseif(${this_CUDA-INITCHECK} AND NOT cudamemcheck_FOUND)
    message(WARNING "no cuda-memcheck")
    set(this_CUDA-INITCHECK FALSE)
  endif()

  if("${this_CUDA-RACECHECK}" STREQUAL "")
    set(this_CUDA-RACECHECK FALSE)
  elseif(${this_CUDA-RACECHECK} AND NOT cudamemcheck_FOUND)
    message(WARNING "no cuda-memcheck")
    set(this_CUDA-RACECHECK FALSE)
  endif()

  set(has_test FALSE)
  foreach(tool IN LISTS cpu_analysis_tools gpu_analysis_tools)
    if(NOT ${this_${tool}})
      continue()
    endif()

    set(new_target "${tool}_${this_TARGET}")
    clone_target(OLD_TARGET ${this_TARGET} NEW_TARGET ${new_target})
    set(new_target_command $<TARGET_FILE:${new_target}>)
    set(has_test TRUE)

    if(tool STREQUAL ASAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=address")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=address")
    elseif(tool STREQUAL UBSAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=undefined")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=undefined")
    elseif(tool STREQUAL TSAN)
      target_compile_options(${new_target} PRIVATE "-fsanitize=thread")
      set_target_properties(${new_target} PROPERTIES LINK_FLAGS "-fsanitize=thread")
    elseif(tool STREQUAL DRMEMORY)
      set(drmemory_command ${drmemory_BINARY} -logdir ${CMAKE_BINARY_DIR} -ignore_kernel --)
      set(new_target_command "${drmemory_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL MEMCHECK)
      set(memcheck_command "${valgrind_BINARY} --error-exitcode=1 --trace-children=yes --gen-suppressions=all --track-fds=yes --leak-check=full")
      foreach(suppression_file ${suppression_files})
	set(memcheck_command "${memcheck_command} --suppressions=${suppression_file}")
      endforeach()
      separate_arguments(memcheck_command)
      set(new_target_command "${memcheck_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL HELGRIND)
      set(helgrind_command "${valgrind_BINARY} --tool=helgrind --error-exitcode=1 --trace-children=yes --gen-suppressions=all")
      foreach(suppression_file ${suppression_files})
	set(helgrind_command "${helgrind_command} --suppressions=${suppression_file}")
      endforeach()
      separate_arguments(helgrind_command)
      set(new_target_command "${helgrind_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL CUDA-MEMCHECK)
      set(memcheck_command ${cudamemcheck_BINARY} --tool memcheck --leak-check full --error-exitcode 1 --flush-to-disk yes)
      set(new_target_command "${memcheck_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL CUDA-SYNCCHECK)
      set(synccheck_command ${cudamemcheck_BINARY} --tool synccheck --leak-check full --error-exitcode 1 --flush-to-disk yes)
      set(new_target_command "${synccheck_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL CUDA-INITCHECK)
      set(initcheck_command ${cudamemcheck_BINARY} --tool initcheck --leak-check full --error-exitcode 1 --flush-to-disk yes)
      set(new_target_command "${initcheck_command};$<TARGET_FILE:${new_target}>")
    elseif(tool STREQUAL CUDA-RACECHECK)
      set(racecheck_command ${cudamemcheck_BINARY} --tool racecheck --leak-check full --error-exitcode 1 --flush-to-disk yes)
      set(new_target_command "${racecheck_command};$<TARGET_FILE:${new_target}>")
    endif()
    add_test(NAME "${new_target}" WORKING_DIRECTORY $<TARGET_FILE_DIR:${new_target}> COMMAND ${new_target_command} ${this_ARGS})
    add_dependencies(check ${new_target})
  endforeach()

  if(NOT has_test)
    set(name ${this_TARGET})
    add_test(NAME ${name} WORKING_DIRECTORY $<TARGET_FILE_DIR:${this_TARGET}> COMMAND $<TARGET_FILE:${this_TARGET}> ${this_ARGS})
  endif()
  add_dependencies(check ${this_TARGET})
endfunction()

if(ENABLE_GNU_CODE_COVERAGE AND NOT TARGET code_coverage)
  FIND_PACKAGE(lcov)
  if(lcov_FOUND)
    ADD_CUSTOM_TARGET(code_coverage ALL
      COMMAND mkdir -p ${CMAKE_BINARY_DIR}/code_coverage
      COMMAND ${lcov_BINARY} --capture --directory ${CMAKE_BINARY_DIR} --output-file coverage.info
      COMMAND ${genhtml_BINARY} coverage.info --output-directory ${CMAKE_BINARY_DIR}/code_coverage
      DEPENDS check)
  endif()
endif()

if(ENABLE_LLVM_CODE_COVERAGE AND NOT TARGET code_coverage)
    ADD_CUSTOM_TARGET(code_coverage ALL
      COMMAND llvm-profdata merge -sparse `find -name default.profraw` -o default.profdata
      COMMAND llvm-cov show -instr-profile=`find -name default.profdata` -format=html -output-dir=${CMAKE_BINARY_DIR}/code_coverage `find ${CMAKE_BINARY_DIR} -name '*.so'` `find ${CMAKE_BINARY_DIR} -executable -type f`
      DEPENDS check)
endif()
