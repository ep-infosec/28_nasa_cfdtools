cfdtools_add_executable(template
  rdlist.f
  reader.f
  scan2.f
  template.f
  upcase.f
)
# TODO: Remove this extension. Not sure why we're using this.
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
    set_source_files_properties(template.f
      PROPERTIES
        COMPILE_FLAGS -fcray-pointer
    )
endif()
target_link_libraries(cfdtools_template
  cfdtools_progtools
)
