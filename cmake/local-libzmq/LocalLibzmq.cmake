set(LIBZMQ_PREFIX ${CMAKE_BINARY_DIR}/libzmq)
set(ZeroMQ_VERSION 4.3.3)
set(LIBZMQ_URL https://github.com/kreditsdev/libzmq/releases/download/v${ZeroMQ_VERSION}/zeromq-${ZeroMQ_VERSION}.tar.gz)
set(LIBZMQ_HASH SHA256=3CCF273C1E81387611788D41462341EA2671DC42C2964EF11C65379DE445A51B)

message(${LIBZMQ_URL})

if(LIBZMQ_TARBALL_URL)
    # make a build time override of the tarball url so we can fetch it if the original link goes away
    set(LIBZMQ_URL ${LIBZMQ_TARBALL_URL})
endif()


file(MAKE_DIRECTORY ${LIBZMQ_PREFIX}/include)

include(ExternalProject)
include(ProcessorCount)
ExternalProject_Add(libzmq_external
    PREFIX ${LIBZMQ_PREFIX}
    URL ${LIBZMQ_URL}
    URL_HASH ${LIBZMQ_HASH}
    CMAKE_ARGS -DWITH_LIBSODIUM=ON -DZMQ_BUILD_TESTS=OFF -DWITH_PERF_TOOL=OFF -DENABLE_DRAFTS=OFF
    -DBUILD_SHARED=OFF -DBUILD_STATIC=ON -DWITH_DOC=OFF -DCMAKE_INSTALL_PREFIX=${LIBZMQ_PREFIX}
    BUILD_BYPRODUCTS ${LIBZMQ_PREFIX}/lib/libzmq.a
    )

add_library(libzmq_vendor STATIC IMPORTED GLOBAL)
add_dependencies(libzmq_vendor libzmq_external)
set_target_properties(libzmq_vendor PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${LIBZMQ_PREFIX}/include
    IMPORTED_LOCATION ${LIBZMQ_PREFIX}/lib/libzmq.a)
