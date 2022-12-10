!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   module tri_header_structure

!  Module for the header information associated with a triangulated surface dataset (coordinates plus function values) in 3-space.
!  No provision for 2-space triangulations has been made (yet).  Elements other than triangles were planned for from the start,
!  and this version supports Tecplot's format for volume meshes where all elements are defined by the same number of nodes
!  (4 for tetrahedra, and 8 for hexahedra).  Volume elements may contain collapsed edges if they have been formed by replicating
!  some nodes as can happen when a tetrahedral volume has been turned into hexahedra.  This case is treated efficiently as a single
!  tetrahedron per "hex" cell.  The full hex cell case (which can be treated as 5 tets or 6 tets) has not been completed.

!  Tecplot files are treated initially, but provision is made for supporting other unstructured formats.  To read such a file, the
!  application must assign header%filename, %fileform, %formatted, and %nvertices.

   type tri_header_type
      character (80)     :: filename                ! Name of file if the dataset is to be read or written
      integer            :: fileform                ! 1 => Tecplot vertex-centered; 2 => Tecplot cell-centered; 3 => ?
      logical            :: formatted               ! T | F for ASCII | binary
      integer            :: nvertices               ! # points defining an element; 3|4|8 for triangles|tets|hexahedra, all zones
      integer            :: numf                    ! # additional variables beyond ndim = 3; numf >= 0
      integer            :: nzones                  ! # zones in dataset (>= 1 at present for Tecplot formats)
      integer            :: datapacking             ! Same for all zones;  0 => POINT order; 1 => BLOCK order
      real               :: xmin, xmax              ! x data ranges over all zones
      real               :: ymin, ymax              ! y data ranges over all zones
      real               :: zmin, zmax              ! z data ranges over all zones
      real               :: CM(3)                   ! Center of mass for all zones
      real               :: R(3,3)                  ! Rotation matrix describing the principal axes for all zones w.r.t. Ox/y/z
      real               :: lambda(3)               ! Eigenvalues, ascending
      real               :: interior_point(3)       ! Interior point to use in computing enclosed_volume for each surface zone
      real               :: surface_area            ! Total surface area of this triangulation
      real               :: enclosed_volume         ! Total volume defined by this triangulation and interior_point
      real               :: solid_volume            ! Total volume of all elements of a volume mesh (all tets or all hexahedra)
      logical            :: combine_zones           ! T means tri_read combines all zones into one, using header%conn, %xyz, %f
      logical            :: centroids_to_vertices   ! T means tri_read converts function data to vertices if fileform = 2
      integer            :: nnodes                  ! # points or nodes forming such a combined triangulation (or volume)
      integer            :: nelements               ! # triangles|tetra/hexahedra forming the combined surface or volume mesh
      integer, dimension (:,:), pointer :: conn     ! Connectivity for all zones if needed for rapid searching, as for tri_type
      real,    dimension (:,:), pointer :: xyz      ! Element vertex coordinates for all zones for rapid searching   "   "   "
      real,    dimension (:,:), pointer :: f        ! Vertex-centered function values for all zones  "   "   "   "   "   "   "
      character (80)          :: title              ! Dataset title
      character (32), pointer :: varname (:)        ! Variable names; embedded blanks are permitted; 32 matches other software
   end type tri_header_type

   end module tri_header_structure

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   module tri_zone_structure

!  Module for a triangulated surface zone with associated flow field variables and a zone name (triangulation_io.f90 version).
!  Serves for tetrahedral or hexahedral unstructured volume data as well.

   type tri_type
      integer                :: nzoneheaderlines    ! # lines in zone header, to facilitate reading zones after counting them
      character (32)         :: zone_title          ! Zone/block title; embedded blanks are permitted; same length as elsewhere
      integer                :: nnodes              ! # points or nodes forming this triangulation (or tetrahedral volume) zone
      integer                :: nelements           ! # triangles|tetra/hexahedra forming this zone of the surface or volume mesh
      character (8)          :: element_type        ! Assumed to be TRI[ANGLE] for surfaces; TET|HEX for volumes (may be extended)
      real                   :: xmin, xmax          ! x data ranges for this zone
      real                   :: ymin, ymax          ! y data ranges for this zone
      real                   :: zmin, zmax          ! z data ranges for this zone
      real                   :: cm(3)               ! Center of mass for this zone
      real                   :: solutiontime        ! Time (or some other useful real number) associated with the zone
      real                   :: surface_area        ! Total surface area of this zone if it is a triangulation
      real                   :: enclosed_volume     ! Total volume defined by this triangulation zone and header%interior_point
      real                   :: solid_volume        ! Total volume of all elements of this zone of a volume mesh (all tets|hexes)
      logical                :: allocated_conn      ! "if (allocated(zone%conn))" is illegal for a pointer argument;
      logical                :: allocated_xyz       ! only an allocatable array can be tested this way;
      logical                :: allocated_f         ! therefore, try to manage allocation/deallocation another way
      logical                :: allocated_area
      logical                :: allocated_volume
      logical                :: allocated_centroid
      integer, dimension (:,:), pointer :: conn     ! conn(1:nvertices,n) point into xyz(1:nvertices,*) for element n
      real,    dimension (:,:), pointer :: xyz      ! Element vertex coordinates are in xyz(1:3,1:nnodes)
      real,    dimension (:,:), pointer :: f        ! Vertex-centered function values are in f(1:numf,1:nnodes);
                                                    ! cell-centered functions are in f(1:numf,1:nelements)
      real,    dimension (:),   pointer :: area     ! For element n of this zone, area(n) is its surface area
      real,    dimension (:),   pointer :: volume   ! For element n of this zone, volume(n) is its volume
      real,    dimension (:,:), pointer :: centroid ! For element n of this zone, centroid(1:3,n) are the centroid coordinates
   end type tri_type

   end module tri_zone_structure

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   module triangulation_io

!  This module packages I/O for unstructured surface datasets in 3-space.  It has now been extended for unstructured volumes too.
!  Initially, two types of Tecplot surface formats are handled with common parsing.  Other formats may be treated here some day.
!  Both BLOCK and POINT data packing formats are supported.  The  (x,y,z) coordinates are assumed to be the first three variables.
!  If the function values are vertex-centered, there should be as many sets as for the coordinates (i.e., # function sets = nnodes).
!  If the function values are cell-centered, there should be as many sets as there are surface/volume elements (nelements).
!
!  The initial version dealt with a single-zone surface triangulation only, and provided only a reading capability.
!  This version deals with multi-zone triangulation files, and includes writing utilities (Tecplot formats).
!  It also deals with multi-zone volume datasets involving all tetrahedral or all hexahedral cells in unstructured form.
!
!  This version also includes utilities for computing geometric properties of surface triangulations (data ranges, area, enclosed
!  volume) and of volume datasets.
!
!  History:
!
!  04/02/04  David Saunders  Initial implementation of XYZQ_IO module for PLOT3D files.
!  07/29/04 -  "       "     Adaptation for multizone structured-data Tecplot files as Tecplot_io.f90.
!  03/02/07
!  03/01/05    "       "     Initial implementation of reading of a single-zone Tecplot-type surface dataset with vertex-centered
!                            functions, as subroutine Tecplot_read_tri_data for program TRI_TO_QUAD.
!  03/11/10 -  "       "     Initial module triangulation_io along the lines of Tecplot_io but for a single zone and reading only.
!  03/17/10                  Nomenclature allows for possible tetrahedral volume datasets as well (composed of triangles after all).
!                            Only Tecplot files are treated so far, with the functions vertex- or cell-centered according to
!                            tri_header%fileform = 1 or 2.
!  02/27/14    "       "     Added the missing write utilities for multi-zone triangulations.
!  03/29/14    "       "     The format for the "too many zones" diagnostic was wrong, and max_zones was still 1.
!  07/03/14    "       "     The run-time format for output functions wasn't being set correctly.
!  10/17/14    "       "     Asteroid studies prompted inclusion of some geometric utilities (surface area, enclosed volume, what
!                            else?) here rather than in some new module.
!  10/21/14    "       "     Center of mass and moments of inertia required storing all elemental centroids and areas.
!  10/22/14    "       "     Deallocation of pointer arrays is problematic: we can't use "if (allocated (zone%conn))" for instance.
!                            Therefore, introduce logical :: allocated_conn, etc.
!  11/10/14 -  "       "     Eric Stern produced an interior volume grid of hexahedra (actually really tetrahedra with collapsed
!  11/18/14                  edges), prompting unstructured volume grid analogues of the unstructured surface utilities.
!  03/08/15    "       "     Added a bare-bones utility for writing a surface triangulation as a small field NASTRAN file.
!  08/03/15    "       "     Handled the ZONETYPE=FExxxx keyword as an alternative to F=FEPOINT, ET=xxx for defining element type.
!  07/21/18    "       "     ADT searching of multizone triangulations (or unstructured volumes) requires a way of assembling all
!                            zones as a single list of all elements.  Subroutine tri_read now has this option, via new header
!                            fields %combine_zones, %conn, %xyz and %f.  If functions are cell-centered, they will be area-averaged
!                            to the vertices as needed for ADT searching.  But see the following afterthought.
!  07/23/18    "       "     Tri_read now has an independent option to convert centroid function values to vertices via new header
!                            field, %centroids_to_vertices.
!  07/26/18    "       "     Tecplot won't read a single-function line VARLOCATION=([4-4]=CELLCENTERED) written by tri_zone_write.
!                            Instead, it expects VARLOCATION=([4]=CELLCENTERED).  Thanks to Jeff Hill for thinking of this.
!
!  Author:  David Saunders, ELORET Corporation/NASA Ames Research Center, CA (later with ERC, Inc. and AMA, Inc. at NASA ARC).
!
!  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   use tri_header_structure  ! Defines "tri_header" derived data type for one unstructured multizone dataset
   use tri_zone_structure    ! Defines "tri_type" derived data type for one unstructured zone
   use string_justify        ! Module with generic interfaces for left- and right-justifying any data type in any field

   implicit none

   private

!  Constants used by the package:

   integer,   parameter :: len_string = 64         ! Room and then some for a zone size/type string
   integer,   parameter :: len_buffer = 500        ! Limit on length of an input line, most likely the DT=(SINGLE SINGLE ... ) line
   integer,   parameter :: max_zones  = 100        ! Limit on number of zones in a file being read
   integer,   parameter :: max_length = 1000       ! Limit on length of string into which variable names are packed
   integer,   parameter :: name_limit = 32         ! Limit on the length of variable names; must match value in modules above
   integer,   parameter :: nsfield    = 8          ! Width  of a NASTRAN small field
   integer,   parameter :: nsline     = 80         ! Length of a NASTRAN small field line

   real,      parameter :: fourth     = 0.25
   real,      parameter :: half       = 0.5
   real,      parameter :: sixth      = 1.0 / 6.0
   real,      parameter :: third      = 1.0 / 3.0
   real,      parameter :: zero       = 0.0
   real,      parameter :: undefined  = -999.

   logical,   parameter :: false = .false.,       &
                           true  = .true.
   character (1), parameter :: blank  = ' ',      &
                               null   = char (0), &
                               quotes = '"'
   character (4), parameter :: GRID   = 'GRID'     ! For small field 1 of a NASTRAN triangulation grid point definition
   character (6), parameter :: CTRIA3 = 'CTRIA3'   ! For small field 1 of a NASTRAN triangulation cell definition

!  Internal variables used by the package:

   integer   :: fileform                           ! Internal copy of header%fileform
!! integer   :: IsDouble                           ! 0 = single precision data (-r4); 1 = double precision data (-r8)
   integer   :: nzoneheaderlines (max_zones)       ! Temporary storage for # zone header lines while # zones is being counted
   integer   :: nelements (max_zones)              !     "        "     "  # elements per zone
   integer   :: nnodes (max_zones)                 !     "        "     "  # nodes per zone
   integer   :: numf                               ! Internal copy of header%numf
   integer   :: nvar                               ! Internal variable = 3 + numf
   integer   :: nvertices                          ! Internal copy of header%nvertices
   integer   :: nzones                             ! Internal copy of header%nzones
   real      :: eps                                ! epsilon (eps) allows IsDouble to be assigned for binary reads & writes
   logical   :: formatted                          ! Internal copy of header%formatted
   logical   :: valid, verbose                     ! Pass ios = 1 to tri/vol_header_read to activate printing of header/zone info.
   character (len_buffer) :: buffer                ! For a line of input; its length is dominated by DT=(SINGLE SINGLE ... ) lines
   character (max_length) :: packed_names          ! For binary output; reused for some of the reading;
                                                   ! Fortran 90 doesn't support dynamically variable string lengths
!  Parsing utilities used by the package:

   logical   :: number
   external  :: number, ndigits, scan2, scan4, upcase

!  Tecplot procedures (but binary output has not been completed):

!! integer   :: TecIni110, TecAuxStr110, TecZne110, TecZAuxStr110, TecDat110, TecEnd110
!! external  :: TecIni110, TecAuxStr110, TecZne110, TecZAuxStr110, TecDat110, TecEnd110

!  Utilities provided for applications:

   public :: tri_read               ! Reads  an entire unstructured surface dataset
   public :: tri_write              ! Writes an entire unstructured surface dataset

   public :: tri_header_read        ! Reads  an unstructured surface dataset header
   public :: tri_header_write       ! Writes fn unstructured surface dataset header
   public :: tri_zone_allocate      ! Allocate the %xyz and %conn and optional %f arrays for one zone of surface triangulation
   public :: tri_zone_read          ! Reads  one zone of an unstructured surface dataset
   public :: tri_zone_write         ! Writes one zone of an unstructured surface dataset

   public :: deallocate_tri_zones   ! Deallocates any allocated arrays of the indicated zone(s) of an unstructured surface dataset

   public :: tri_data_range         ! Computes the x/y/z data ranges over all surface zones
   public :: tri_area               ! Computes the total wetted area over all zones of a surface triangulation
   public :: tri_volume             ! Computes the volume enclosed by all surface zones using header%interior_point
   public :: tri_center_of_mass     ! Computes the CM of all zones (and of each zone; all cell centroids & areas are also stored)
   public :: tri_moments_of_inertia ! Computes the overall moments of inertia about Ox/y/z & the rotation matrix <-> principal axes
   public :: tri_apply_rotation_R   ! Applies the rotation matrix R from tri_moments_of_inertia; assumes Ox/Oy/Oz moments increase
   public :: tri_zone_data_range    ! Computes the x/y/z data ranges for one surface zone
   public :: tri_zone_area          ! Computes the total wetted area of one triangulated zone
   public :: tri_zone_volume        ! Computes the enclosed volume defined by a zone and its header%interior_point
   public :: tri_zone_center_of_mass! Computes the center of mass of one surface zone; its cell centroids & areas are also stored

!  Analogous utilities for volume meshes (tets or hexahedra); some can use the tri* utility directly, but this avoids confusion:

   public :: vol_read               ! Reads  an entire unstructured volume dataset
   public :: vol_write              ! Writes an entire unstructured volume dataset

   public :: vol_get_element_type   ! Reads enough of an unstructured dataset (surface or volume) to determine ET (element type)
   public :: vol_header_read        ! Reads  an unstructured volume dataset header
   public :: vol_header_write       ! Writes fn unstructured volume dataset header
   public :: vol_zone_allocate      ! Allocate the %xyz and %conn and optional %f arrays for one zone of an unstructured volume
   public :: vol_zone_read          ! Reads  one zone of an unstructured volume
   public :: vol_zone_write         ! Writes one zone of an unstructured volume

   public :: deallocate_vol_zones   ! Deallocates any allocated arrays of the indicated zone(s) of an unstructured volume

   public :: vol_data_range         ! Computes the x/y/z data ranges over all volume zones
   public :: vol_volume             ! Computes the volume of all elements of all zones of an unstructured volume dataset
   public :: vol_center_of_mass     ! Computes the CM of all zones (and of each zone; all cell centroids & volumes are also stored)
   public :: vol_moments_of_inertia ! Computes the overall moments of inertia about Ox/y/z & the rotation matrix <-> principal axes
   public :: vol_apply_rotation_R   ! Applies the rotation matrix R from vol_moments_of_inertia; assumes Ox/Oy/Oz moments increase
   public :: vol_zone_data_range    ! Computes the x/y/z data ranges for one volume zone
   public :: vol_zone_volume        ! Computes the the volume of all cells of one volume zone
   public :: vol_zone_center_of_mass! Computes the center of mass of one zone; its cell centroids & volumes are also stored

!  NASTRAN file utilities (rudimentary):

   public :: nas_sf_tri_write       ! Writes a triangulation in small field NASTRAN format

   contains

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_read (lun, header, grid, ios)

!     Read a 3-space unstructured surface dataset, one or more zones, binary or ASCII, with BLOCK or POINT data packing.
!     The first 3 variables are returned as the x, y, z fields of each zone in grid(:).
!     Remaining variables become the "f" field packed in "point" order (n-tuples, where n = numf = # variables - 3).
!     The input file title is also returned, along with the variable names (up to name_limit characters each).
!     Titles for the zone or zones are returned in the appropriate field of each element of the grid array.
!     The file is opened and closed here.
!
!     07/21/18  ADT searching of multizone unstructured datasets requires treating all elements of all zones as a single list.
!               This option has been enabled here via new header variables as explained above, starting with header%combine_zones.
!               The zones are read and packed one zone at a time, and they are NOT deallocated in case the application needs to do
!               more than just searching/interpolation.  If the function data are cell-centered, they are area-averaged to vertices
!               (for surface_zones; volume averaging of volume-cell centroid function values has not been implemented yet). This
!               conversion may also be requested via header%centroids_to_vertices even if header%combine_zones = F.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)                   :: lun      ! Logical unit for the file being read;
                                                         ! opened here upon entry; closed here before the return
      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information;
                                                         ! input with file name, form, formatting, and element size in place
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and optional f data;
                                                         ! allocated here prior to the reading
      integer, intent (inout)                :: ios      ! 1 on input activates printing of header/zone info. during the read;
                                                         ! 0 on output means no error detected, else diagnostics are written to
                                                         ! standard output; early return follows
!     Local variables:

      integer :: ie, in, iz, ne, nf, nn, ntri, nv, nvert, nz
      logical :: combine
      real, allocatable :: area_total(:), tri_area(:), fnode(:,:)

!     Execution:
!     ----------

!     Open the file, read the header records, determine the number of zones, allocate an array of unstructured zone structures,
!     and set up the zone dimensions by scanning till EOF:

      call tri_header_read (lun, header, grid, ios)
      if (ios /= 0) go to 999

      combine = header%combine_zones
      if (combine) then  ! Count all nodes and all elements of all zones
         nz = header%nzones
         nf = header%numf
         nn = 0;  ne = 0
         do iz = 1, nz
            nn = nn + grid(iz)%nnodes
            ne = ne + grid(iz)%nelements
         end do

         nv = header%nvertices
         allocate (header%conn(nv,ne), header%xyz(3,nn), header%f(nf,nn))
         header%nnodes = nn
         header%nelements = ne
         if (verbose) write (*, '(a, i7)') ' # combined nodes:', nn, ' # combined cells:', ne
      end if

!     Allocate and read each zone:

      ie = 0;  in = 0  ! Packing offsets

      do iz = 1, header%nzones

         call tri_zone_allocate (header, grid(iz), ios)
         if (ios /= 0) then
            write (*, '(a, i6)') ' tri_read: Trouble allocating zone #', iz
            write (*, '(2a)')    ' File name: ', trim (header%filename)
            go to 999
         end if

         call tri_zone_read (lun, header, grid(iz), ios)
         if (ios /= 0) then
            write (*, '(a, i6)')  ' tri_read:  Trouble reading zone #', iz
            write (*, '(2a)')     ' File name: ', trim (header%filename)
            write (*, '(a, 3i9)') ' # nodes, # elements, # functions: ', grid(iz)%nnodes, grid(iz)%nelements, numf
            go to 999
         end if

         ntri  = grid(iz)%nelements
         nvert = grid(iz)%nnodes

         if (combine .or. header%centroids_to_vertices) then
            if (header%fileform == 2) then  ! Convert function values from centroids to vertices
               allocate (tri_area(ntri), area_total(nvert))

               call tri_areas (nvert, ntri, grid(iz)%xyz, grid(iz)%conn, tri_area, area_total)

               allocate (fnode(nf,nvert))

               call tri_centers_to_vertices (nvert, ntri, nf, tri_area, area_total, grid(iz)%conn, grid(iz)%f, fnode)

               deallocate (tri_area, area_total)
               deallocate (grid(iz)%f);  allocate (grid(iz)%f(nf,nvert))

               grid(iz)%f(:,:) = fnode(:,:);  deallocate(fnode)
            end if
         end if

         if (combine) then  ! Pack the zone data into the header space for all zones:
            header%conn(:,ie+1:ie+ntri)  = grid(iz)%conn(:,:) + in
            header%xyz (:,in+1:in+nvert) = grid(iz)%xyz(:,:)
            header%f   (:,in+1:in+nvert) = grid(iz)%f(:,:)
            ie = ie + ntri
            in = in + nvert
            if (verbose) write (*, '(a, 2i10)') ' Zone packing offsets ie & in:', ie, in
         end if

      end do

!!    if (verbose .and. combine) then
!!       write (*, '(3es25.15)') header%xyz(:,:)
!!       write (*, '(3i10)')     header%conn(:,:)
!!    end if

  999 continue

!!    if (header%formatted) then
         close (lun)
!!    else
!!       ios = TecEnd110 ()
!!       if (ios /= 0) write (*, '(2a)') ' Trouble closing binary file ', trim (header%filename)
!!    end if

      end subroutine tri_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_write (lun, header, grid, ios)

!     Write a 3-space unstructured surface dataset, binary or ASCII, with BLOCK or POINT data packing.
!     The first 3 variables are taken to be the x, y, z fields of each zone in grid(:).
!     Remaining variables should be the "f" field packed in "point" order (n-tuples, where n = numf = # variables - 3).
!     The indicated file title is written along with the variable names (up to name_limit characters each).
!     Titles for the zone or zones are written from the appropriate field of each element of the grid array.
!     The file is opened and closed here.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)                   :: lun      ! Logical unit for the file being written;
                                                         ! opened here upon entry; closed here before the return
      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information;
                                                         ! input with file name, form, formatting, and element size in place
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and optional f data;
                                                         ! NOT deallocated after the writing
      integer, intent (out)                  :: ios      ! 0 on output means no error detected, else diagnostics are written to
                                                         ! standard output; early return follows
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

!     Open the file and write the header records:

      call tri_header_write (lun, header, grid, ios)

      if (ios /= 0) go to 999

!     Write each zone:

      do iz = 1, header%nzones

         call tri_zone_write (lun, header, grid(iz), ios)

         if (ios /= 0) then
            write (*, '(a, i4)')  ' tri_write:  Trouble writing zone #', iz
            write (*, '(2a)')     ' File name: ', trim (header%filename)
            write (*, '(a, 3i9)') ' # nodes, # elements, # functions: ', grid(iz)%nnodes, grid(iz)%nelements, numf
            go to 999
         end if

      end do

  999 continue

!!    if (header%formatted) then
         close (lun)
!!    else
!!       ios = TecEnd110 ()
!!       if (ios /= 0) write (*, '(2a)') ' Trouble closing binary file ', trim (header%filename)
!!    end if

      end subroutine tri_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine tri_header_read (lun, header, grid, ios)
!
!     Open a file of 3-space unstructured surface data and read the file header and zone header records.
!     The grid(*) array is allocated and zone header information is entered.
!     Before returning, the file is rewound and advanced ready for reading the first zone.
!
!     If no variable names are present, they are defaulted to "X", "Y", "Z", "V1", "V2", ...,
!     but a DT=(... ) record must then accompany zone 1 so that the number of variables can be determined.
!
!     Reading of binary files is incomplete.
!
!     Format for vertex-centered Tecplot file (header%fileform = 1):
!
!        VARIABLES = "X", "Y", "Z", "TEMP", "PRESS", "CP", "MACHE", "ASOUNDE", ...
!        ZONE N=96000, E=32000, F=FEPOINT, ET=TRIANGLE
!        0.000000  0.000000 0.000000 2838.386719 51330.925781 1.552663 0.609412 ...
!        0.000883 -0.007150 0.113643 2838.386719 51330.925781 1.552663 0.609412 ...
!        0.000883  0.000000 0.113868 2838.386719 51330.925781 1.552663 0.609412 ...
!        ::::::::::::::::
!        ::::::::::::::::
!        4.882953  0.000000 0.011285 950.867676 16.506409 -0.001166 5.062649 ...
!        1 2 3
!        4 5 6
!        7 8 9
!        10 11 12
!        ::::::::
!        ::::::::
!        95992 95993 95994
!        95995 95996 95997
!        95998 95999 96000
!
!     Format for cell-centered Tecplot file (header%fileform = 2) as from David Boger's overset grid tools:
!
!        TITLE     = ""
!        VARIABLES = "x"
!        "y"
!        "z"
!        "p"
!        "Chm"
!        "h"
!        "qw"
!        "Re_c"
!        ZONE T="ZONE 001"
!         STRANDID=0, SOLUTIONTIME=0
!         Nodes=9367, Elements=18438, ZONETYPE=FETriangle
!         DATAPACKING=BLOCK
!         VARLOCATION=([4-8]=CELLCENTERED)
!         FACENEIGHBORCONNECTIONS=55014
!         FACENEIGHBORMODE=LOCALONETOONE
!         FEFACENEIGHBORSCOMPLETE=YES
!         DT=(SINGLE SINGLE SINGLE SINGLE SINGLE SINGLE SINGLE SINGLE )
!         3.756540120E-01 3.601163924E-01 3.451932967E-01 3.309260905E-01  ...
!        ::::::::::::::::
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)    :: lun     ! Logical unit number
      type (tri_header_type), intent (inout) :: header  ! Data structure containing dataset header information; input with
                                                        ! file name, form, and %nvertices
      type (tri_type),        pointer        :: grid(:) ! Array of derived data types for unstructured data zones, allocated here
      integer,                intent (inout) :: ios     ! 1 on input means write header/zone info. during reading (verbose mode);
                                                        ! 0 on output means no error detected
!     Local constants:

      character (18), parameter :: routine = ' tri_header_read: '

!     Local variables:

      integer :: first, iend, istart, iz, last, lentrim, line, mark, nfileheaderlines, nz
      logical :: double_quotes, names_in_header

!     Execution:

      verbose = ios == 1

      formatted = header%formatted  ! Internal copies
      fileform  = header%fileform
      nvertices = header%nvertices  ! # cell vertices, not zone%nnodes

      if (formatted) then

         open (lun, file=trim (header%filename), status='old', iostat=ios)

      else ! Binary input

         eps = epsilon (eps)

!!       if (eps < 1.e-10) then
!!          IsDouble = 1
!!       else
!!          IsDouble = 0
!!       end if

         if (header%fileform == 1) then
!!          ios = Tec_xxx (...) ! Some utility not available yet in the Tec_io library
            write (*, '(/, 2a)') routine, 'Reading of Tecplot binaries is not an option yet.'
            ios = 999
         end if

      end if

      if (ios /= 0) then
         write (*, '(3a)') routine, 'Trouble opening file ', trim (header%filename)
         go to 999
      end if

      if (formatted) then

!        Read the file header lines up to and including the first 'ZONE' line.
!        Variable names are not assigned here either, because they may not be in the file header; count_zones assigns them.

         call read_file_header () ! Local procedure below

         if (ios /= 0) then
            write (*, '(3a)') routine, 'Trouble reading file header: ', trim (header%filename)
            go to 999
         end if

!        Count the zones, saving dimension records as strings for decoding after the right number of zones has been allocated.
!        If variable names weren't in the file header, they'll be counted from zone 1 and defaulted as X, Y, Z, V1, V2, ...

         call count_zones ()      ! Local procedure below

         if (ios /= 0) then
            write (*, '(3a)') routine, 'Trouble counting zones: ', trim (header%filename)
            go to 999
         end if

      else ! Not implemented yet; what's here applies to PLOT3D files

         read (lun, iostat=ios) nzones

      end if

      if (ios /= 0) then
         write (*, '(2a)') ' Error determining the number of grid zones in ', trim (header%filename)
         go to 999
      end if

      numf        = nvar - 3
      header%numf = numf

      if (verbose) write (*, '(a, i7)') ' # functions:', numf

!     Allocate an array of grid zone derived data types:

      allocate (grid(nzones), stat=ios)

      if (ios /= 0) then
         write (*, '(2a)') routine, 'Error allocating array of grid zones.'
         go to 999
      end if

!     Now we can assign zone dimensions and the numbers of header records to each zone.

      do iz = 1, nzones
         grid(iz)%nnodes           = nnodes(iz)
         grid(iz)%nelements        = nelements(iz)
         grid(iz)%nzoneheaderlines = nzoneheaderlines(iz)
         grid(iz)%solutiontime     = undefined
      end do

      if (verbose) then
         write (*, '(a)') '   zone  # nodes  #elements'
         write (*, '(i7, 2i9)') (iz, nnodes(iz), nelements(iz), iz = 1, nzones)
      end if

!     Also, any dataset auxiliary info. can be reread and stored (auxiliaries not handled though - see Tecplot_io package):

      if (formatted) then

         call reread_header ()  ! Local procedure below

      else ! Not implemented

!!!      read (lun, iostat=ios) (grid(iz)%ni, grid(iz)%nj, grid(iz)%nk, iz = 1, nzones)

!!!      if (ios /= 0) then
!!!         write (*, '(2a, i4)') routine, ' Error rereading the file header.  Unit number:', lun
!!!      end if

      end if

  999 return

!     Local procedures for subroutine tri_header_read, in the order they're used:

      contains

!        ---------------------------
         subroutine read_file_header ()
!        ---------------------------

!        Read lines up to the first zone-related string, looking for optional dataset title and variable names.
!        Return with the file ready to process the first zone header line (already read).

!        Local variables:

         integer :: i, first_local, last_local, mark_local
         logical :: read_a_line

!        Execution:

         header%title      = blank
         names_in_header   = false
         read_a_line       = true
         nfileheaderlines  = 0
         nvar              = 0  ! Recall that the number of variables may have to be found from the first zone DT=(xxxxLE ... )
         istart            = 1  ! See pack_names

         if (header%fileform > 2) then  ! Something other than Tecplot format

!!          call read_dataset_header ()  ! Not implemented yet
            ios = 1
            go to 999

         end if

         do ! While the first token on a line is not 'ZONE'

!!          write (6, '(a, l2, i4)') ' read_file_header: read_a_line, nfileheaderlines =', read_a_line, nfileheaderlines

            if (read_a_line) then
               read (lun, '(a)') buffer
               lentrim = len_trim (buffer);  last = lentrim  ! SCAN2 expects last as input, and can update it
               if (lentrim == 0) then
                  nfileheaderlines = nfileheaderlines + 1
                  cycle  ! Skip a blank line
               end if
               first = 1
            else
               read_a_line = true  ! Because no other keyword is expected on the same file header line
            end if

            call scan2  (buffer(1:lentrim), ' =', first, last, mark)
            call upcase (buffer(first:mark))

!!          write (6, '(a, 3i5, 2a)') ' read_file_header: first, mark, last =', first, mark, last, '  b(f:m): ', buffer(first:mark)

            select case (buffer(first:first))

            case ('T') ! TITLE, which could follow the keyword on the next line

               nfileheaderlines = nfileheaderlines + 1
               first = mark + 2

               if (first > lentrim) then
                  read (lun, '(a)') buffer
                  nfileheaderlines = nfileheaderlines + 1
                  first = 1;  lentrim = len_trim (buffer);  last = lentrim
               end if

               call scan4 (buffer(1:lentrim), quotes, first, last, mark)

               if (mark > 0) header%title = buffer(first:mark)  ! Omit the double quotes

               if (verbose) then
                  if (mark > 0) then
                     write (*, '(1x, 3a)') 'TITLE = "', buffer(first:mark), quotes
                  else
                     write (*, '(1x,  a)') 'TITLE = ""'
                  end if
               end if

            case ('V') ! VARIABLES

               nfileheaderlines = nfileheaderlines + 1
               names_in_header  = true
               double_quotes    = true  ! Maybe
               first = mark + 2

               if (first < lentrim) then   ! More text on this line; could be "X" or just x,y,...

                  i = index (buffer(first:lentrim), quotes)

                  if (i == 0) then ! Simple list of names on same line (as for DPLR's Postflow)
                     double_quotes = false

                     call pack_names ()   ! Ready for transfer to header%varname(*) after that array has been allocated

                     cycle  ! Next input line; no more variables
                  else
                     first = i
                  end if

                  call pack_names ()  ! For 1 or more names on current line

               end if

!              Now we need to read any remaining lines containing double-quoted variables.

               do ! Until another header keyword or ZONE is encountered

                  read (lun, '(a)') buffer
                  first = 1;  lentrim = len_trim (buffer);  last = lentrim

                  call scan2 (buffer(1:lentrim), ' =', first, last, mark)

                  if (buffer(first:first) == quotes) then
                     nfileheaderlines = nfileheaderlines + 1

                     call pack_names ()

                  else ! No more variables

                     read_a_line = false
                     exit

                  end if

               end do

            case ('#') ! Comment - skip it

               nfileheaderlines = nfileheaderlines + 1

            case ('Z') ! ZONE means end of file header lines, with first zone line already read

               exit

            case default ! Unknown keyword

               nfileheaderlines = nfileheaderlines + 1
               write (*, '(3a)') ' *** Unknown file header keyword: ', buffer(first:mark), '.  Proceeding.'

            end select

         end do ! Next file header line


!        Unpack the variable names if they've been found in the header:

         if (nvar > 0) then  ! Else they're counted and set up from the first DT = (... ) record in count_zones

            allocate (header%varname(nvar))

            first_local = 1;  last_local = iend - 1 ! See pack_names

            do i = 1, nvar

               call scan4 (packed_names, quotes, first_local, last_local, mark_local)

               header%varname(i) = packed_names(first_local:mark_local)
               first_local = mark_local + 2
            end do

            if (verbose) then
               write (*, '(a, i4)') ' # variables found, including (x,y,z):', nvar
               write (*, '(a, (10(3x, a)))') ' Variable names:', (trim (header%varname(i)), i = 1, nvar)
            end if

         end if

         ios = 0

 999     return

         end subroutine read_file_header

!        ---------------------
         subroutine pack_names ()  ! Transfer names from buffer to next portion (istart) of packed_names
!        ---------------------

!        Allowing for embedded blanks requires (new) scan4; the standard scan2 won't work.
!        The packed names are returned like this:  "X, m" "Y, m" "Z, m", "T, K" ...

         mark = 0

         do ! Until mark = 0

            if (double_quotes) then
               call scan4 (buffer, quotes, first, last, mark)
            else
               call scan2 (buffer,  '=, ', first, last, mark)
            end if

            if (mark == 0) exit

            nvar = nvar + 1

            packed_names(istart:istart) = quotes
            istart = istart + 1
            iend = istart + mark - first
            packed_names(istart:iend) = buffer(first:mark)
            iend = iend + 1
            packed_names(iend:iend) = quotes
            iend = iend + 1
            packed_names(iend:iend) = blank
            istart = iend + 1
            first  = mark + 2

         end do

         end subroutine pack_names

!        -----------------------
         subroutine count_zones ()  ! Count the zones in a file of unstructured data; save zone dimensions in a string array.
!        -----------------------

!        Any file header records have been read.  The first line of the first zone header is in the buffer.
!        If the number of variables is not known from names in the file header, count them from the first zone.
!
!        Some programming considerations:
!
!        The case statement can't easily work with more than the first character of a keyword.
!        Using IF ... THEN ... ELSE ... would allow strings with different lengths to be compared, but is eschewed nonetheless.
!        Trapping of unknown keywords requires precise matches (after upcasing).
!
!        Local variables:

         integer :: i

!        Execution:

         line = nfileheaderlines + 1;  nz = 1;  nzoneheaderlines(1) = 1

!        Always (re)start the loop over possible keywords with a keyword in hand, as when read_file_header is done.
!        The default case (first numerical value of zonal data proper) necessarily reads on until a non-numeric token (or EOF)
!        is found, so all other cases must do likewise.

         do ! Until the numeric case encounters EOF and exits; allow for more than one keyword and value on a line

!!          write (6, '(a, 6i9)') 'count_zones: nz, line, first, mark, last, lentrim =', nz, line, first, mark, last, lentrim
!!          write (6, '(a, i5, 2a)') 'Zone:', nz, '  keyword: ', buffer(first:mark)

            select case (buffer(first:first))

            case ('Z')  ! ZONE or ZONETYPE

               if (mark - first == 3) then ! ZONE (start of a new zone);  zone # is incremented after reading data proper

                  if (buffer(first:mark) == 'ZONE') then
                  else
                     call unknown_keyword ()
                  end if

               else if (mark - first == 7) then ! ZONETYPE

                  if (buffer(first:mark) == 'ZONETYPE') then  ! The application will know if it's FETriangle or FETet...
                     call next_token ()  ! Skip the value
                  else
                     call unknown_keyword ()
                  end if

               else
                  call unknown_keyword ()
               end if

               call next_token ()

            case ('T')  ! Title keyword for this zone; its value may have embedded blanks; assume it's on the same line as T

               first = mark + 2

               call scan4 (buffer(1:lentrim), quotes, first, last, mark)

               if (mark < 0) mark = -mark  ! Scan4 signals a null token this way

               call next_token ()

            case ('D')  ! Data types or DATAPACKING

               if (mark - first == 1) then  ! DT = (....LE ....LE ...LE )

                  if (buffer(first:mark) == 'DT') then

                     call scan4 (buffer(1:lentrim), '(', first, last, mark)

                     if (mark <= first) then
                        write (*, '(/, a, 2i5)') &
                           ' Missing '')''. triangulation_io.f90 limit exceeded? lentrim, len_buffer: ', lentrim, len_buffer
                        ios = -len_buffer
                        go to 999
                     end if

                     if (nz == 1) then

                        if (.not. names_in_header) then  ! Default the variable names to "X", "Y", "Z", "V1", "V2", ...

                           do i = first, mark
                              if (buffer(i:i) == 'E' .or. buffer(i:i) == 'e') nvar = nvar + 1 ! Works for SINGLE or DOUBLE
                           end do

                           allocate (header%varname(nvar))

                           header%varname(1) = 'X';  header%varname(2) = 'Y';  header%varname(3) = 'Z'

                           do i = 4, nvar
                              header%varname(i) = blank
                              numf = i - 3
                              if (numf < 10) then
                                 write (header%varname(i)(1:2), '(a1, i1)') 'V', numf
                              else ! Assume no more than 99 variables
                                 write (header%varname(i)(1:3), '(a1, i2)') 'V', numf
                              end if
                           end do

                           if (verbose) write (*, '(a, i4)') ' # variables found apart from (x,y,z):', numf

                        end if

                     end if

                  else
                     call unknown_keyword ()
                  end if

               else ! DATAPACKING

                  valid = false
                  if (mark - first == 10) valid = buffer(first:mark) == 'DATAPACKING'
!!                if (mark - first ==  0) valid = buffer(first:mark) == 'F'  ! "Form" keyword applies only to structured data (?)

                  if (valid) then

                     call next_token ()

                     if (nz == 1) then
                        header%datapacking = 0   ! POINT
                        if (buffer(first:mark) == 'BLOCK') header%datapacking = 1
                     end if

                  else
                     call unknown_keyword ()
                  end if

               end if

               call next_token ()

            case ('E')  ! E[LEMENTS] = # elements or ET = Element type

               valid = mark == first
               if (.not. valid) valid = mark - first == 7 .and. buffer(first:mark) == 'ELEMENTS'

               if (valid) then
                  call next_token ()
                  call char_to_integer (buffer, first, mark, nelements(nz))
               else

                  valid = false
                  if (mark - first == 1) valid = buffer(first:mark) == 'ET'  ! Element type

                  if (valid) then
                     call next_token ()  ! Skip it - can't save it till the right # zones has been allocated
                  else
                     call unknown_keyword ()
                  end if

               end if

               call next_token ()

            case ('F')  ! F = Form?  FEBLOCK | FEPOINT seem to be alternatives to DATAPACKING = BLOCK | POINT

               if (mark == first) then  ! F = Form
                  call next_token ()
                  valid = false
                  if (mark - first == 6) then
                     if (buffer(first:mark) == 'FEBLOCK') then
                        if (nz == 1) header%datapacking = 1
                        valid = true
                     else if  (buffer(first:mark) == 'FEPOINT') then
                        if (nz == 1) header%datapacking = 0
                        valid = true
                     end if
                  end if
                  if (.not. valid) write (*, '(3a)') ' *** Unknown value for keyword F[orm]: ', buffer(first:mark), '.  Proceeding.'
               else
                  call unknown_keyword ()
               end if

               call next_token ()

            case ('N')  ! N[ODES] = # nodes

               if (mark == first .or. (mark - first == 4 .and. buffer(first:mark) == 'NODES')) then

                  call next_token ()
                  call char_to_integer (buffer, first, mark, nnodes(nz))

               else
                  call unknown_keyword ()
               end if

               call next_token ()

            case ('S')  ! SOLUTIONTIME = xxx

               if (mark - first == 11) then

                  if (buffer(first:mark) == 'SOLUTIONTIME') then
                     call next_token ()
!!!                  call char_to_real (buffer, first, mark), grid(nz)%solutiontime)  ! Can't do it till all zones are allocated
                  else
                     call unknown_keyword ()
                  end if

               else
                  call unknown_keyword ()
               end if

               call next_token ()

            case ('V')  ! VARLOCATION = ...  ! Ignore it and the rest of its line, to avoid parsing ([4-8]=CELLCENTERED)

               if (mark - first == 10) then

                  if (buffer(first:mark) == 'VARLOCATION') then
                     write (*, '(3a)') ' *** Ignoring nonstandard keyword and value: ', buffer(first:last), '.  Proceeding.'
                     mark = last  ! Force new line
                  else
                     call unknown_keyword ()
                  end if

               else
                  call unknown_keyword ()
               end if

               call next_token ()

            case ('#') ! Comment - skip it

               first = mark;  last = 0;  lentrim = 0  ! Force a new line to be read

               call next_token ()

            case default ! Must be data proper for current zone (or an unknown keyword such as STRANDID):

               if (.not. number (buffer(first:mark))) then ! Non-numeric token must be an unknown keyword

                  call unknown_keyword ()  ! Ignore it, and skip its value
                  call next_token ()

               else ! A numeric token - we're through with this zone header

                  nzoneheaderlines(nz) = nzoneheaderlines(nz) - 1

                  do ! Until EOF or another zone is encountered, skip the data

                     read (lun, '(a)', iostat=ios) buffer

                     if (ios < 0) exit  ! Or go to 999 directly

                     line = line + 1

                     i = index (buffer(1:4), 'Z')

                     if (i == 0) i = index (buffer(1:4), 'z') ! Assume no leading blanks, or just a few

                     if (i  > 0) exit

                  end do

                  if (ios < 0) exit  ! EOF

!                 Prepare for the next zone:

                  first = i;  mark = i + 3;  lentrim = len_trim (buffer);  last = lentrim

                  call upcase (buffer(first:mark))

                  nz = nz + 1

                  if (nz > max_zones) then
                     nz  = max_zones
                     write (*, '(4a, i6)') routine, 'Too many zones in file ', trim (header%filename), '.  Limit:', max_zones
                     exit
                  end if

                  nzoneheaderlines(nz) = 1  ! Ready for incrementing

               end if

            end select

         end do  ! Process next keyword

  999    continue

         nzones        = nz
         header%nzones = nz
         if (ios /= -len_buffer) ios = 0  ! See case 'D' above

         if (verbose) then
            write (*, '(a, i5)') ' # zones found:', nz, ' # variables:  ', nvar
            if (nz == 1) write (*, '(a, i9)') ' # nodes:   ', nnodes(1), ' # elements:', nelements(1)
         end if

         end subroutine count_zones

!        ---------------------
         subroutine next_token ()  ! Intended for processing zone headers only.  It spans input lines if necessary.
!        ---------------------

!        Use this if converting to upper case is appropriate (not for zone titles).
!        Global variables first, last, lentrim, and mark are assumed on input to apply to the previous token.
!        Variable "nz" points to the current zone.  Variable "line" refers to the entire file (for error messages only).
!        Upon return, the next token is in buffer(first:mark), in upper case.
!        EOF is NOT considered a possibility here.

         integer :: first_local, last_local, mark_local

         first = mark + 2

         if (first > last) then

            lentrim = 0
            do while (lentrim == 0)  ! Skip any blank lines
               read (lun, '(a)') buffer
               line = line + 1;  nzoneheaderlines(nz) = nzoneheaderlines(nz) + 1
               lentrim = len_trim (buffer)
            end do

            first = 1;  last = lentrim

            if (verbose) then  ! Avoid echoing the first data line of each zone
               first_local = 1;  last_local = lentrim
               call scan2 (buffer(1:lentrim), blank, first_local, last_local, mark_local)
               if (.not. number (buffer(first_local:mark_local))) write (*, '(a)') buffer(1:lentrim)
            end if

         end if

         call scan2  (buffer(1:lentrim), ' =,', first, last, mark)
         call upcase (buffer(first:mark))

         end subroutine next_token

!        --------------------------
         subroutine unknown_keyword ()
!        --------------------------

         write (*, '(3a)') ' *** Unknown keyword: ', buffer(first:mark), '.  Proceeding.'

         call next_token () ! Get the value presumably associated with the unknown keyword, and ignore it

         end subroutine unknown_keyword

!        --------------------------
         subroutine char_to_integer (text, i1, i2, number)  ! Internal read from text(i1:i2) to integer number
!        --------------------------

         character (*), intent (in)  :: text
         integer,       intent (in)  :: i1, i2
         integer,       intent (out) :: number

         character (4) :: format_string

         format_string = '(i?)'
         write (format_string(3:3), '(i1)') i2 - i1 + 1
         read  (text(i1:i2), format_string) number

         end subroutine char_to_integer

!        ------------------------
         subroutine reread_header ()  ! Leave the file ready to read the first zone.  (Tecplot_io stores auxiliary data here too.)
!        ------------------------

         integer :: line

         rewind (lun)

         if (verbose) write (*, '(/, a, /)') ' Rereading input file header:'

         do line = 1, nfileheaderlines

            read (lun, '(a)') buffer
            if (verbose) write (*, '(a)') trim (buffer)

         end do

         end subroutine reread_header

      end subroutine tri_header_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine tri_header_write (lun, header, grid, ios)
!
!     Open a file for output of 3-space unstructured data and write the file header and zone header records.
!
!     Writing of binary files is incomplete.
!
!     Format for vertex-centered Tecplot file (header%fileform = 1):
!
!        TITLE = "Case xxx"
!        VARIABLES =
!        "x, m"
!        "y, m"
!        "z, m"
!        "T, K"
!        ZONE T="Zone yyy"
!           Nodes = 561, Elements = 1024
!           F=FEPOINT, ET=TRIANGLE
!           0.0000000E+00   0.0000000E+00   1.0000000E+00   1.2345678E+03     ! x, y, z, f1, f2 for vertex 1
!           4.9067674E-02   0.0000000E+00   9.9879546E-01   1.2356789E+03     ! :  :  :  :  :  :  :  :  :  2
!           0.0000000E+00   4.9067674E-02   9.9879546E-01   1.2678901E+03
!            :               :               :               :
!           0.0000000E+00   1.0000000E+00   0.0000000E+00   9.9876543E+02     ! :  :  :  :  :  :  :  :  :  561
!             1     2     3                                                   ! Vertex pointers for element 1
!             2     4     5
!             5     3     2
!             :     :     :
!           527   559   560
!           560   528   527
!           528   560   561                                                   ! Vertex pointers for element 1024
!
!     Format for cell-centered Tecplot file (header%fileform = 2):
!
!        TITLE = "Case xxx"
!        VARIABLES =
!        "x, m"
!        "y, m"
!        "z, m"
!        "Area, m^2"
!        "Solid angle, sr"
!        ZONE T="Zone yyy"
!           Nodes = 561, Elements = 1024
!           ZONETYPE=FETriangle
!           DATAPACKING=BLOCK
!           VARLOCATION=([4-5]=CELLCENTERED)
!           0.0000000E+00   4.9067674E-02   0.0000000E+00   9.8017140E-02   6.9308585E-02     ! All x, then all y, then z (vertices)
!           0.0000000E+00   1.4673047E-01   1.2707232E-01   7.3365237E-02   0.0000000E+00     ! followed by all f1 then all f2 at
!           1.9509032E-01   1.8023996E-01   1.3794969E-01   7.4657834E-02   0.0000000E+00     ! element centers
!            :               :               :               :               :
!           1.2038183E-03   1.2411699E-03   1.2038183E-03                                     ! Last cell-centered values of f2
!             1     2     3                                                                   ! Same connectivity data as above
!             2     4     5
!             5     3     2
!             :     :     :
!           527   559   560
!           560   528   527
!           528   560   561

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)  :: lun      ! Logical unit number
      type (tri_header_type), intent (in)  :: header   ! Data structure containing dataset header information
      type (tri_type),        pointer      :: grid(:)  ! Array of derived data types for unstructured data zones
      integer,                intent (out) :: ios      ! 0 on output means no error detected

!     Local constants:

      character (19), parameter :: routine = ' tri_header_write: '

!     Local variables:

      integer :: ivar

!     Execution:

      formatted = header%formatted  ! Internal copies
      fileform  = header%fileform
      nvertices = header%nvertices  ! Per cell
      numf      = header%numf

      if (formatted) then
         open (lun, file=trim (header%filename), status='unknown', iostat=ios)
      else
         write (*, '(/, a)') ' Writing of Tecplot binaries is not an option yet.'
         ios = 999
      end if

      if (ios /= 0) then
         write (*, '(3a)') routine, 'Trouble opening file ', trim (header%filename)
         go to 999
      end if

      if (formatted) then
         write (lun, '(3a)') &
            'TITLE = "', trim (header%title), '"',                 &
            'VARIABLES', ' ', '=',                                 &  ! Kludge to do it in one write
            ('"', trim (header%varname(ivar)), '"', ivar = 1, 3 + numf)
      else
         ! Binary writes haven't been implemented yet
      end if

  999 continue

      end subroutine tri_header_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine tri_zone_allocate (header, zone, ios)
!
!     Allocate the x, y, z and optional f arrays and the connectivity array for one zone.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (in)    :: header  ! Dataset header with fileform
      type (tri_type),        intent (inout) :: zone
      integer,                intent (out)   :: ios

!     Local constants:

      character (32), parameter :: routine_etc = ' tri_zone_allocate trouble with '

!     Local variables:

      integer :: nelements, nfsets, nnodes

!     Execution:

      nnodes    = zone%nnodes
      nelements = zone%nelements

      allocate (zone%xyz(3,nnodes), stat=ios);  zone%allocated_xyz = true

      if (ios /= 0) then
         write (*, '(2a)') routine_etc, 'x, y, z.'
         go to 999
      end if

      if (header%fileform == 1) then  ! Vertex-centered
         nfsets = nnodes
      else
         nfsets = nelements           ! Cell-centered
      end if

      numf = header%numf

      if (numf > 0) then

         allocate (zone%f(numf,nfsets), stat=ios);  zone%allocated_f = true

      else ! Avoid undefined arguments elsewhere

         allocate (zone%f(1,1), stat=ios);  zone%allocated_f = true

      end if

      if (ios /= 0) then
         write (*, '(2a, i4, i9)') routine_etc, 'f array.  # functions, # sets:', numf, nfsets
         go to 999
      end if

      nvertices = header%nvertices

      allocate (zone%conn(nvertices,nelements), stat=ios);  zone%allocated_conn = true

      if (ios /= 0) then
         write (*, '(2a, i4, i9)') routine_etc, 'connectivity array.  # vertices, # elements:', nvertices, nelements
         go to 999
      end if

      zone%solutiontime = undefined

      zone%allocated_area     = false
      zone%allocated_volume   = false
      zone%allocated_centroid = false

  999 if (ios /= 0) write (*, '(a, 2i8, 2i4)') '  nnodes, nelements, numf, nvertices:', nnodes, nelements, numf, nvertices

      end subroutine tri_zone_allocate

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine tri_zone_read (lun, header, zone, ios)
!
!     Read one 3-space zone of unstructured data from a file (ASCII, POINT or BLOCK packing order).
!     Binary reads have yet to be implemented.
!     The zone dimensions have already been determined as part of reading the file header, and x/y/z/f/iconn arrays for this zone
!     should have been allocated via tri_zone_allocate.
!     In the case of Tecplot files, the file is presumed to be positioned ready to read a 'zone' keyword as the first token.
!
!     The zone keywords can be in any order, possibly with a few leading blanks or blank lines.
!     Since tri_header_read has determined the number of lines per zone header, the logic is slightly different from that for
!     the count_zones procedure.  The loop over keywords here starts with finding a keyword as opposed to already having
!     encountered one, because we don't want to buffer in the first line of numeric data when reparsing the zone header.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)    :: lun     ! Logical unit number
      type (tri_header_type), intent (inout) :: header  ! Dataset header with nzones, etc.
      type (tri_type),        intent (inout) :: zone    ! Zone to be read, with %nnodes, %nelements set & other fields allocated
      integer,                intent (out)   :: ios     ! 0 = no error

!     Local variables:

      integer   :: first, last, lentrim, line, mark  ! Shared by internal procedures
      integer   :: i, n, nelements, nnodes

!     Execution:

      nnodes    = zone%nnodes
      nelements = zone%nelements
      formatted = header%formatted
      numf      = header%numf

      if (formatted) then

         call read_zone_header ()

      else

!        Not implemented

      end if

!     Read the numeric data for this zone:

      select case (header%datapacking)

         case (0) ! POINT; any functions must be vertex-centered

            if (formatted) then

               if (numf == 0) then
                  read (lun, *, iostat=ios) (zone%xyz(:,i), i = 1, nnodes)  ! Or just zone%xyz
               else
                  read (lun, *, iostat=ios) (zone%xyz(:,i), zone%f(:,i), i = 1, nnodes)
               end if

               if (ios /= 0) then
                  write (*, '(/, a, i4, a, i9)') ' Trouble reading data in POINT order.  Logical unit:', lun, '  # nodes:', nnodes
                  go to 99
               end if

               read (lun, *, iostat=ios) zone%conn
               if (ios /= 0) then
                  write (*, '(/, a, i4, a, i9)') &
                     ' Trouble reading point order connectivity data. Unit:', lun, '  # elements:', nelements
                  write (*, '(a, 2i9)') ' Zone connectivity dimensions: ', size (zone%conn, 1), size (zone%conn, 2)
                  go to 99
               end if

            else ! Not implemented yet
            end if

         case (1) ! BLOCK

            if (formatted) then

               if (numf == 0) then
                  read (lun, *, iostat=ios) zone%xyz(1,:), zone%xyz(2,:), zone%xyz(3,:)
               else
                  read (lun, *, iostat=ios) zone%xyz(1,:), zone%xyz(2,:), zone%xyz(3,:), (zone%f(n,:), n = 1, numf)
               end if

               if (ios /= 0) then
                  write (*, '(/, a, 3i4, a, i9)') &
                     ' Trouble reading data in BLOCK order.  numf, var # and lun:', numf, n, lun, '  # nodes:', nnodes
                  go to 99
               end if

               read (lun, *, iostat=ios) zone%conn
               if (ios /= 0) then
                  write (*, '(/, a, i4, a, i9)') &
                     ' Trouble reading block order connectivity data. Unit:', lun, '  # elements:', nelements
                  write (*, '(a, 2i9)') ' Zone connectivity dimensions: ', size (zone%conn, 1), size (zone%conn, 2)
                  go to 99
               end if

            else ! Not implemented yet
            end if

         case default

            ios = 1

      end select

   99 return

!     Local procedures for subroutine tri_zone_read:

      contains

!        ------------------------------
         subroutine read_zone_header ()  ! Read the current zone header with known number of header lines
!        ------------------------------

!        Execution:

         line = 0;  mark = 0;  last = 0

!        Always (re)start the loop over possible keywords by locating the next keyword if any (in contrast to count_zones).

         do ! Until all header lines for this zone have been fully processed - see next_zone_token.

            call next_zone_token ()

            select case (buffer(first:first))

            case ('Z')  ! ZONE or ZONETYPE

               if (mark - first == 3) then ! ZONE (start of a new zone);  zone # is incremented after reading data proper

                  if (buffer(first:mark) == 'ZONE') then
!                    Nothing to do
                  else  ! Unknown keyword: ignore it, and skip its value as well
                     call next_zone_token ()
                  end if

               else  ! ZONETYPE is assumed to be known to the application (triangles or tets)

                  call next_zone_token ()  ! Skip the FETxxx value;  same action if it's an unknown keyword

               end if

            case ('T')  ! Title keyword for this zone; its value may have embedded blanks; assume it's on the same line as T

               if (first == mark) then

                  first = mark + 2;  call scan4 (buffer(1:lentrim), quotes, first, last, mark)

                  if (mark < 0) then ! Blank title signaled with ""
                     mark = -mark
                     zone%zone_title = blank
                  else
                     zone%zone_title = buffer(first:mark)
                  end if

               else  ! Unknown keyword - ignore it, and skip its value as well
                  call next_zone_token ()
               end if

            case ('D')  ! Data types or DATAPACKING

               if (mark - first == 1) then  ! DT = (....LE ....LE ...LE )

                  if (buffer(first:mark) == 'DT') then

                     call scan4 (buffer(1:lentrim), '(', first, last, mark)

                  else  ! Unknown keyword and value to ignore
                     call next_zone_token ()
                  end if

               else  ! DATAPACKING

                  call next_zone_token ()  ! BLOCK or POINT is already known;  same action for an unknown keyword

               end if

            case ('E', 'N')  ! E = # elements (known), ET = Element type, or END (see next_zone_token); N = # nodes (known)

               if (mark - first >= 1) then
                  if (buffer(first:mark) == 'ET') then
                     if (nvertices == 3) then
                        zone%element_type = 'TRIANGLE'
                     else if (nvertices == 4) then
                        zone%element_type = 'TET'
                     else if (nvertices == 8) then
                        zone%element_type = 'BRICK'
                     end if
                  end if
               end if
               if (mark - first == 2) then
                  if (buffer(first:mark) == 'END') exit  ! Done with this zone header
               else
                  call next_zone_token ()  ! Same action for an unknown keyword
               end if

            case ('S')  ! SOLUTIONTIME = xxx

               if (mark - first == 11) then
                  if (buffer(first:mark) == 'SOLUTIONTIME') then
                     call next_zone_token ()
                     call char_to_real (buffer, first, mark, zone%solutiontime)
                  else
                     call next_zone_token ()  ! Unknown keyword - ignore it, and skip its value
                  end if
               else
                  call next_zone_token ()  ! Unknown keyword - ignore it, and skip its value
               end if

            case default ! Must be an unknown keyword such as STRANDID:

               call next_zone_token ()  ! Get and skip its value and keep going

            end select

         end do  ! Process next keyword

         end subroutine read_zone_header

!        --------------------------
         subroutine next_zone_token ()  ! This is a variation of "next_token" used by count_zones
!        --------------------------

!        Use this if converting to upper case is appropriate (not for zone titles).
!        Global variables first, last, lentrim, and mark are assumed on input to apply to the previous token.
!        Upon return, the next token is in buffer(first:mark), in upper case.
!        It may have been fudged as 'END' if the known number of header lines has been processed.
!        EOF is NOT considered a possibility here.

         first = mark + 2

!!       write (6, '(a, 6i6)') ' next_zone_token: nzh, line, first, mark, last, lentrim:', &
!!                              zone%nzoneheaderlines, line, first, mark, last, lentrim

         if (first > last) then

            if (line < zone%nzoneheaderlines) then  ! Get a new zone header line

               lentrim = 0

               do while (lentrim == 0)  ! Skip any blank lines
                  read (lun, '(a)') buffer
                  line = line + 1
                  lentrim = len_trim (buffer)
                  if (line == zone%nzoneheaderlines) exit
               end do

               first = 1;  last = lentrim  ! Handling a blank last zone header line is awkward

            end if

            if (line == zone%nzoneheaderlines .and. first > last) then  ! Done with this zone header

               buffer(1:3) = 'END'
               first = 1;  mark = 3;  last = 0

            end if

         end if

         if (first <= last) then

            call scan2  (buffer(1:lentrim), ' =,', first, last, mark)
            call upcase (buffer(first:mark))

         end if

         end subroutine next_zone_token

!        -----------------------
         subroutine char_to_real (text, i1, i2, real_number)  ! Internal read from text(i1:i2) to real number
!        -----------------------

         character (*), intent (in)  :: text
         integer,       intent (in)  :: i1, i2
         real,          intent (out) :: real_number

         integer       :: n
         character (7) :: format_string

         format_string = '(???.0)'
         n = i2 - i1 + 1
         if (n < 10) then
            format_string(2:3) = ' f';  write (format_string(4:4), '(i1)') n
         else ! n < 100
            format_string(2:2) = 'f';   write (format_string(3:4), '(i2)') n
         end if
         read  (text(i1:i2), format_string) real_number

         end subroutine char_to_real

      end subroutine tri_zone_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine tri_zone_write (lun, header, zone, ios)
!
!     Write one 3-space zone of unstructured data to a file (ASCII, POINT or BLOCK packing order).
!     Binary writes have yet to be implemented.
!     The file is presumed to be positioned ready to write a 'ZONE T(itle) =' line.
!     Function values may or may not accompany the x,y,z coordinates.
!     This routine should apply to unstructured volume zones as well as triangulated zones.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)  :: lun     ! Logical unit number
      type (tri_header_type), intent (in)  :: header  ! Dataset header with nzones, etc.
      type (tri_type),        intent (in)  :: zone    ! Zone to be written
      integer,                intent (out) :: ios     ! 0 = no error

!     Local variables:

      integer              :: in, iv, lc, le, ln, nelements, nnodes
      character (14), save :: form1    = '(a, i*, a, i*)'
      character (11), save :: form2    = '(***es16.8)'
      character (5),  save :: form3    = '(*i*)'
      character (6),  save :: centered = '[4-*] '

!     Execution:

      numf       = header%numf
      nvar       = 3 + numf
      formatted  = header%formatted
      fileform   = header%fileform
      nvertices  = header%nvertices
      nnodes     = zone%nnodes
      nelements  = zone%nelements

      if (formatted) then
         write (lun, '(3a)') 'ZONE T = "', trim (zone%zone_title), '"'
         call ndigits (nnodes, ln);       write (form1(6:6),   '(i1)') ln
         call ndigits (nelements, le);    write (form1(13:13), '(i1)') le
         write (lun, form1) 'Nodes = ', nnodes, ', Elements = ', nelements

         select case (fileform)

            case (1)  ! Vertex-centered functions, if any

               write (lun, '(2a)') 'F=FEPOINT, ET=', trim (zone%element_type)
               if (numf == 0) then
                   write (lun, '(3es16.8)') zone%xyz(:,:)
               else
                  write (form2(2:4), '(i3)') nvar
                  write (lun, form2) (zone%xyz(:,in), zone%f(:,in), in = 1, nnodes)
               end if

            case (2)  ! Cell-centered functions: surfaces only, for now

               write (lun, '(a)') 'ZONETYPE=FETriangle', &
                                  'DATAPACKING=BLOCK'
               if (nvar < 10) then
                  lc = 5
                  write (centered(4:4), '(i1)') nvar
               else
                  lc = 6
                  write (centered(4:5), '(i2)') nvar;  centered(6:6) = ']'
               end if
               if (numf > 1) then
                  write (lun, '(3a)') 'VARLOCATION=(', centered(1:lc), '=CELLCENTERED)'
               else  ! For a single function, [4-4] is not allowed -- just [4]
                  write (lun, '(a)') 'VARLOCATION=([4]=CELLCENTERED)'
               end if
               write (lun, '(5es16.8)') (zone%xyz(iv,1:nnodes),  iv = 1, nvertices)
               write (lun, '(5es16.8)') (zone%f(iv,1:nelements), iv = 1, numf)

         end select

         write (form3(2:2), '(i1)') nvertices
         write (form3(4:4), '(i1)') le + 1    ! Assume nelements < 100,000,000
         write (lun, form3) zone%conn(:,:)

      else
         ! Binary output has yet to be implemented
      end if

      ios = 0

      end subroutine tri_zone_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine deallocate_tri_zones (iz1, iz2, numf, grid, ios)

!     Deallocate the indicated zones.

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)  :: iz1, iz2             ! Zone range to deallocate
      integer, intent (in)  :: numf                 ! > 0 means deallocate %f too; actually, %allocated_f is preferable now
      type (tri_type), intent (inout) :: grid(iz2)  ! At least this many
      integer, intent (out) :: ios                  ! 0 means no problem

!     Local variables:

      integer :: iz

!     Execution:

      do iz = iz1, iz2

         if (grid(iz)%allocated_xyz) then
             deallocate (grid(iz)%xyz, stat=ios);       grid(iz)%allocated_xyz = false
             if (ios /= 0) go to 90
         end if

         if (grid(iz)%allocated_f) then
            deallocate (grid(iz)%f, stat=ios);          grid(iz)%allocated_f = false
            if (ios /= 0) go to 90
         end if

         if (grid(iz)%allocated_conn) then
             deallocate (grid(iz)%conn, stat=ios);      grid(iz)%allocated_conn = false
             if (ios /= 0) go to 90
         end if

         if (grid(iz)%allocated_area) then
             deallocate (grid(iz)%area, stat=ios);      grid(iz)%allocated_area = false
             if (ios /= 0) go to 90
         end if

         if (grid(iz)%allocated_volume) then
             deallocate (grid(iz)%volume, stat=ios);    grid(iz)%allocated_volume = false
             if (ios /= 0) go to 90
         end if

         if (grid(iz)%allocated_centroid) then
             deallocate (grid(iz)%centroid, stat=ios);  grid(iz)%allocated_centroid = false
             if (ios /= 0) go to 90
         end if

      end do

      go to 99

   90 write (*, '(/, a, 3i5)') ' Trouble deallocating tri_type variable. iz1, iz2, nf: ', iz1, iz2, numf

   99 return

      end subroutine deallocate_tri_zones

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_data_range (header, grid)

!     For the given surface triangulation, compute the x/y/z data ranges over all zones, which are assumed to be read already.
!     This could be used to set interior_point(:) for enclosed volume calculations.  In fact, as a convenience, interior_point(:)
!     is returned as the average of xmin & xmax, etc.
!
!     The data range calculations are applicable to a tetrahedral volume grid as well.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data

!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%xmin = grid(1)%xyz(1,1);  header%xmax = header%xmin
      header%ymin = grid(1)%xyz(2,1);  header%ymax = header%ymin
      header%zmin = grid(1)%xyz(3,1);  header%zmax = header%zmin

      do iz = 1, header%nzones

         call tri_zone_data_range (grid(iz))

         header%xmin = min (header%xmin, grid(iz)%xmin);  header%xmax = max (header%xmax, grid(iz)%xmax)
         header%ymin = min (header%ymin, grid(iz)%ymin);  header%ymax = max (header%ymax, grid(iz)%ymax)
         header%zmin = min (header%zmin, grid(iz)%zmin);  header%zmax = max (header%zmax, grid(iz)%zmax)
      end do

      header%interior_point(1) = half*(header%xmin + header%xmax)  ! Reasonable default for enclosed volume calculations
      header%interior_point(2) = half*(header%ymin + header%ymax)
      header%interior_point(3) = half*(header%zmin + header%zmax)

      end subroutine tri_data_range

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_area (header, grid)

!     For the given surface triangulation, compute the total surface area over all zones, which are assumed to be read already.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data

!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%surface_area = zero

      do iz = 1, header%nzones

         call tri_zone_area (grid(iz))

         header%surface_area = header%surface_area + grid(iz)%surface_area
      end do

      end subroutine tri_area

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_volume (header, grid)

!     For the given surface triangulation and interior_point(:), compute the total volume over all zones, which are assumed to be
!     read already.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data

!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%surface_area    = zero
      header%enclosed_volume = zero

      do iz = 1, header%nzones

         call tri_zone_volume (header, grid(iz))

         header%surface_area    = header%surface_area    + grid(iz)%surface_area
         header%enclosed_volume = header%enclosed_volume + grid(iz)%enclosed_volume
      end do

      end subroutine tri_volume

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_center_of_mass (header, grid)

!     For the given surface triangulation, assuming constant unit areal density, compute the overall center of mass.
!     This involves computing and storing, for each zone, all the cell centroids and surface areas (as might be needed for
!     moments of inertia calculations).  The total area for all zones is a by-product along with the total for each zone.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured surface zones containing x,y,z and conn data;
                                                         ! zone CM and cell centroids and areas are stored upon return, along
                                                         ! with the overall CM
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%surface_area = zero
      header%CM(:)        = zero

      do iz = 1, header%nzones

         call tri_zone_center_of_mass (grid(iz))         ! Also allocates and stores cell centroids and areas, and sums cell areas

         header%surface_area = header%surface_area + grid(iz)%surface_area
         header%CM(:)        = header%CM(:)        + grid(iz)%surface_area * grid(iz)%cm(:)
         write (*, '(a, i3, es16.8, 3x, 3es16.8)') '   zone, area, CM(1:3):', iz, grid(iz)%surface_area, grid(iz)%cm(:)
      end do

      header%CM(:) = header%CM(:) / header%surface_area
      write (*, '(a, es16.8, 3x, 3es16.8)') '   total area, CM(1:3):   ', header%surface_area, header%CM(:)

      end subroutine tri_center_of_mass

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_moments_of_inertia (header, grid)

!     For the given surface triangulation, assuming constant unit areal density, compute the overall moments of inertia about
!     Ox, Oy, Oz along with the rotation matrix corresponding to the principal axes.  Centers of mass, etc., are computed here
!     as an initial part of the inertia calculations.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data;
                                                         ! zone CM and cell centroids and areas are stored upon return, along
                                                         ! with the overall CM and the moments of inertia and associated rotation
!     Local variables:                                   ! matrix

      integer :: i, ier, itri, iz
      real    :: area, x, y, z, xx, yy, zz, xy, yz, zx
      real    :: fv1(3), fv2(3)                          ! Work-space for eigen routine
      real    :: A(3,3), CM(3)                           ! Inertia matrix to be diagonalized to determine the principal axes;
                                                         ! CM(:) is just a copy of the header center of mass coordinates
!     Execution:
!     ----------

      call tri_center_of_mass (header, grid)             ! Includes allocating and storing all cell centroids and areas

      CM(:) = header%CM(:)
      xx = zero;  yy = zero;  zz = zero
      xy = zero;  yz = zero;  zx = zero

      do iz = 1, header%nzones
         do itri = 1, grid(iz)%nelements
            area = grid(iz)%area(itri)
            x    = grid(iz)%centroid(1,itri) - CM(1)
            y    = grid(iz)%centroid(2,itri) - CM(2)
            z    = grid(iz)%centroid(3,itri) - CM(3)
            xx   = area * (y*y + z*z) + xx
            yy   = area * (z*z + x*x) + yy
            zz   = area * (x*x + y*y) + zz
            xy   = area *  x*y + xy
            yz   = area *  y*z + yz
            zx   = area *  z*x + zx
         end do
      end do

      A(1,1) =  xx;  A(1,2) = -xy;  A(1,3) = -zx
      A(2,1) = -xy;  A(2,2) =  yy;  A(2,3) = -yz
      A(3,1) = -zx;  A(3,2) = -yz;  A(3,3) =  zz

      write (*, '(/, a, /, (3es15.6))') ' Inertia matrix:', (A(i,:), i = 1, 3)

!     Calculate the eigenvectors (and values) of the inertia matrix:

      call rs (3, 3, A, header%lambda, 1, header%R, fv1, fv2, ier)

      if (ier /= 0) then
         write (*, '(a, i4)') ' Eigenvector routine "rs" reports "tql2" error: ', ier
      else
         write (*, '(/, a, /, (es15.7, 2x, 3es15.7, es17.7))')          &
            ' Triangulation CM, principal axis matrix, and ordered eigenvalues:', (CM(i), header%R(i,:), header%lambda(i), i = 1, 3)
      end if

      end subroutine tri_moments_of_inertia

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_apply_rotation_R (header, grid)

!     Apply the rotation matrix R produced by tri_moments_of_inertia to the indicated surface triangulation.
!     Note that the eigenvalues/moments of inertia are returned in ascending order.
!     Correct application assumes these are about Ox, Oy, Oz respectively.  [What to do if this is not true?]
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized, plus R(:,:)
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data;
                                                         ! xyz(1:3,:) are rotated in place
!     Local variables:

      integer :: i, iz
      real    :: v(3)

!     Execution:
!     ----------

      do iz = 1, header%nzones
         do i = 1, grid(iz)%nnodes
            v(:) = grid(iz)%xyz(:,i)
            grid(iz)%xyz(:,i) = matmul (header%R, v)
         end do
      end do

      end subroutine tri_apply_rotation_R

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_zone_data_range (zone)

!     For the given surface triangulation zone, compute the x/y/z data ranges.
!     These calculations are applicable to an unstructured volume zone as well.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_type), intent (inout) :: zone  ! One data zone containing x,y,z data

!     Local variables:

      integer :: i

!     Execution:
!     ----------

      zone%xmin = zone%xyz(1,1);  zone%xmax = zone%xmin
      zone%ymin = zone%xyz(2,1);  zone%ymax = zone%ymin
      zone%zmin = zone%xyz(3,1);  zone%zmax = zone%zmin

      do i = 2, zone%nnodes
         zone%xmin = min (zone%xmin, zone%xyz(1,i));  zone%xmax = max (zone%xmax, zone%xyz(1,i))
         zone%ymin = min (zone%ymin, zone%xyz(2,i));  zone%ymax = max (zone%ymax, zone%xyz(2,i))
         zone%zmin = min (zone%zmin, zone%xyz(3,i));  zone%zmax = max (zone%zmax, zone%xyz(3,i))
      end do

      end subroutine tri_zone_data_range

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_zone_area (zone)

!     For the given surface triangulation zone, compute the surface area over all elements.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_type), intent (inout) :: zone  ! Surface triangulation zone containing x,y,z and conn data

!     Local variables:

      integer :: i1, i2, i3, itri
      real    :: v1(3), v2(3), v3(3)

!     Execution:
!     ----------

      zone%surface_area = zero

      do itri = 1, zone%nelements
         i1    = zone%conn(1,itri)
         i2    = zone%conn(2,itri)
         i3    = zone%conn(3,itri)
         v1(:) = zone%xyz(:,i3) - zone%xyz(:,i1)
         v2(:) = zone%xyz(:,i3) - zone%xyz(:,i2)
         call cross_product (v1, v2, v3)
         zone%surface_area = zone%surface_area + sqrt (dot_product (v3, v3))  ! Wolfram, e.g.
      end do

      zone%surface_area = zone%surface_area * half

      end subroutine tri_zone_area

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_zone_volume (header, zone)

!     For the given surface triangulation zone and header%interior_point(:), compute the summed volumes of the implied tetrahedra.
!     For efficiency (one pass through the triangular elements), compute the summed areas of the triangles as well.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (in)    :: header   ! Data structure containing %interior_point(:);
                                                         ! summed results for all zones of a CLOSED surface should be insensitive
                                                         ! to this choice of point
      type (tri_type),        intent (inout) :: zone     ! Surface triangulation zone containing x,y,z and conn data

!     Local variables:

      integer :: i1, i2, i3, itri
      real    :: center(3), v1(3), v2(3), v3(3), v4(3)

!     Execution:
!     ----------

      zone%surface_area    = zero
      zone%enclosed_volume = zero
      center(:) = header%interior_point(:)  ! Any reasonable interior point

      do itri = 1, zone%nelements
         i1 = zone%conn(1,itri)
         i2 = zone%conn(2,itri)
         i3 = zone%conn(3,itri)

!        Area of triangle (times 2):

         v1(:) = zone%xyz(:,i3) - zone%xyz(:,i1)
         v2(:) = zone%xyz(:,i3) - zone%xyz(:,i2)

         call cross_product (v1, v2, v3)

         zone%surface_area = zone%surface_area + sqrt (dot_product (v3, v3))  ! Wolfram, e.g.

!        Volume of tetrahedron (times 6):

         v1(:) = zone%xyz(:,i1) - center(:)
         v2(:) = zone%xyz(:,i2) - center(:)
         v3(:) = zone%xyz(:,i3) - center(:)

         call cross_product (v2, v3, v4)

         zone%enclosed_volume = zone%enclosed_volume + abs (dot_product (v1, v4))  ! Wolfram, e.g.
      end do

      zone%surface_area    = zone%surface_area * half
      zone%enclosed_volume = zone%enclosed_volume * sixth

      end subroutine tri_zone_volume

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine tri_zone_center_of_mass (zone)

!     For the given surface triangulation zone, compute the center of mass assuming constant unit areal density.
!     The total zone area and all cell areas and centroids are stored here as by-products for likely use by related utilities.
!     The associated storage is allocated here, so be sure it hasn't already been allocated by a call to a related utility.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_type), intent (inout) :: zone ! Surface triangulation zone containing x,y,z and conn data;
                                              ! zone%area(:) and zone%centroid(1:3,:) are returned too (allocated here);
                                              ! zone%area and %cm(1:3) combine with those of other zones for the overall CM;
!     Local variables:                        ! see also tri_center_of_mass

      integer :: i1, i2, i3, ios, itri, n
      real    :: v1(3), v2(3), v3(3)

!     Execution:
!     ----------

      n = zone%nelements

      allocate (zone%centroid(3,n), zone%area(n), stat=ios);  zone%allocated_centroid = true;  zone%allocated_area = true
      if (ios /= 0) then
         write (*, '(a)') '*** tri_zone_center_of_mass: Trouble allocating cell centroids and areas.  Already allocated?'
      end if

      zone%surface_area = zero
      zone%cm(:)        = zero

      do itri = 1, n
         i1    = zone%conn(1,itri)
         i2    = zone%conn(2,itri)
         i3    = zone%conn(3,itri)
         zone%centroid(:,itri) = (zone%xyz(:,i1) + zone%xyz(:,i2) + zone%xyz(:,i3)) * third
         v1(:) = zone%xyz(:,i3) - zone%xyz(:,i1)
         v2(:) = zone%xyz(:,i3) - zone%xyz(:,i2)
         call cross_product (v1, v2, v3)
         zone%area(itri)   = sqrt (dot_product (v3, v3)) * half     ! Wolfram, e.g.
         zone%surface_area = zone%area(itri) + zone%surface_area
         zone%cm(:)        = zone%area(itri) * zone%centroid(:,itri) + zone%cm(:)
      end do

      zone%cm(:) = zone%cm(:) / zone%surface_area

      end subroutine tri_zone_center_of_mass

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_read (lun, header, grid, ios)

!     Read one 3-space unstructured volume dataset, binary or ASCII, with BLOCK or POINT data packing.
!     The first 3 variables are returned as the x, y, z fields of each zone in grid(:).
!     Remaining variables become the "f" field packed in "point" order (n-tuples, where n = numf = # variables - 3).
!     The input file title is also returned, along with the variable names (up to name_limit characters each).
!     Titles for the zone or zones are returned in the appropriate field of each element of the grid array.
!     The file is opened and closed here.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)                   :: lun      ! Logical unit for the file being read;
                                                         ! opened here upon entry; closed here before the return
      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information;
                                                         ! input with file name, form, formatting, and element size in place
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and optional f data;
                                                         ! allocated here prior to the reading
      integer, intent (inout)                :: ios      ! 1 on input activates printing of header/zone info. during the read;
                                                         ! 0 on output means no error detected, else diagnostics are written to
                                                         ! standard output; early return follows
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

!     Open the file, read the header records, determine the number of zones, allocate an array of unstructured zone structures,
!     and set up the zone dimensions by scanning till EOF:

      call vol_header_read (lun, header, grid, ios)

      if (ios /= 0) go to 999

!     Allocate and read each zone:

      do iz = 1, header%nzones

         call vol_zone_allocate (header, grid(iz), ios)

         if (ios /= 0) then
            write (*, '(a, i5)') ' vol_read: Trouble allocating zone #', iz
            write (*, '(2a)')    ' File name: ', trim (header%filename)
            go to 999
         end if

         call vol_zone_read (lun, header, grid(iz), ios)

         if (ios /= 0) then
            write (*, '(a, i4)')  ' vol_read:  Trouble reading zone #', iz
            write (*, '(2a)')     ' File name: ', trim (header%filename)
            write (*, '(a, 3i9)') ' # nodes, # elements, # functions: ', grid(iz)%nnodes, grid(iz)%nelements, numf
            write (*, '(a, i3)')  ' # vertices per cell:', header%nvertices
            go to 999
         end if

      end do

  999 continue

!!    if (header%formatted) then
         close (lun)
!!    else
!!       ios = TecEnd110 ()
!!       if (ios /= 0) write (*, '(2a)') ' Trouble closing binary file ', trim (header%filename)
!!    end if

      end subroutine vol_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_write (lun, header, grid, ios)

!     Write a 3-space unstructured volume dataset, binary or ASCII, with BLOCK or POINT data packing.
!     The first 3 variables are taken to be the x, y, z fields of each zone in grid(:).
!     Remaining variables should be the "f" field packed in "point" order (n-tuples, where n = numf = # variables - 3).
!     The indicated file title is written along with the variable names (up to name_limit characters each).
!     Titles for the zone or zones are written from the appropriate field of each element of the grid array.
!     The file is opened and closed here.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)                   :: lun      ! Logical unit for the file being written;
                                                         ! opened here upon entry; closed here before the return
      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information;
                                                         ! input with file name, form, formatting, and element size in place
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and optional f data;
                                                         ! NOT deallocated after the writing
      integer, intent (out)                  :: ios      ! 0 on output means no error detected, else diagnostics are written to
                                                         ! standard output; early return follows
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

!     Open the file and write the header records:

      call vol_header_write (lun, header, grid, ios)

      if (ios /= 0) go to 999

!     Write each zone:

      do iz = 1, header%nzones

         call vol_zone_write (lun, header, grid(iz), ios)

         if (ios /= 0) then
            write (*, '(a, i4)')  ' vol_write:  Trouble writing zone #', iz
            write (*, '(2a)')     ' File name: ', trim (header%filename)
            write (*, '(a, 3i9)') ' # nodes, # elements, # functions: ', grid(iz)%nnodes, grid(iz)%nelements, numf
            go to 999
         end if

      end do

  999 continue

!!    if (header%formatted) then
         close (lun)
!!    else
!!       ios = TecEnd110 ()
!!       if (ios /= 0) write (*, '(2a)') ' Trouble closing binary file ', trim (header%filename)
!!    end if

      end subroutine vol_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_get_element_type (lun, header, ios)
!
!
!     This afterthought was prompted by the TRIANGULATION_TOOL driving program when it needed to be extended to drive the volume
!     grid analogues of the triangulation utilities: the user should not have to be prompted for the element size; the file name
!     should suffice.  Since the existing reading utilities assume that header%nvertices is known (and assigned) by the application,
!     it is simplest to open the file here, locate the element type (assumed to be the same for all zones), then close the file.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)    :: lun     ! Logical unit number
      type (tri_header_type), intent (inout) :: header  ! Data structure containing dataset header information; input with
                                                        ! file name and form; output with %nvertices
      integer,                intent (inout) :: ios     ! 0 on output means no error detected

!     Local constants:

      character (23), parameter :: routine = ' vol_get_element_type: '

!     Local variables:

      integer :: first, header_case, last, mark, nvertices

!     Execution:

      if (header%formatted) then

         open (lun, file=trim (header%filename), status='old', iostat=ios)

      else ! Binary input has not been implemented

         write (*, '(/, 2a)') routine, 'Reading of Tecplot binaries is not an option yet.'

      end if

      if (ios /= 0) then
         write (*, '(3a)') routine, 'Trouble opening file ', trim (header%filename)
         go to 900
      end if

      if (header%formatted) then

!        Read the file header lines up to and including the first 'ZONE' line.

         do  ! Until a zone header is found
            read (lun, '(a)') buffer;  last = len_trim (buffer)
            call upcase (buffer(1:last))
            if (index (buffer(1:last), 'ZONE') > 0) exit
         end do

!        ZONETYPE=FETriangle can clash with ET=Triangle, so look for it first:

         header_case = 0
         do  ! Until either ZONETYPE or ET is found
            first = index (buffer(1:last), 'ZONETYPE')
            if (first > 0) then
               first = first + 8
               header_case = 1
               exit
            else
               first = index (buffer(1:last), 'ET')
               if (first > 0) then
                  first = first + 2
                  header_case = 2
                  exit
               end if
            end if
            read (lun, '(a)') buffer;  last = len_trim (buffer)
            call upcase (buffer(1:last))
         end do

         if (header_case == 0) then
            write (*, '(3a)') routine, 'Element type not apparent: ', &
               'neither ET= nor ZONETYPE= found.'
            go to 900
         end if

         call scan2 (buffer(1:last), ' =', first, last, mark)

         select case (header_case)
            case (1)  ! ZONETYPE=...
               select case (buffer(first:first+5)) ! FExxxx (ORDERED is not expected)
                  case ('FELINE')
                     nvertices = 2
                  case ('FETRIA')
                     nvertices = 3
                  case ('FEQUAD', 'FETETR')
                     nvertices = 4
                  case ('FEHEXA', 'FEBRIC')
                     nvertices = 8
                  case default
                     write (*, '(3a)') routine, 'Unknown finite element zone type: ', buffer(first:mark)
                     go to 900
               end select
            case (2)  ! ET=...
               select case (buffer(first:first+2)) ! Unknown if TET is legal for tetrahedral volumes; assume so
                  case ('TRI')
                     nvertices = 3
                  case ('TET')
                     nvertices = 4
                  case ('HEX', 'BRI') ! 'BRICK'
                     nvertices = 8
                  case default
                     write (*, '(3a)') routine, 'Unknown element type: ', buffer(first:mark)
                     go to 900
               end select
         end select

      else  ! Binary input is incomplete
      end if

      header%nvertices = nvertices
      ios = 0
      go to 999

 900  ios = 999

 999  close (lun)

      end subroutine vol_get_element_type

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_header_read (lun, header, grid, ios)
!
!     Open a file of 3-space unstructured volume data and read the file header and zone header records.
!     The grid(*) array is allocated and zone header information is entered.
!     Before returning, the file is rewound and advanced ready for reading the first zone.
!
!     If no variable names are present, they are defaulted to "X", "Y", "Z", "V1", "V2", ...,
!     but a DT=(... ) record must then accompany zone 1 so that the number of variables can be determined.
!
!     Reading of binary files is incomplete.
!
!     Format for a Tecplot volume file (header%fileform = 1 (vc) or 2 (cc); zone%element type = tet or hex|brick):
!
!        variables = x y z
!        zone T="grid", n=      505286 , e=     2759284 ,et=brick,              f=fepoint
!         2.273000031709671E-002  1.339999958872795E-003  0.119850002229214
!         2.288999967277050E-002 -1.100000008591451E-004  0.119819998741150
!        ::::::::::::::::
!         7.481993472351248E-002 -1.206158433734931E-002 -1.534229517647054E-002
!         98307     98308     98309     98309     98310     98310     98310     98310
!         98308     98307     98309     98309     98311     98311     98311     98311
!        ::::::::::::::::
!        263981    238511    270276    270276    270277    270277    270277    270277
!        318887    318885    378503    378503    378505    378505    378505    378505
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)    :: lun     ! Logical unit number
      type (tri_header_type), intent (inout) :: header  ! Data structure containing dataset header information; input with
                                                        ! file name, form, and %nvertices
      type (tri_type),        pointer        :: grid(:) ! Array of derived data types for unstructured data zones, allocated here
      integer,                intent (inout) :: ios     ! 1 on input means write header/zone info. during reading (verbose mode);
                                                        ! 0 on output means no error detected
!     Local constants:

      character (18), parameter :: routine = ' vol_header_read: '

!     Execution:

      call tri_header_read (lun, header, grid, ios)     ! Should work for triangles and volume elements

      if (ios /= 0) then
         write (*, '(2a, i4)') routine, ' Error reading the file header.  Unit number:', lun, ' File name: ', trim (header%filename)
      end if

      end subroutine vol_header_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_header_write (lun, header, grid, ios)
!
!     Open a file for output of 3-space unstructured volume data and write the file header and zone header records.
!
!     Writing of binary files is incomplete.
!
!     Format for a Tecplot volume file (header%fileform = 1 (vc) or 2 (cc); element type = tet or hex|brick):
!
!        TITLE = "Case xxx"
!        VARIABLES =
!        "x, m"
!        "y, m"
!        "z, m"
!        "Area, m^2"
!        "Solid angle, sr"
!        ZONE T="Zone yyy"
!           Nodes = 561, Elements = 1024, et=tet, f=fepoint
!           [ZONETYPE=FETETRAHEDRON]
!           DATAPACKING=BLOCK
!           VARLOCATION=([4-5]=CELLCENTERED)
!           0.0000000E+00   4.9067674E-02   0.0000000E+00   9.8017140E-02   6.9308585E-02     ! All x, then all y, then z (vertices)
!           0.0000000E+00   1.4673047E-01   1.2707232E-01   7.3365237E-02   0.0000000E+00     ! followed by all f1 then all f2 at
!           1.9509032E-01   1.8023996E-01   1.3794969E-01   7.4657834E-02   0.0000000E+00     ! element centers
!            :               :               :               :               :
!           1.2038183E-03   1.2411699E-03   1.2038183E-03                                     ! Last cell-centered values of f2
!             1     2     3    4                                                              ! Connectivity data
!             2     4     5    6
!             :     :     :
!           527   559   560  561
!           560   528   527  561
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)  :: lun      ! Logical unit number
      type (tri_header_type), intent (in)  :: header   ! Data structure containing dataset header information
      type (tri_type),        pointer      :: grid(:)  ! Array of derived data types for unstructured data zones
      integer,                intent (out) :: ios      ! 0 on output means no error detected

!     Local constants:

      character (19), parameter :: routine = ' vol_header_write: '

!     Execution:

      call tri_header_write (lun, header, grid, ios)

      if (ios /= 0) then
         write (*, '(2a, i4)') routine, ' Error writing the file header.  Unit number:', lun, ' File name: ', trim (header%filename)
      end if

  999 continue

      end subroutine vol_header_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_zone_allocate (header, zone, ios)
!
!     Allocate the x, y, z and optional f arrays and the connectivity array for one zone (seems identical to tri_zone_allocate).
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (in)    :: header  ! Dataset header with fileform
      type (tri_type),        intent (inout) :: zone
      integer,                intent (out)   :: ios

!     Execution:

      call tri_zone_allocate (header, zone, ios)

      end subroutine vol_zone_allocate

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_zone_read (lun, header, zone, ios)  ! (Seems identical to tri_zone_read.)
!
!     Read one 3-space zone of unstructured volume data from a file (ASCII, POINT or BLOCK packing order).
!     Binary reads have yet to be implemented.
!     The zone dimensions have already been determined as part of reading the file header, and x/y/z/f/iconn arrays for this zone
!     should have been allocated via tri_zone_allocate.
!     In the case of Tecplot files, the file is presumed to be positioned ready to read a 'zone' keyword as the first token.
!
!     The zone keywords can be in any order, possibly with a few leading blanks or blank lines.
!     Since vol_header_read has determined the number of lines per zone header, the logic is slightly different from
!     that for the count_zones procedure.  The loop over keywords here starts with finding a keyword as opposed to
!     already having encountered one, because we don't want to buffer in the first line of numeric data when reparsing
!     the zone header.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)    :: lun     ! Logical unit number
      type (tri_header_type), intent (inout) :: header  ! Dataset header with nzones, etc.
      type (tri_type),        intent (inout) :: zone    ! Zone to be read, with %nnodes, %nelements set & other fields allocated
      integer,                intent (out)   :: ios     ! 0 = no error

!     Execution:

      call tri_zone_read (lun, header, zone, ios)

      end subroutine vol_zone_read

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine vol_zone_write (lun, header, zone, ios)  ! (Seems identical to tri_zone_write.)
!
!     Write one 3-space zone of unstructured volume data to a file (ASCII, POINT or BLOCK packing order).
!     Binary writes have yet to be implemented.
!     The file is presumed to be positioned ready to write a 'ZONE T(itle) =' line.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)  :: lun     ! Logical unit number
      type (tri_header_type), intent (in)  :: header  ! Dataset header with nzones, etc.
      type (tri_type),        intent (in)  :: zone    ! Zone to be written
      integer,                intent (out) :: ios     ! 0 = no error

!     Execution:

      call tri_zone_write (lun, header, zone, ios)

      end subroutine vol_zone_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine deallocate_vol_zones (iz1, iz2, numf, grid, ios)

!     Deallocate the indicated zones.  Seems identical to deallocate_tri_zones.

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)  :: iz1, iz2             ! Zone range to deallocate
      integer, intent (in)  :: numf                 ! > 0 means deallocate %f too; actually, %allocated_f is preferable now
      type (tri_type), intent (inout) :: grid(iz2)  ! At least this many
      integer, intent (out) :: ios                  ! 0 means no problem

!     Execution:

      call deallocate_tri_zones (iz1, iz2, numf, grid, ios)

      end subroutine deallocate_vol_zones

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_data_range (header, grid)  ! (Seems identical to tri_data_range.)

!     For the given surface triangulation, compute the x/y/z data ranges over all zones, which are assumed to be read already.
!     This could be used to set interior_point(:) for enclosed volume calculations.  In fact, as a convenience, interior_point(:)
!     is returned as the average of xmin & xmax, etc.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data

!     Execution:
!     ----------

      call tri_data_range (header, grid)

      end subroutine vol_data_range

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_volume (header, grid)

!     For the given unstructured volume dataset and interior_point(:), compute the total volume over all zones, which are assumed
!     to be read already.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data

!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%solid_volume = zero

      do iz = 1, header%nzones

         call vol_zone_volume (header, grid(iz))

         header%solid_volume = header%solid_volume + grid(iz)%solid_volume
      end do

      end subroutine vol_volume

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_center_of_mass (header, grid)

!     For the given unstructured volume data, assuming constant unit density, compute the overall center of mass.
!     This involves computing and storing, for each zone, all the cell centroids and cell volumes (as might be needed for
!     moments of inertia calculations).  The total volume for all zones is a by-product along with the total for each zone.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data;
                                                         ! zone CM and cell centroids and volumes are stored upon return, along
                                                         ! with the overall CM
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

      header%solid_volume = zero
      header%CM(:)        = zero

      do iz = 1, header%nzones

         call vol_zone_center_of_mass (header, grid(iz)) ! Also allocates and stores cell centroids & volumes, and sums cell vols.

         header%solid_volume = header%solid_volume + grid(iz)%solid_volume
         header%CM(:)        = header%CM(:)        + grid(iz)%solid_volume * grid(iz)%cm(:)
         write (*, '(a, i4, es16.8, 3x, 3es16.8)') '   zone, volume, CM(1:3):', iz, grid(iz)%solid_volume, grid(iz)%cm(:)
      end do

      header%CM(:) = header%CM(:) / header%solid_volume
      write (*, '(a, es16.8, 3x, 3es16.8)') '   total volume, CM(1:3):    ', header%solid_volume, header%CM(:)

      end subroutine vol_center_of_mass

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_moments_of_inertia (header, grid)

!     For the given unstructured volume data, assuming constant unit density, compute the overall moments of inertia about
!     Ox, Oy, Oz along with the rotation matrix corresponding to the principal axes.  Centers of mass, etc., are computed here
!     as an initial part of the inertia calculations.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data;
                                                         ! zone CM and cell centroids and volumes are stored upon return, along
                                                         ! with the overall CM and the moments of inertia and associated rotation
!     Local variables:                                   ! matrix

      integer :: i, ier, icell, iz
      real    :: vol, x, y, z, xx, yy, zz, xy, yz, zx
      real    :: fv1(3), fv2(3)                          ! Work-space for eigen routine
      real    :: A(3,3), CM(3)                           ! Inertia matrix to be diagonalized to determine the principal axes;
                                                         ! CM(:) is just a copy of the header center of mass coordinates
!     Execution:
!     ----------

      call vol_center_of_mass (header, grid)             ! Includes allocating and storing all cell centroids and volumes

      CM(:) = header%CM(:)
      xx = zero;  yy = zero;  zz = zero
      xy = zero;  yz = zero;  zx = zero

      do iz = 1, header%nzones
         do icell = 1, grid(iz)%nelements
            vol = grid(iz)%volume(icell)
            x   = grid(iz)%centroid(1,icell) - CM(1)
            y   = grid(iz)%centroid(2,icell) - CM(2)
            z   = grid(iz)%centroid(3,icell) - CM(3)
            xx  = vol * (y*y + z*z) + xx
            yy  = vol * (z*z + x*x) + yy
            zz  = vol * (x*x + y*y) + zz
            xy  = vol *  x*y + xy
            yz  = vol *  y*z + yz
            zx  = vol *  z*x + zx
         end do
      end do

      A(1,1) =  xx;  A(1,2) = -xy;  A(1,3) = -zx
      A(2,1) = -xy;  A(2,2) =  yy;  A(2,3) = -yz
      A(3,1) = -zx;  A(3,2) = -yz;  A(3,3) =  zz

      write (*, '(/, a, /, (3es15.6))') ' Inertia matrix:', (A(i,:), i = 1, 3)

!     Calculate the eigenvectors (and values) of the inertia matrix:

      call rs (3, 3, A, header%lambda, 1, header%R, fv1, fv2, ier)

      if (ier /= 0) then
         write (*, '(a, i4)') ' Eigenvector routine "rs" reports "tql2" error: ', ier
      else
         write (*, '(/, a, /, (es15.7, 2x, 3es15.7, es17.7))')          &
            ' Volume grid CM, principal axis matrix, and ordered eigenvalues:', (CM(i), header%R(i,:), header%lambda(i), i = 1, 3)
      end if

      end subroutine vol_moments_of_inertia

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_apply_rotation_R (header, grid)  ! (Seems the same as tri_apply_rotation.)

!     Apply the rotation matrix R produced by tri_moments_of_inertia to the indicated unstructured volume dataset (all zones).
!     Note that the eigenvalues/moments of inertia are returned in ascending order.
!     Correct application assumes these are about Ox, Oy, Oz respectively.  [What to do if this is not true?]
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information set when
                                                         ! all zones have been read or otherwise initialized, plus R(:,:)
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z and conn data;
                                                         ! xyz(1:3,:) are rotated in place
!     Execution:
!     ----------

      call tri_apply_rotation_R (header, grid)

      end subroutine vol_apply_rotation_R

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_zone_data_range (zone)  ! (Seems the same as tri_zone_data_range.)

!     For the given unstructured volume data zone, compute the x/y/z data ranges.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_type), intent (inout) :: zone  ! One data zone containing x,y,z data

!     Execution:
!     ----------

      call tri_zone_data_range (zone)

      end subroutine vol_zone_data_range

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_zone_volume (header, zone)

!     For the given unstructured data zone, compute the summed volumes of the cells.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (in)    :: header   ! Data structure containing %nvertices
      type (tri_type),        intent (inout) :: zone     ! Unstructured volume zone containing x,y,z and conn data

!     Local constants:

      character (18), parameter :: routine = ' vol_zone_volume: '

!     Local variables:

      integer :: i1, i2, i3, i4, icell
      real    :: v1(3), v2(3), v3(3), v4(3)

!     Execution:
!     ----------

      zone%solid_volume = zero

      select case (header%nvertices)

         case (4)  ! Tetrahedra

            do icell = 1, zone%nelements
               i1 = zone%conn(1,icell)
               i2 = zone%conn(2,icell)
               i3 = zone%conn(3,icell)
               i4 = zone%conn(4,icell)

!              Volume of tetrahedron (times 6) (Wolfram, e.g.):

               v1(:) = zone%xyz(:,i1) - zone%xyz(:,i4)
               v2(:) = zone%xyz(:,i2) - zone%xyz(:,i4)
               v3(:) = zone%xyz(:,i3) - zone%xyz(:,i4)

               call cross_product (v2, v3, v4)

               zone%solid_volume = zone%solid_volume + abs (dot_product (v1, v4))
            end do

         case (8)  ! Hex cells, or bricks, that may really be tetrahedra

            icell = zone%nelements / 3   ! Some random cell less likely to be collapsed than the first or last cell

            if (zone%conn(4,icell) == zone%conn(3,icell) .and. &  ! As observed in a Gridgen-derived volume meshing
                zone%conn(6,icell) == zone%conn(5,icell) .and. &  ! of the Itokawa asteroid triangulation
                zone%conn(7,icell) == zone%conn(5,icell) .and. &
                zone%conn(8,icell) == zone%conn(5,icell)) then

                write (*, '(2a)') routine, &
                   'Treating all cells as single tets because the hexahedra appear to have collapsed edges.'

                do icell = 1, zone%nelements
                   i1 = zone%conn(1,icell)
                   i2 = zone%conn(2,icell)
                   i3 = zone%conn(3,icell)
                   i4 = zone%conn(5,icell)  ! Assumed 4th unique vertex

!                  Volume of a hexahedron with only 4 finite edges is that of a single tetrahedron:

                   v1(:) = zone%xyz(:,i1) - zone%xyz(:,i4)
                   v2(:) = zone%xyz(:,i2) - zone%xyz(:,i4)
                   v3(:) = zone%xyz(:,i3) - zone%xyz(:,i4)

                   call cross_product (v2, v3, v4)

                   zone%solid_volume = zone%solid_volume + abs (dot_product (v1, v4))  ! 6 x volume = v1'v4 -- see Wolfram
                end do

            else  ! Do the fully general hex case if the need arises (using %element_type?).
                write (*, '(2a)') routine, 'true hexahedra volumes have not been implemented yet (5 tetrahedra).'
            end if

         case default

            write (*, '(2a, i4)') routine, 'unhandled # vertices per cell:', header%nvertices

      end select

      zone%solid_volume = zone%solid_volume * sixth

      end subroutine vol_zone_volume

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine vol_zone_center_of_mass (header, zone)

!     For the given unstructured volume zone, compute the center of mass assuming constant unit density.
!     The total zone volume and all cell volumes and centroids are stored here as by-products for likely use by related utilities.
!     The associated storage is allocated here, so be sure it hasn't already been allocated by a call to a related utility.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      type (tri_header_type), intent (in) :: header  ! Data structure containing %nvertices
      type (tri_type), intent (inout)     :: zone    ! Unstructured volume zone containing x,y,z and conn data;
                                                     ! zone%volume(:) & zone%centroid(1:3,:) are returned too (allocated here);
                                                     ! zone%volume & %cm(1:3) combine with those of other zones for the overall CM;
!     Local constants:                               ! see also vol_center_of_mass

      character (26), parameter :: routine = ' vol_zone_center_of_mass: '

!     Local variables:

      integer :: i1, i2, i3, i4, i5, icell, ios, n
      real    :: v1(3), v2(3), v3(3), v4(3)

!     Execution:
!     ----------

      n = zone%nelements

      allocate (zone%centroid(3,n), zone%volume(n), stat=ios);  zone%allocated_centroid = true;  zone%allocated_volume = true
      if (ios /= 0) then
         write (*, '(2a)') routine, 'Trouble allocating cell centroids and volumes.  Already allocated?'
      end if

      zone%solid_volume = zero
      zone%cm(:)        = zero

      select case (header%nvertices)

         case (4)  ! Tetrahedra

            do icell = 1, zone%nelements
               i1 = zone%conn(1,icell)
               i2 = zone%conn(2,icell)
               i3 = zone%conn(3,icell)
               i4 = zone%conn(4,icell)
               zone%centroid(:,icell) = (zone%xyz(:,i1) + zone%xyz(:,i2) + zone%xyz(:,i3) + zone%xyz(:,i4)) * fourth

!              Volume of tetrahedron (Wolfram, e.g.):

               v1(:) = zone%xyz(:,i1) - zone%xyz(:,i4)
               v2(:) = zone%xyz(:,i2) - zone%xyz(:,i4)
               v3(:) = zone%xyz(:,i3) - zone%xyz(:,i4)

               call cross_product (v2, v3, v4)

               zone%volume(icell) = abs (dot_product (v1, v4)) * sixth
               zone%solid_volume  = zone%volume(icell) + zone%solid_volume
               zone%cm(:)         = zone%volume(icell) * zone%centroid(:,icell) + zone%cm(:)
            end do

         case (8)  ! Hex cells, or bricks, that may really be tetrahedra

            icell = zone%nelements / 3   ! Some random cell less likely to be collapsed than the first or last cell

            if (zone%conn(4,icell) == zone%conn(3,icell) .and. &  ! As observed in a Gridgen-derived volume meshing
                zone%conn(6,icell) == zone%conn(5,icell) .and. &  ! of the Itokawa asteroid triangulation
                zone%conn(7,icell) == zone%conn(5,icell) .and. &
                zone%conn(8,icell) == zone%conn(5,icell)) then

                write (*, '(2a)') routine, &
                   'Treating all cells as single tets because the hexahedra appear to have collapsed edges.'

                do icell = 1, zone%nelements
                   i1 = zone%conn(1,icell)
                   i2 = zone%conn(2,icell)
                   i3 = zone%conn(3,icell)
                   i4 = zone%conn(5,icell)  ! Assumed 4th unique vertex
                   zone%centroid(:,icell) = (zone%xyz(:,i1) + zone%xyz(:,i2) + zone%xyz(:,i3) + zone%xyz(:,i4)) * fourth

!                  Volume of a hexahedron with only 4 finite edges is that of a single tetrahedron:

                   v1(:) = zone%xyz(:,i1) - zone%xyz(:,i4)
                   v2(:) = zone%xyz(:,i2) - zone%xyz(:,i4)
                   v3(:) = zone%xyz(:,i3) - zone%xyz(:,i4)

                   call cross_product (v2, v3, v4)

                   zone%volume(icell) = abs (dot_product (v1, v4)) * sixth  ! 6 x volume = v1'v4 -- see Wolfram
                   zone%solid_volume  = zone%volume(icell) + zone%solid_volume
                   zone%cm(:)         = zone%volume(icell) * zone%centroid(:,icell) + zone%cm(:)
                end do

            else  ! Do the fully general hex case if the need arises (using %element_type?).
                write (*, '(2a)') routine, 'true hexahedra volumes have not been implemented yet (5 tetrahedra).'
            end if

         case default

            write (*, '(2a, i4)') routine, 'unhandled # vertices per cell:', header%nvertices

      end select


      zone%cm(:) = zone%cm(:) / zone%solid_volume

      end subroutine vol_zone_center_of_mass

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine cross_product (a, b, c)  ! This should be an F90 intrinsic;  it is private to this module

!     Calculate the cross product c = a x b for vectors in three-space.  The argument description is obvious.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      real, intent (in)  :: a(3), b(3)
      real, intent (out) :: c(3)

!     Execution:

      c(1) = a(2)*b(3) - a(3)*b(2)
      c(2) = a(3)*b(1) - a(1)*b(3)
      c(3) = a(1)*b(2) - a(2)*b(1)

      end subroutine cross_product

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine nas_sf_tri_write (lun, header, grid, ios)

!     Write a 3-space unstructured surface dataset as a small field NASATRAN file (x, y, z and elements only).
!     The author is unfamiliar with such files at the time of writing, so only one zone is assumed for now.

!     The file is opened and closed here.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer, intent (in)                   :: lun      ! Logical unit for the file being written;
                                                         ! opened here upon entry; closed here before the return
      type (tri_header_type), intent (inout) :: header   ! Data structure containing dataset header information;
                                                         ! input with file name and element size in place
      type (tri_type), pointer               :: grid(:)  ! Array of unstructured data zones containing x,y,z (only)
                                                         ! NOT deallocated after the writing
      integer, intent (out)                  :: ios      ! 0 on output means no error detected, else diagnostics are written to
                                                         ! standard output; early return follows
!     Local variables:

      integer :: iz

!     Execution:
!     ----------

!     Open the file and write the header records:

!!!   call nas_sf_tri_header_write (lun, header, grid, ios)

      open (lun, file=header%filename, status='unknown', iostat=ios)
      if (ios /= 0) go to 999

      numf = 0  ! For now

!     Write each zone:

      do iz = 1, header%nzones

         call nas_sf_tri_zone_write (lun, header, iz, grid(iz), ios)

         if (ios /= 0) then
            write (*, '(a, i4)')  ' nas_sf_tri_write:  Trouble writing zone #', iz
            write (*, '(2a)')     ' File name: ', trim (header%filename)
            write (*, '(a, 3i9)') ' # nodes, # elements, # functions: ', grid(iz)%nnodes, grid(iz)%nelements, numf
            go to 999
         end if

      end do

      write (lun, '(a)') 'ENDDATA'

      close (lun)

  999 continue

      end subroutine nas_sf_tri_write

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
      subroutine nas_sf_tri_zone_write (lun, header, iz, zone, ios)
!
!     Write one 3-space zone of triangulated data to a small field NASTRAN file.
!     The file is presumed to be positioned ready to write a GRID block.
!     Function values in addition to x, y, z are not treated (yet).
!
!     NASTRAN file format:
!
!        GRID    1       0       -0.148800.0784100.077610
!        GRID    2       0       -0.147910.0731600.079000
!          :     :       :         :      :       :
!        GRID    98305   0       0.1298900.062770-0.04944
!        GRID    98306   0       0.1295500.063950-0.04782
!        CTRIA3  1       1       65422   120     65297
!        CTRIA3  2       1       65422   32879   120
!          :     :       :         :      :       :
!        CTRIA3  196608  1       81813   98306   49281
!       [GRID    1       1       -.1234560.123450.12345  ! Possible further zone(s)?
!        GRID    2       1         :      :       :
!          :     :       :         :      :       :
!        CTRIA3  1       2       1234    12      12345
!        CTRIA3  2       2         :      :       :
!          :     :       :         :      :       :      ]
!        ENDDATA
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,                intent (in)  :: lun     ! Logical unit number
      type (tri_header_type), intent (in)  :: header  ! Dataset header with nzones, etc.
      integer,                intent (in)  :: iz      ! Zone number = "property" id
      type (tri_type),        intent (in)  :: zone    ! Zone to be written
      integer,                intent (out) :: ios     ! 0 = no error

!     Local variables:

      integer :: ie, in
      integer, save :: igpid = 0  ! "GRID Property ID"; not clear if it has to be different for each zone

!     Execution:

      buffer(1:nsline)  = blank  ! 8 fields
      igpid = 0

      buffer(1:nsfield) = GRID   ! Field 1
      call left_justify (nsfield, igpid, buffer(2*nsfield+1:3*nsfield))  ! Field 3

      do in = 1, zone%nnodes
         call left_justify (nsfield, in, buffer(  nsfield+1:2*nsfield))  ! Field 2
         call left_justify (nsfield, zone%xyz(1,in), buffer(3*nsfield+1:4*nsfield))  ! Field 4 (x)
         call left_justify (nsfield, zone%xyz(2,in), buffer(4*nsfield+1:5*nsfield))  ! Field 5 (y)
         call left_justify (nsfield, zone%xyz(3,in), buffer(5*nsfield+1:6*nsfield))  ! Field 6 (z)
         write (lun, '(a)') buffer(1:6*nsfield)
      end do

      buffer(1:nsfield) = CTRIA3  ! Field 1
      call left_justify (nsfield, iz, buffer(2*nsfield+1:3*nsfield))  ! Field 3

      do ie = 1, zone%nelements
         call left_justify (nsfield, ie, buffer(  nsfield+1:2*nsfield))  ! Field 2
         call left_justify (nsfield, zone%conn(1,ie), buffer(3*nsfield+1:4*nsfield))  ! Field 4 (i1)
         call left_justify (nsfield, zone%conn(2,ie), buffer(4*nsfield+1:5*nsfield))  ! Field 5 (i2)
         call left_justify (nsfield, zone%conn(3,ie), buffer(5*nsfield+1:6*nsfield))  ! Field 6 (i3)
         write (lun, '(a)') buffer(1:6*nsfield)
      end do

      igpid = igpid + 1
      ios   = 0

      end subroutine nas_sf_tri_zone_write

   end module triangulation_io
