INCLUDE (StringToInternalBool)
MACRO (FINDFILENO)
  #
  # Dependencies
  #
  STRINGTOINTERNALBOOL(_HAVE_STDIO_H HAVE_STDIO_H)
  #
  # Test
  #
  FOREACH (KEYWORD "fileno" "_fileno" "__fileno")
    MESSAGE(STATUS "Looking for ${KEYWORD}")
    TRY_COMPILE (C_HAS_${KEYWORD} ${CMAKE_CURRENT_BINARY_DIR}
      ${CMAKE_CURRENT_SOURCE_DIR}/cmake/fileno.c
      COMPILE_DEFINITIONS "-DC_FILENO=${KEYWORD} -DHAVE_STDIO_H=${_HAVE_STDIO_H}")
    IF (C_HAS_${KEYWORD})
      MESSAGE(STATUS "Looking for ${KEYWORD} - found")
      SET (C_FILENO ${KEYWORD})
      BREAK ()
    ENDIF ()
  ENDFOREACH ()
ENDMACRO ()
IF (NOT C_FILENO)
  FINDFILENO ()
  SET (C_FILENO "${C_FILENO}" CACHE STRING "C FILENO")
  MARK_AS_ADVANCED (C_FILENO)
ENDIF (NOT C_FILENO)
