cmake_minimum_required(VERSION 3.7)

project(libkreditsmq CXX)

include(GNUInstallDirs)

set(KREDITSMQ_VERSION_MAJOR 1)
set(KREDITSMQ_VERSION_MINOR 1)
set(KREDITSMQ_VERSION_PATCH 4)
set(KREDITSMQ_VERSION "${KREDITSMQ_VERSION_MAJOR}.${KREDITSMQ_VERSION_MINOR}.${KREDITSMQ_VERSION_PATCH}")
message(STATUS "kreditsmq v${KREDITSMQ_VERSION}")

set(KREDITSMQ_LIBVERSION 0)


option(BUILD_SHARED_LIBS "Build shared libraries instead of static ones" ON)


list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

configure_file(kreditsmq/version.h.in kreditsmq/version.h @ONLY)
configure_file(libkreditsmq.pc.in libkreditsmq.pc @ONLY)

add_library(kreditsmq
    kreditsmq/auth.cpp
    kreditsmq/bt_serialize.cpp
    kreditsmq/connections.cpp
    kreditsmq/jobs.cpp
    kreditsmq/kreditsmq.cpp
    kreditsmq/proxy.cpp
    kreditsmq/worker.cpp
)
set_target_properties(kreditsmq PROPERTIES SOVERSION ${KREDITSMQ_LIBVERSION})

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(kreditsmq PRIVATE Threads::Threads)

# libzmq is nearly impossible to link statically from a system-installed static library: it depends
# on a ton of other libraries, some of which are not all statically available.  If the caller wants
# to mess with this, so be it: they can set up a libzmq target and we'll use it.  Otherwise if they
# asked us to do things statically, don't even try to find a system lib and just build it.
set(kreditsmq_build_static_libzmq OFF)
if(TARGET libzmq)
    target_link_libraries(kreditsmq PUBLIC libzmq)
elseif(BUILD_SHARED_LIBS)
    include(FindPkgConfig)
    pkg_check_modules(libzmq libzmq>=4.3 IMPORTED_TARGET)
    # Debian sid includes a -isystem in the mit-krb package that, starting with pkg-config 0.29.2,
    # breaks cmake's pkgconfig module because it stupidly thinks "-isystem" is a path, so if we find
    # -isystem in the include dirs then hack it out.
    get_property(zmq_inc TARGET PkgConfig::libzmq PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
    list(FIND zmq_inc "-isystem" broken_isystem)
    if(NOT broken_isystem EQUAL -1)
      list(REMOVE_AT zmq_inc ${broken_isystem})
      set_property(TARGET PkgConfig::libzmq PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${zmq_inc})
    endif()

    if(libzmq_FOUND)
        target_link_libraries(kreditsmq PUBLIC PkgConfig::libzmq)
    else()
        set(kreditsmq_build_static_libzmq ON)
    endif()
else()
    set(kreditsmq_build_static_libzmq ON)
endif()

if(kreditsmq_build_static_libzmq)
    message(STATUS "libzmq >= 4.3 not found or static build requested, building bundled 4.3.2")
    list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/local-libzmq")
    include(LocalLibzmq)
    target_link_libraries(kreditsmq PUBLIC libzmq_vendor)
endif()

target_include_directories(kreditsmq
    PUBLIC
        $<INSTALL_INTERFACE:>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/cppzmq>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/mapbox-variant/include>
)

target_compile_options(kreditsmq PRIVATE -Wall -Wextra -Werror)
set_target_properties(kreditsmq PROPERTIES
    CXX_STANDARD 14
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
    POSITION_INDEPENDENT_CODE ON
)

function(link_dep_libs target linktype libdirs)
    foreach(lib ${ARGN})
        find_library(link_lib-${lib} NAMES ${lib} PATHS ${libdirs})
        message(STATUS "FIND ${lib} FOUND ${link_lib-${lib}}")
        if(link_lib-${lib})
            target_link_libraries(${target} ${linktype} ${link_lib-${lib}})
        endif()
    endforeach()
endfunction()

# If the caller has already set up a sodium target then we will just link to it, otherwise we go
# looking for it.
if(TARGET sodium)
    target_link_libraries(kreditsmq PRIVATE sodium)
    if(kreditsmq_build_static_libzmq)
        target_link_libraries(libzmq_vendor INTERFACE sodium)
    endif()
else()
    pkg_check_modules(sodium REQUIRED libsodium IMPORTED_TARGET)

    if(BUILD_SHARED_LIBS)
        target_link_libraries(kreditsmq PRIVATE PkgConfig::sodium)
        if(kreditsmq_build_static_libzmq)
            target_link_libraries(libzmq_vendor INTERFACE PkgConfig::sodium)
        endif()
    else()
        link_dep_libs(kreditsmq PRIVATE "${sodium_STATIC_LIBRARY_DIRS}" ${sodium_STATIC_LIBRARIES})
        target_include_directories(kreditsmq PRIVATE ${sodium_STATIC_INCLUDE_DIRS})
        if(kreditsmq_build_static_libzmq)
            link_dep_libs(libzmq_vendor INTERFACE "${sodium_STATIC_LIBRARY_DIRS}" ${sodium_STATIC_LIBRARIES})
            target_link_libraries(libzmq_vendor INTERFACE ${sodium_STATIC_INCLUDE_DIRS})
        endif()
    endif()
endif()

add_library(kreditsmq::kreditsmq ALIAS kreditsmq)

export(
    TARGETS kreditsmq
    NAMESPACE kreditsmq::
    FILE kreditsmqTargets.cmake
)
install(
    TARGETS kreditsmq
    EXPORT kreditsmqConfig
    DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

install(
    FILES kreditsmq/auth.h
          kreditsmq/batch.h
          kreditsmq/bt_serialize.h
          kreditsmq/connections.h
          kreditsmq/hex.h
          kreditsmq/kreditsmq.h
          kreditsmq/message.h
          kreditsmq/string_view.h
          ${CMAKE_CURRENT_BINARY_DIR}/kreditsmq/version.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/kreditsmq
)
option(KREDITSMQ_INSTALL_MAPBOX_VARIANT "Install mapbox-variant headers with kreditsmq/ headers" ON)
if(KREDITSMQ_INSTALL_MAPBOX_VARIANT)
  install(
    FILES mapbox-variant/include/mapbox/variant.hpp
          mapbox-variant/include/mapbox/variant_cast.hpp
          mapbox-variant/include/mapbox/variant_io.hpp
          mapbox-variant/include/mapbox/variant_visitor.hpp
          mapbox-variant/include/mapbox/recursive_wrapper.hpp
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/kreditsmq/mapbox
  )
endif()

option(KREDITSMQ_INSTALL_CPPZMQ "Install cppzmq header with kreditsmq/ headers" ON)
if(KREDITSMQ_INSTALL_CPPZMQ)
  install(
    FILES cppzmq/zmq.hpp
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/kreditsmq
  )
endif()


install(
    FILES ${CMAKE_CURRENT_BINARY_DIR}/libkreditsmq.pc
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)

if(CMAKE_PROJECT_NAME STREQUAL PROJECT_NAME)
  set(kreditsmq_IS_TOPLEVEL_PROJECT TRUE)
else()
  set(kreditsmq_IS_TOPLEVEL_PROJECT FALSE)
endif()

option(KREDITSMQ_BUILD_TESTS "Building and perform kreditsmq tests" ${kreditsmq_IS_TOPLEVEL_PROJECT})
if(KREDITSMQ_BUILD_TESTS)
    add_subdirectory(tests)
endif()

