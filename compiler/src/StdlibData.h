#pragma once

// The standard library is written in CShift (stdlib/*.csh). CMake embeds the sources into the compiler
// (generated file StdlibData.cpp); every compilation parses them before the user's files.
struct StdlibFile
{
    const char* name;
    const unsigned char* data;
    unsigned long size;
};

extern const StdlibFile kStdlibFiles[];
extern const unsigned kStdlibFileCount;
