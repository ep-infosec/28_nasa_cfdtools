cfdtools_add_executable(reshape
  reshape.f
)
target_link_libraries(cfdtools_reshape
  cfdtools_geomlib
  cfdtools_gridlib
  cfdtools_numodules
  cfdtools_interplib
  cfdtools_searchlib
  cfdtools_progtools
)
