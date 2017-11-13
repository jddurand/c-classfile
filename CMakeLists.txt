CMAKE_MINIMUM_REQUIRED (VERSION 3.0.0 FATAL_ERROR)
IF (NOT MYPACKAGEBOOTSTRAP_DONE)
  INCLUDE ("3rdparty/github/cmake-utils/cmake/MyPackageBootstrap.cmake")
ENDIF ()

MYPACKAGESTART (classfile 1 0 0)

MYPACKAGELIBRARY(
  ${CMAKE_CURRENT_SOURCE_DIR}/include/classfile/internal/config.h.in
  ${INCLUDE_OUTPUT_PATH}/classfile/internal/config.h
  src/classfile.c)

################
# For CHAR_BIT #
################
CHECK_INCLUDE_FILE ("limits.h" HAVE_LIMITS_H)
CHECK_INCLUDE_FILE ("arpa/inet.h" HAVE_ARPA_INET_H)
CHECK_INCLUDE_FILE ("netinet/in.h" HAVE_NETINET_IN_H)
CHECK_INCLUDE_FILE ("machine/endian.h" HAVE_MACHINE_ENDIAN_H)
CHECK_INCLUDE_FILE ("sys/endian.h" HAVE_SYS_ENDIAN_H)
CHECK_INCLUDE_FILE ("ctype.h" HAVE_CTYPE_H)

#######################
# For open on Windows #
#######################
CHECK_INCLUDE_FILE ("io.h" HAVE_IO_H)

################
# Dependencies #
################
SET (ALL_IN_ONE TRUE)
MYPACKAGEDEPENDENCY (genericLogger "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/github/genericLogger" LIBS)
MYPACKAGEDEPENDENCY (genericStack "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/github/genericStack" LIBS)
MYPACKAGEDEPENDENCY (genericHash "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/github/genericHash" LIBS)

################
# Executables  #
################
MYPACKAGEEXECUTABLE(classFileExe bin/classfile.c)
FOREACH (_target classFileExe classFileExe_static)
  IF (${_target} STREQUAL "classFileExe")
    SET_TARGET_PROPERTIES(${_target} PROPERTIES OUTPUT_NAME classfile)
  ELSE ()
    SET_TARGET_PROPERTIES(${_target} PROPERTIES OUTPUT_NAME classfile_static)
  ENDIF ()
ENDFOREACH ()
