cfdtools_add_executable(surface_cuts
  surface_cuts.f
)
target_link_libraries(cfdtools_surface_cuts
  cfdtools_gridlib
  cfdtools_geomlib
  cfdtools_interplib
  cfdtools_integratelib
  cfdtools_intrinsics
  cfdtools_numodules
  cfdtools_searchlib
  cfdtools_triangulation_io
  cfdtools_ugridlib
)
