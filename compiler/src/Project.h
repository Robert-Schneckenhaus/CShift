#pragma once

#include <string>
#include <vector>

// A CShift project is described by a cshift.json file (see BuildDesign.md):
//
//   {
//     "name": "demo",
//     "version": "0.1.0",
//     "type": "executable",
//     "sources": ["src"],
//     "output": "bin/demo",
//     "optimize": 2,
//     "links": [],
//     "target": "x86_64-pc-windows-msvc"
//   }
//
// Only "name" is required.
struct Project
{
    std::string file; // path of cshift.json
    std::string dir;  // directory of cshift.json
    std::string name;
    std::string version;
    std::string type = "executable"; // "executable" or "object"
    std::vector<std::string> sources; // resolved .csh files, sorted
    std::string output;               // output path (without the platform's file extension)
    int optimize = 2;
    bool hasOptimize = false;
    std::vector<std::string> links;     // library names for the linker (-l<name>)
    std::vector<std::string> linkFiles; // library/object files for the linker (from "links" entries that are files)
    std::vector<std::string> includePaths; // C header search paths (-I), relative to the project file
    std::vector<std::string> libraryPaths; // linker search paths (-L)
    std::vector<std::string> defines;      // macros for parsing C headers (-D)
    std::vector<std::string> apiPaths;     // headers with these path parts belong to the imported API (--ffi-api)
    std::string target;             // target triple, empty = host
};

// Loads a project. 'location' is a directory containing cshift.json, the path of a project file, or empty:
// then cshift.json is searched in the current directory and its parents.
bool loadProject(const std::string& location, Project& project, std::string& error);

// Creates a new project directory with cshift.json and src/main.csh ("cshiftc new <path>").
bool createProject(const std::string& path, std::string& error);
