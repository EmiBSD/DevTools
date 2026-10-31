# CMake's platform description of EmiBSD, for CMAKE_SYSTEM_NAME=EmiBSD (the runtimes are
# cross-compiled for it; CMake itself knows no such system). Reached through
# CMAKE_MODULE_PATH=llvm/build/cmake (build.sh). An ELF Unix: shared objects with soname
# and rpath, no libdl (dlopen is in the libc), .so then .a when a library is looked up.
set(UNIX 1)
set(CMAKE_DL_LIBS "")
set(CMAKE_SHARED_LIBRARY_C_FLAGS "-fPIC")
set(CMAKE_SHARED_LIBRARY_CXX_FLAGS "-fPIC")
set(CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS "-shared")
set(CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS "-shared")
set(CMAKE_SHARED_LIBRARY_SONAME_C_FLAG "-Wl,-soname,")
set(CMAKE_SHARED_LIBRARY_SONAME_CXX_FLAG "-Wl,-soname,")
set(CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG "-Wl,-rpath,")
set(CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG_SEP ":")
set(CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG "-Wl,-rpath-link,")
set(CMAKE_EXE_EXPORTS_C_FLAG "-Wl,--export-dynamic")
set(CMAKE_SHARED_MODULE_C_FLAGS "-fPIC")
set(CMAKE_SHARED_MODULE_CXX_FLAGS "-fPIC")
set(CMAKE_FIND_LIBRARY_PREFIXES "lib")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".so" ".a")
set(CMAKE_INSTALL_SO_NO_EXE 1)
include(Platform/UnixPaths)
