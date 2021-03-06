MACRO (MYPACKAGECHECKCOMMONSIZES)
  INCLUDE (CheckTypeSize)
  CHECK_TYPE_SIZE("short" SIZEOF_SHORT)
  CHECK_TYPE_SIZE("int" SIZEOF_INT)
  CHECK_TYPE_SIZE("long" SIZEOF_LONG)
  CHECK_TYPE_SIZE("long long" SIZEOF_LONG_LONG)
  CHECK_TYPE_SIZE("unsigned short" SIZEOF_UNSIGNED_SHORT)
  CHECK_TYPE_SIZE("unsigned int" SIZEOF_UNSIGNED_INT)
  CHECK_TYPE_SIZE("unsigned long" SIZEOF_UNSIGNED_LONG)
  CHECK_TYPE_SIZE("unsigned long long" SIZEOF_UNSIGNED_LONG_LONG)
  CHECK_TYPE_SIZE("size_t" SIZEOF_SIZE_T)
  #
  # Special types
  #
  FOREACH (_sign "" "u")
    FOREACH (_size 8 16 32 64)
      SET (_mytype    MYPACKAGE_${_sign}int${_size})
      STRING (TOUPPER ${_mytype} _MYTYPE)
      SET (_MYTYPEDEF ${_MYTYPE}_TYPEDEF)

      SET (HAVE_${_MYTYPE} FALSE)
      SET (${_MYTYPE} "")
      SET (${_MYTYPEDEF} "")

      SET (_found_type FALSE)
      FOREACH (_underscore "" "_" "__")
        SET (_type ${_underscore}${_sign}int${_size}_t)
        STRING (TOUPPER ${_type} _TYPE)
        CHECK_TYPE_SIZE (${_type} ${_TYPE})
        IF (HAVE_${_TYPE})
          SET (HAVE_${_MYTYPE} TRUE)
          SET (${_MYTYPE} ${${_TYPE}})
          SET (${_MYTYPEDEF} ${_type})
          BREAK ()
        ENDIF ()
      ENDFOREACH ()
      IF (NOT HAVE_${_MYTYPE})
        #
        # Try with C types
        #
        FOREACH (_c "short" "int" "long" "long long")
          IF ("${_sign}" STREQUAL "u")
            SET (_c "unsigned ${_c}")
          ENDIF ()
          STRING (TOUPPER ${_c} _C)
          STRING (REPLACE " " "_" _C "${_C}")
          IF (HAVE_SIZEOF_${_C})
            IF (${SIZEOF_${_C}} EQUAL ${_size})
              SET (HAVE_${_MYTYPE} TRUE)
              SET (${_MYTYPE} ${${_TYPE}})
              SET (${_MYTYPEDEF} ${_c})
              BREAK ()
            ENDIF ()
          ENDIF ()
        ENDFOREACH ()
      ENDIF ()
      MARK_AS_ADVANCED (
        HAVE_${_MYTYPE}
        ${_MYTYPE}
        ${_MYTYPEDEF})
    ENDFOREACH ()
  ENDFOREACH ()
ENDMACRO()
