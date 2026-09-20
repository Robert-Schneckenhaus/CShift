cmake_minimum_required(VERSION 3.20)
project(CShift LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# LLVM (tested with LLVM 22). Set LLVM_DIR to <llvm>/lib/cmake/llvm if it is not found automatically.
find_package(LLVM REQUIRED CONFIG)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION} (${LLVM_DIR})")

include_directories(${LLVM_INCLUDE_DIRS})
separate_arguments(LLVM_DEFINITIONS_LIST NATIVE_COMMAND ${LLVM_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS_LIST})

add_executable(cshiftc
    compiler/src/main.cpp
    compiler/src/Types.cpp
    compiler/src/Lexer.cpp
    compiler/src/Parser.cpp
    compiler/src/CodeGen.cpp
    compiler/src/CodeGenRuntime.cpp
    compiler/src/CodeGenExpr.cpp
    compiler/src/CodeGenCall.cpp
    compiler/src/CodeGenStmt.cpp
)

# Link the complete LLVM (shared library if LLVM was built that way, otherwise all static components).
if(LLVM_LINK_LLVM_DYLIB)
    target_link_libraries(cshiftc PRIVATE LLVM)
else()
    llvm_map_components_to_libnames(LLVM_LIBS all)
    target_link_libraries(cshiftc PRIVATE ${LLVM_LIBS})
endif()

if(MSVC)
    target_compile_options(cshiftc PRIVATE /W3 /permissive- /utf-8)
else()
    target_compile_options(cshiftc PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()
