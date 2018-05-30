IF(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
  add_compile_options("/analyze")
ELSEIF(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  add_compile_options("-Wthread-safety")
ENDIF()

SET(CMAKE_EXPORT_COMPILE_COMMANDS ON)

LIST(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/module)

FIND_PACKAGE(clangtidy)
if(clangtidy_FOUND)
  SET(CMAKE_CXX_CLANG_TIDY "${clangtidy_BINARY}" "-extra-arg-before=-std=c++17" "-checks=*,-fuchsia-default-arguments")
ENDIF()

FIND_PACKAGE(cppcheck)
if(cppcheck_FOUND)
   SET(CMAKE_CXX_CPPCHECK "${cppcheck_BINARY}" "--std=c++14" "--enable=all")
endif()

FIND_PACKAGE(scanbuild)
if(NOT TARGET scan_build AND scanbuild_FOUND)
  ADD_CUSTOM_TARGET(scan_build
    COMMAND ${CMAKE_COMMAND} -DCMAKE_CXX_COMPILER=${cpp_analyzer_BINARY} -DCMAKE_C_COMPILER=${ccc_analyzer_BINARY} ${CMAKE_BINARY_DIR}
    COMMAND ${scanbuild_BINARY} ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR}
    )
endif()

FIND_PACKAGE(pvsstudio)
FIND_PACKAGE(powershell)

if(pvsstudio_FOUND)
  if(NOT WIN32)
    ADD_CUSTOM_TARGET(pvs-studio-analysis ALL
      COMMAND grep '"file":' ${CMAKE_BINARY_DIR}/compile_commands.json | sed -e 's/"file"://' | xargs -I source_file sed -i -e '1i // This is an open source non-commercial project. Dear PVS-Studio, please check it.' -e '1i // PVS-Studio Static Code Analyzer for C, C++ and C\#: http://www.viva64.com' source_file
      COMMAND ${pvs-studio-analyzer_BINARY} analyze -a 31 -o ${CMAKE_BINARY_DIR}/pvs-studio.log -j8 || true
      COMMAND grep '"file":' ${CMAKE_BINARY_DIR}/compile_commands.json | sed -e 's/"file"://' | xargs -I source_file sed -i -e '/.* This is an open source non-commercial project. Dear PVS-Studio, please check it./d' -e '/.* PVS-Studio Static Code Analyzer for C, C++.*/d' source_file
      COMMAND ${plog-converter_BINARY} -t tasklist -a 'GA:1,2,3;64:1,2,3;OP:1,2,3;CS:1,2,3' -o ${CMAKE_BINARY_DIR}/pvs-studio-report.txt ${CMAKE_BINARY_DIR}/pvs-studio.log
      DEPENDS ${CMAKE_BINARY_DIR}/compile_commands.json
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      )
  elseif(powershell_FOUND)
    ADD_CUSTOM_TARGET(pvs-studio-analysis ALL
      COMMAND ${powershell_BINARY} grep 'ClCompile Include' --include='*.vcxproj.filters' -r ${CMAKE_BINARY_DIR} | sed -e 's/.*ClCompile Include="/"/' | sed -e 's/">.*/"/' | xargs -I source_file sed -i -e '1i // This is an open source non-commercial project. Dear PVS-Studio, please check it.' -e '1i // PVS-Studio Static Code Analyzer for C, C++ and C\#: http://www.viva64.com' source_file
      COMMAND ${PVS-Studio_Cmd_BINARY} --incremental ScanAndAnalyze --target ${CMAKE_BINARY_DIR}/${CMAKE_PROJECT_NAME}.sln --progress -o ${CMAKE_BINARY_DIR}/pvs-studio.log || true
      COMMAND ${PlogConverter_BINARY} -t FullHtml,Tasks -o ${CMAKE_BINARY_DIR} -n pvs-studio-report ${CMAKE_BINARY_DIR}/pvs-studio.log 
      COMMAND ${powershell_BINARY} grep 'ClCompile Include' --include='*.vcxproj.filters' -r ${CMAKE_BINARY_DIR} | sed -e 's/.*ClCompile Include="/"/' | sed -e 's/">.*/"/' | xargs -I source_file sed -i -e '/.* This is an open source non-commercial project. Dear PVS-Studio, please check it./d' -e '/.* PVS-Studio Static Code Analyzer for C, C++.*/d' source_file
      COMMAND ${powershell_BINARY} grep 'ClCompile Include' --include='*.vcxproj.filters' -r ${CMAKE_BINARY_DIR} | sed -e 's/.*ClCompile Include="/"/' | sed -e 's/">.*/"/' | xargs -I source_file unix2dos source_file
      COMMAND ${powershell_BINARY} rm ${CMAKE_BINARY_DIR}/pvs-studio.log
      DEPENDS ${CMAKE_BINARY_DIR}/${CMAKE_PROJECT_NAME}.sln
      WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
      )
  endif()
endif()
