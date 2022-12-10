!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!  adt_utilities.f90
!
!  Variations of Alternating Digital Tree (ADT) utilities are gathered here with
!  generic interfaces that allow use of common BUILD_ADT and SEARCH_ADT names
!  to be used, with differing argument lists, for the various grid types being
!  searched.  This overcomes a weakness of the original organization (same names
!  in different subdirectories) that did not lend itself to "publishing" on a
!  web-based repository.
!
!  As indicated in the specific build and search utilities, Edwin van der Weide
!  produced the first of these implementations (for a packed list of surface
!  quadrilaterals, some of which may be collapsed into triangles) for Stanford
!  University's aerodynamic shape optimization group in 2003.  James Reuther
!  provided a copy to the Space Technology Divn. at NASA Ames Research Center,
!  where David Saunders derived the five variants now packaged here.
!
!  The key techniques implemented here are to use cell bounding boxes in tree
!  structures to eliminate the bulk of cells quickly during a search for a
!  target point in 3-space, and to return the closest point to the target that
!  is either inside or on the boundary of (but NOT OUTSIDE) the nearest cell.
!  For multiblock grids, all cells of all blocks are combined in one search tree
!  as opposed to searching one block at a time.  This is key to handling target
!  points not in any block just as efficiently as targets inside the searched
!  grid: the best possible point not outside the grid is always returned along
!  with its squared distance from the target, which may or may not be zero.
!  Each search also returns interpolation coefficients for that best cell so
!  that vertex-centered data may be interpolated to the target point.
!
!  Note that these techniques, while admirably efficient for reasonably-sized
!  grids, cannot compete with cheapest-possible implementations that work with
!  squared distances to determine closest data points (only).  If no refinement
!  of each search (interpolation within the best cell found) is really needed,
!  a recommended alternative is the KDTREE2 package of Matthew B. Kennel, UCSD,
!  applied to cell-centered data.   KDTREE2 is an Open Source package available
!  on the web.
!
!  References:
!
!    Aftosmis, Michael J., "Solution Adaptive Cartesian Grid Methods for Aerody-
!    namic Flows with Complex Geometries," lecture notes for 28th Computational
!    Fluid Dynamics Lecture Series, von Karman Institute for Fluid Dynamics,
!    March 3-7, 1997.
!
!    Van der Weide, Edwin, Aeronautics and Astronautics Department, Stanford
!    University, original source code, 2003.
!
!  History:
!
!    02-Aug-2013  D.A.Saunders  Initial repackaging of the ADT variations as a
!                 ERC Inc./ARC  module with generic interfaces.  At this time,
!                               the mixed-cell variant has hooks for prism and
!                               pyramid cells (potentially needed by the US3D
!                               flow solver) but the associated nearest_*_point
!                               utilities have not been written.
!    27-Mar-2015    "     "     Two-space intersection calculations with a
!                               boundary of a 2D multiblock structured grid
!                               required analogues for the case of finding the
!                               closest point (to some target point) on a curve
!                               formed by the (:,j) points of all grid blocks,
!                               which are assumed to form a consistently indexed
!                               single layer of blocks around some geometry.
!    10-Apr-2015    "     "     BUILD_ADT fails on a 2-space volume grid with
!                               zero data range for Z.  Work-around: rotate the
!                               volume grid, using working grid GRIDW in module
!                               ADT_DATA where SEARCH_ADT can see it.
!    13-Apr-2015    "     "     Wrong!  Another glitch caused the failure.
!                               Therefore, the data rotation has been removed.
!    17-Oct-2019    "     "     See SEARCH_STRUCTURED_VOLUME_ADT for notes on a
!                               work-around for possible matrix singularity.
!    23-Dec-2019    "     "     Fixed a typo in the singularity diagnostic.
!    28-Dec-2020    "     "     Print the cell vertices as well, once in a
!                               given Newton iteration where the singularity
!                               may appear for multiple iterations.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!      Module ADT_DATA is placed ahead of the module of combined build & search
!      variants in order to be compiled first and packaged with them. It is used
!      internally, not by application programs.

!      ******************************************************************
       MODULE ADT_DATA
!      *                                                                *
!      * LOCAL MODULE TO STORE THE 6 DIMENSIONAL ALTERNATING DIGITAL    *
!      * TREE OF THE BOUNDING BOXES OF A SET OF ELEMENTS IN 3D AND THE  *
!      * POSSIBLE TARGET BOUNDING BOXES.                                *
!      *                                                                *
!      * FILE:          adt_data.f90 (originally)                       *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-06-2003                                      *
!      * LAST MODIFIED: 12-06-2003                                      *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      *                                                                *
!      ******************************************************************
!
       IMPLICIT NONE
       SAVE

       PUBLIC
       PRIVATE :: LESS_EQUAL_BBOX_TARGET_TYPE
       PRIVATE :: LESS_BBOX_TARGET_TYPE
!
!      ******************************************************************
!      *                                                                *
!      * THE DEFINITION OF ADT_LEAF DERIVED DATA TYPE. THE ADT IS AN    *
!      * ARRAY OF ADT_LEAVES.                                           *
!      *                                                                *
!      ******************************************************************
!
       TYPE ADT_LEAF_TYPE

         ! CHILDREN(2): CHILDREN OF THE PARENT. IF NEGATIVE IT MEANS THAT
         !              IT IS A TERMINAL LEAF AND THE ABSOLUTE VALUES
         !              INDICATE THE FACE ID'S. NOTE THAT IT IS ALLOWED
         !              THAT 1 CHILD IS NEGATIVE AND THE OTHER POSITIVE.
         ! XMIN(6):     THE MINIMUM COORDINATES OF THE LEAF.
         ! XMAX(6):     THE MAXIMUM COORDINATES OF THE LEAF.

         INTEGER, DIMENSION(2) :: CHILDREN
         REAL,    DIMENSION(6) :: XMIN, XMAX

       END TYPE ADT_LEAF_TYPE
!
!      ******************************************************************
!      *                                                                *
!      * THE DEFINITION OF BBOX_TARGET_TYPE, WHICH STORES THE DATA OF A *
!      * POSSIBLE BOUNDARY BOX WHICH MINIMIZES THE DISTANCES TO THE     *
!      * GIVEN COORDINATE.                                              *
!      *                                                                *
!      ******************************************************************
!
       TYPE BBOX_TARGET_TYPE

         ! ID:        THE ID OF THE BOUNDING BOX IN THE LIST.
         ! POS_DIST2: THE POSSIBLE MINIMUM DISTANCE SQUARED TO THE ACTIVE
         !            COORDINATE.

         INTEGER :: ID
         REAL    :: POS_DIST2

       END TYPE BBOX_TARGET_TYPE

       ! INTERFACE FOR THE EXTENSION OF THE OPERATORS <= AND <.
       ! THESE ARE NEEDED FOR THE SORTING OF BBOX_TARGET_TYPE. NOTE
       ! THAT THE = OPERATOR DOES NOT NEED TO BE DEFINED, BECAUSE
       ! BBOX_TARGET_TYPE ONLY CONTAINS PRIMITIVE TYPES.

       INTERFACE OPERATOR(<=)
         MODULE PROCEDURE LESS_EQUAL_BBOX_TARGET_TYPE
       END INTERFACE

       INTERFACE OPERATOR(<)
         MODULE PROCEDURE LESS_BBOX_TARGET_TYPE
       END INTERFACE
!
!      ******************************************************************
!      *                                                                *
!      * VARIABLES STORED IN THIS MODULE.                               *
!      *                                                                *
!      ******************************************************************
!
       ! NLEAVES:      NUMBER OF LEAVES PRESENT IN THE ADT. DUE TO THE
       !               VARIABLE SPLITTING THE TREE IS OPTIMALLY BALANCED
       !               AND THEREFORE NLEAVES EQUALS THE NUMBER OF
       !               BOUNDING BOXES - 1.
       ! ADT(NLEAVES): THE ALTERNATING DIGITAL TREE.

       INTEGER :: NLEAVES

       TYPE (ADT_LEAF_TYPE), ALLOCATABLE, DIMENSION(:) :: ADT

       ! XBBOX(6,NCELL): THE COORDINATES OF THE BOUNDING BOXES OF THE
       !                 ELEMENTS TO BE STORED IN THE ADT.

       REAL, DIMENSION(:,:), ALLOCATABLE :: XBBOX

       ! NALLOC_BBOX:    NUMBER ALLOCATED FOR THE POSSIBLE TARGET
       !                 BOUNDING BOXES.
       ! BBOX_TARGETS(): ARRAY TO STORE THE TARGET BOUNDING BOXES.

       INTEGER :: NALLOC_BBOX
       TYPE(BBOX_TARGET_TYPE), DIMENSION(:), ALLOCATABLE :: BBOX_TARGETS

       ! NALLOC_FRONT_LEAVES:     NUMBER ALLOCATED FOR THE FRONTAL LEAVES
       !                          THE ADT SEARCH.
       ! NALLOC_FRONT_LEAVES_NEW: IDEM FOR THE NEW FRONT.
       ! FRONT_LEAVES():          THE LEAVES OF THE SEARCH FRONT.
       ! FRONT_LEAVES_NEW():      IDEM FOR THE NEW FRONT.

       INTEGER :: NALLOC_FRONT_LEAVES
       INTEGER :: NALLOC_FRONT_LEAVES_NEW

       INTEGER, ALLOCATABLE, DIMENSION(:) :: FRONT_LEAVES
       INTEGER, ALLOCATABLE, DIMENSION(:) :: FRONT_LEAVES_NEW

       ! NSTACK:        NUMBER OF ELEMENTS ALLOCATED IN STACK, NEEDED
       !                IN THE QSORT ROUTINE.
       ! STACK(NSTACK): THE CORRESPONDING ARRAY.

       INTEGER :: NSTACK
       INTEGER, ALLOCATABLE, DIMENSION(:) :: STACK

       !=================================================================

       CONTAINS

         !===============================================================

         LOGICAL FUNCTION LESS_EQUAL_BBOX_TARGET_TYPE(G1,G2)
!
!        ****************************************************************
!        *                                                              *
!        * LESS_EQUAL_BBOX_TARGET_TYPE RETURNS .TRUE. IF G1 <= G2. THE  *
!        * COMPARISON IS FIRSTLY BASED ON THE POSSIBLE MINIMUM DISTANCE *
!        * SUCH THAT THE MOST LIKELY CANDIDATES ARE TREATED FIRST.      *
!        * IN CASE OF TIES THE BOUNDARY BOX ID IS CONSIDERED.           *
!        *                                                              *
!        ****************************************************************
!
         IMPLICIT NONE
!
!        FUNCTION ARGUMENTS.
!
         TYPE(BBOX_TARGET_TYPE), INTENT(IN) :: G1, G2
!
!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************
!
         ! COMPARE THE POSSIBLE MINIMUM DISTANCES.

         IF(G1%POS_DIST2 < G2%POS_DIST2) THEN
           LESS_EQUAL_BBOX_TARGET_TYPE = .TRUE.
           RETURN
         ELSE IF(G1%POS_DIST2 > G2%POS_DIST2) THEN
           LESS_EQUAL_BBOX_TARGET_TYPE = .FALSE.
           RETURN
         ENDIF

         ! COMPARE THE BOUNDING BOX ID'S.

         IF(G1%ID < G2%ID) THEN
           LESS_EQUAL_BBOX_TARGET_TYPE = .TRUE.
           RETURN
         ELSE IF(G1%ID > G2%ID) THEN
           LESS_EQUAL_BBOX_TARGET_TYPE = .FALSE.
           RETURN
         ENDIF

         ! G1 AND G2 ARE IDENTICAL. RETURN .TRUE.

         LESS_EQUAL_BBOX_TARGET_TYPE = .TRUE.

         END FUNCTION LESS_EQUAL_BBOX_TARGET_TYPE

         !===============================================================

         LOGICAL FUNCTION LESS_BBOX_TARGET_TYPE(G1,G2)
!
!        ****************************************************************
!        *                                                              *
!        * LESS_BBOX_TARGET_TYPE RETURNS .TRUE. IF G1 < G2. THE         *
!        * COMPARISON IS FIRSTLY BASED ON THE POSSIBLE MINIMUM DISTANCE *
!        * SUCH THAT THE MOST LIKELY CANDIDATES ARE TREATED FIRST.      *
!        * IN CASE OF TIES THE BOUNDARY BOX ID IS CONSIDERED AND        *
!        * FINALLY THE COORDINATES. IT IS EXTREMELY UNLIKELY THAT THE   *
!        * COORDINATES WILL BE EVER COMPARED AND DIFFERENT, BUT IT IS   *
!        * INCLUDED FOR CONSISTENCY.                                    *
!        *                                                              *
!        ****************************************************************
!
         IMPLICIT NONE
!
!        FUNCTION ARGUMENTS.
!
         TYPE(BBOX_TARGET_TYPE), INTENT(IN) :: G1, G2
!
!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************
!
         ! COMPARE THE POSSIBLE MINIMUM DISTANCES.

         IF(G1%POS_DIST2 < G2%POS_DIST2) THEN
           LESS_BBOX_TARGET_TYPE = .TRUE.
           RETURN
         ELSE IF(G1%POS_DIST2 > G2%POS_DIST2) THEN
           LESS_BBOX_TARGET_TYPE = .FALSE.
           RETURN
         ENDIF

         ! COMPARE THE BOUNDING BOX ID'S.

         IF(G1%ID < G2%ID) THEN
           LESS_BBOX_TARGET_TYPE = .TRUE.
           RETURN
         ELSE IF(G1%ID > G2%ID) THEN
           LESS_BBOX_TARGET_TYPE = .FALSE.
           RETURN
         ENDIF

         ! G1 AND G2 ARE IDENTICAL. RETURN .FALSE.

         LESS_BBOX_TARGET_TYPE = .FALSE.

         END FUNCTION LESS_BBOX_TARGET_TYPE

       END MODULE ADT_DATA

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   module adt_utilities   ! The bulk of the ADT routines, public and private

   implicit none

!  Public procedures:

   public :: build_adt    ! Build an ADT search tree from the indicated grid
   public :: search_adt   ! Search the ADT for the cell closest to a target
                          ! point, and corresponding interpolation coefficients
                          ! applicable to data at the vertices of that cell
   public :: release_adt  ! Deallocates ADT storage before building another ADT
   public :: terminate    ! Diagnostic routine used by the ADT routines and
                          ! usable by the calling program

!  Private procedures common to all ADT variants:

   private :: qsort_bbox_target_type
   private :: qsort_reals
   private :: realloc_bbox_targets
   private :: realloc_front_leaves_new
   private :: realloc_stack
   private :: reallocate_stack

!  Generic interfaces:

   interface build_adt
      module procedure &
         build_structured_curve_adt,     &  ! 2D multiblock curve/2-point cells
         build_structured_surface_adt,   &  ! Multiblock surface grid/quad cells
         build_structured_volume_adt,    &  ! Multiblock volume grid/hex cells
         build_unstructured_surface_adt, &  ! Triangulated surface mesh
         build_unstructured_volume_adt,  &  ! Tetrahedral volume mesh
         build_mixed_cell_adt               ! Volume or surface mesh as a list
                                            ! of tri/tet/quad/hex/pyramid/prism
                                            ! cells using Fluent conventions
   end interface build_adt

   interface search_adt
      module procedure &
         search_structured_curve_adt,     & ! 2D multiblock curve/2-point cells
         search_structured_surface_adt,   & ! Multiblock surface grid/quad cells
         search_structured_volume_adt,    & ! Multiblock volume grid/hex cells
         search_unstructured_surface_adt, & ! Triangulated surface mesh
         search_unstructured_volume_adt,  & ! Tetrahedral volume mesh
         search_mixed_cell_adt              ! Volume or surface mesh as a list
                                            ! of tri/tet/quad/hex/pyramid/prism
                                            ! cells using Fluent conventions
   end interface search_adt

!  Internal procedures for module adt_utilities:

!  Specific build and search procedures follow in the above order.
!  Note that for the argument lists to be suitably unambiguous, the two
!  BUILD_[UN]STRUCTURED_VOLUME_ADT forms now have an extra UNUSED argument
!  to distinguish them from their BUILD_[UN]STRUCTURED_SURFACE_ADT analogues.
!
!  The private routines common to all of the ADT variants appear last below.

   contains

!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!      BUILD_ADT variants:
!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!      ******************************************************************

       SUBROUTINE BUILD_STRUCTURED_CURVE_ADT (NBLOCK, GRID, NCELL, J, CONN)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE 2-POINT CELLS OF THE INDICATED   *
!      * J LINE OF THE GIVEN MULTIBLOCK STRUCTURED 2D VOLUME GRID.      *
!      * ALL BLOCKS OF THE GRID ARE ASSUMED TO BE INDEXED CONSISTENTLY  *
!      * SUCH THAT THE (:,J) POINTS FORM A CONTINUOUS CURVE, WHERE J IS *
!      * MOST LIKELY TO BE 1 OR NJ.  TWO-SPACE DATA ARE INPUT, BUT THE  *
!      * THREE-SPACE TECHNIQUES OF THE EARLIER UTILITIES ARE RETAINED   *
!      * BY INTRODUCING Z = 0 EVERYWHERE (INTERNALLY).                  *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003                                      *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      *                                                                *
!      * 08-02-13:  David Saunders  Version of the structured surface   *
!      *            ELORET/NASA ARC routine from which this curve       *
!      *                            analogue has been adapted.
!      * 03-27-15:  David Saunders  Structured curve analogue added for *
!      *            ERC, Inc./ARC   2-space line/boundary intersection  *
!      *                            calculations needed for setting up  *
!      *                            line-of-sight data within an axi-   *
!      *                            symmetric flow solution.            *
!      * 04-13-15:    "       "     New argument J clashed with local J *
!      *                            and caused an unnecessary rotation  *
!      *                            of the data, now removed.           *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NBLOCK   ! # blocks in multiblock grid >= 1

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK)
                                        ! Multiblock 2-space volume grid;
                                        ! %x and %y are input; %z should be
                                        ! input also and be constant (zero)
                                        ! because 3-space bounding boxes
                                        ! are retained from the surface form

       INTEGER, INTENT (IN)  :: NCELL   ! # 2-pt. cells formed by the (:,J)
                                        ! points of all blocks

       INTEGER, INTENT (IN)  :: J       ! J is probably 1 or %nj, defining a
                                        ! boundary curve formed by all blocks

       INTEGER, INTENT (OUT) :: CONN(2,NCELL) ! Connectivity information

!      CONN(II,N) for the Nth 2-pt. cell uses II = 1 & 2 to store the block
!      number and the left index i of the cell

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER,        PARAMETER :: INITIAL_SIZE = 100
       REAL,           PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,           PARAMETER :: BIG_NEGATIVE = -1.E+30
       CHARACTER (26), PARAMETER :: BUILD_NAME = 'BUILD_STRUCTURED_CURVE_ADT'

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR

       INTEGER :: I, IB, II, JJ, JT, K, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS
       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS_NEW
       INTEGER, DIMENSION (:), ALLOCATABLE :: NBB_IDS
       INTEGER, DIMENSION (:), ALLOCATABLE :: NBB_IDS_NEW
       INTEGER, DIMENSION (:), ALLOCATABLE :: CUR_LEAF
       INTEGER, DIMENSION (:), ALLOCATABLE :: CUR_LEAF_NEW

       REAL :: DIST, TMP, XSPLIT

       REAL, DIMENSION (:), ALLOCATABLE :: XSORT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

!      The commented-out code should be feasible, treating CONN(:,:) as a
!      pointer instead of as allocatable (here and in the calling program),
!      but the Fortran 90 standard calls for an explicit interface.
!      Instead, we expect the calling program to count the structured grid cells
!      and do the allocation.  Assigning CONN can be done here.

!!!!   ! Count the 2-point cells formed by points (:,J) of all blocks:

!!!!   NCELL = 0
!!!!   DO IB = 1, NBLOCK
!!!!     NCELL = (GRID(IB)%NI - 1) + NCELL
!!!!   END DO

!!!!   ALLOCATE (CONN(2,NCELL), STAT=IERR)
!!!!   IF (IERR /= 0) ...

       NN = 0
       DO IB = 1, NBLOCK
         DO I = 1, GRID(IB)%NI - 1
           NN = NN + 1
           CONN(1,NN) = IB  ! Block # of 2-point cell NN
           CONN(2,NN) = I   ! Index i in that block for this cell
         END DO
       END DO

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.

       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       IF (ALLOCATED (BBOX_TARGETS)) DEALLOCATE (BBOX_TARGETS)
       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for BBOX_TARGETS.")

       IF (ALLOCATED (FRONT_LEAVES)) DEALLOCATE (FRONT_LEAVES)
       ALLOCATE (FRONT_LEAVES(NALLOC_FRONT_LEAVES),         STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for FRONT_LEAVES.")

       IF (ALLOCATED (FRONT_LEAVES_NEW)) DEALLOCATE (FRONT_LEAVES_NEW)
       ALLOCATE (FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for FRONT_LEAVES_NEW.")

       IF (ALLOCATED (STACK)) DEALLOCATE (STACK)
       ALLOCATE (STACK(NSTACK),                             STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for STACK.")

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NCELL - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NCELL == 1 INTO ACCOUNT.

       NLEAVES = NCELL - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! CELLS AND FOR THE ADT.

       IF (ALLOCATED (ADT)) DEALLOCATE (ADT)
       ALLOCATE (ADT(NLEAVES),   STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for ADT.")

       IF (ALLOCATED (XBBOX)) DEALLOCATE (XBBOX)
       ALLOCATE (XBBOX(6,NCELL), STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE (BUILD_NAME, &
          "Allocation failure for XBBOX.")

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE J CELLS.

       DO NN = 1, NCELL
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       NN = 0
       DO IB = 1, NBLOCK
         DO I = 1, GRID(IB)%NI - 1
           NN = NN + 1
           XBBOX(1,NN) = MIN (GRID(IB)%X(I,J,1),     &
                              GRID(IB)%X(I+1,J,1),   &
                              XBBOX(1,NN))
           XBBOX(4,NN) = MAX (GRID(IB)%X(I,J,1),     &
                              GRID(IB)%X(I+1,J,1),   &
                              XBBOX(4,NN))
           XBBOX(2,NN) = MIN (GRID(IB)%Y(I,J,1),     &
                              GRID(IB)%Y(I+1,J,1),   &
                              XBBOX(2,NN))
           XBBOX(5,NN) = MAX (GRID(IB)%Y(I,J,1),     &
                              GRID(IB)%Y(I+1,J,1),   &
                              XBBOX(5,NN))
           XBBOX(3,NN) = MIN (GRID(IB)%Z(I,J,1),     &
                              GRID(IB)%Z(I+1,J,1),   &
                              XBBOX(3,NN))
           XBBOX(6,NN) = MAX (GRID(IB)%Z(I,J,1),     &
                              GRID(IB)%Z(I+1,J,1),   &
                              XBBOX(6,NN))
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NCELL+1)/2
       ALLOCATE (BB_IDS(NCELL), BB_IDS_NEW(NCELL), &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NCELL),  STAT=IERR)
       IF (IERR /= 0) &
         CALL TERMINATE (BUILD_NAME, &
                         "Allocation failure for help arrays.")

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NCELL
       CUR_LEAF(1) = 1

       DO I = 1, NCELL
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO JT = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(JT)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO JT = 2, 6
               TMP = ADT(MM)%XMAX(JT) - ADT(MM)%XMIN(JT)
               IF(TMP > DIST) THEN
                 IDIR = JT
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO JT = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(JT)
               XSORT(JT-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO JT = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(JT)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT, STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE (BUILD_NAME, &
                         "Deallocation failure for help arrays.")

       END SUBROUTINE BUILD_STRUCTURED_CURVE_ADT

!      ******************************************************************

       SUBROUTINE BUILD_STRUCTURED_SURFACE_ADT (NBLOCK, GRID, NQUAD, CONN)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE QUAD CELLS OF THE GIVEN MULTI-   *
!      * BLOCK SURFACE GRID.  THE SURFACE MAY BE THE K = 1 LAYER OF A   *
!      * VOLUME GRID IF DESIRED -- ONLY THIS LAYER IS USED HERE, BUT    *
!      * ALL BLOCKS OF THE GRID WOULD NEED TO BE CONSISTENT.            *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003                                      *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      *                                                                *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      *            ELORET/NASA ARC                                     *
!      * 06-07-04:  David Saunders  Work directly with a multiblock     *
!      *                            grid -- no need to repack the nodes.*
!      * 07-10-04:    "      "      Switched the order of the indices   *
!      *                            for XBBOX in the hope of slightly   *
!      *                            better cache usage.                 *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NBLOCK ! # blocks in multiblock grid >= 1

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK)
                                              ! Multiblock surface grid,
                                              ! or possibly a volume grid
                                              ! of which only k = 1 is used

       INTEGER, INTENT (IN)  :: NQUAD ! # surface quads found in the grid

       INTEGER, INTENT (OUT) :: CONN(3,NQUAD) ! Connectivity information

!      CONN(II,N) for the Nth quad cell uses II = 1 : 3 to store the patch
!      (block) number and the i and j of the "lower left" vertex of the quad

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER, PARAMETER :: INITIAL_SIZE = 100
       REAL,    PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,    PARAMETER :: BIG_NEGATIVE = -1.E+30

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR

       INTEGER :: I, J, IB, II, JJ, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS
       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS_NEW
       INTEGER, DIMENSION (:), ALLOCATABLE :: NBB_IDS
       INTEGER, DIMENSION (:), ALLOCATABLE :: NBB_IDS_NEW
       INTEGER, DIMENSION (:), ALLOCATABLE :: CUR_LEAF
       INTEGER, DIMENSION (:), ALLOCATABLE :: CUR_LEAF_NEW

       REAL :: DIST, TMP, XSPLIT

       REAL, DIMENSION (:), ALLOCATABLE :: XSORT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

!      The commented-out code should be feasible, treating CONN(:,:) as a
!      pointer instead of as allocatable (here and in the calling program),
!      but the Fortran 90 standard calls for an explicit interface.
!      Instead, we expect the calling program to count the structured grid cells
!      and do the allocation.

!!!!   ! Count the surface quads:

!!!!   NQUAD = 0
!!!!   DO IB = 1, NBLOCK
!!!!     NQUAD = (GRID(IB)%NI - 1) * (GRID(IB)%NJ - 1) + NQUAD
!!!!   END DO

!!!!   ALLOCATE (CONN(3,NQUAD), STAT=IERR)
!!!!   IF (IERR /= 0)                 &
!!!!     CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
!!!!                     "Memory allocation failure for CONN(3,NQUAD).")

       ! Set up connectivity information that avoids repacking the grid
       ! coordinates into the list expected by Edwin's original implementation:

       NN = 0
       DO IB = 1, NBLOCK
         DO J = 1, GRID(IB)%NJ - 1
           DO I = 1, GRID(IB)%NI - 1
             NN = NN + 1
             CONN(1,NN) = IB
             CONN(2,NN) = I
             CONN(3,NN) = J
           END DO
         END DO
       END DO

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.


       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       IF (ALLOCATED (BBOX_TARGETS)) DEALLOCATE (BBOX_TARGETS)
       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for BBOX_TARGETS.")

       IF (ALLOCATED (FRONT_LEAVES)) DEALLOCATE (FRONT_LEAVES)
       ALLOCATE (FRONT_LEAVES(NALLOC_FRONT_LEAVES),         STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for FRONT_LEAVES.")

       IF (ALLOCATED (FRONT_LEAVES_NEW)) DEALLOCATE (FRONT_LEAVES_NEW)
       ALLOCATE (FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for FRONT_LEAVES_NEW.")

       IF (ALLOCATED (STACK)) DEALLOCATE (STACK)
       ALLOCATE (STACK(NSTACK),                             STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for STACK.")

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NQUAD - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NQUAD == 1 INTO ACCOUNT.

       NLEAVES = NQUAD - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! QUADRILATERALS AND FOR THE ADT.

       IF (ALLOCATED (ADT)) DEALLOCATE (ADT)
       ALLOCATE (ADT(NLEAVES),   STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for ADT.")

       IF (ALLOCATED (XBBOX)) DEALLOCATE (XBBOX)
       ALLOCATE (XBBOX(6,NQUAD), STAT=IERR)
       IF (IERR /= 0) CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
          "Memory allocation failure for XBBOX.")

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE QUADRILATERALS.

       DO NN = 1, NQUAD
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       NN = 0
       DO IB = 1, NBLOCK
         DO J = 1, GRID(IB)%NJ - 1
           DO I = 1, GRID(IB)%NI - 1
             NN = NN + 1
             XBBOX(1,NN) = MIN (GRID(IB)%X(I,J,1),     &
                                GRID(IB)%X(I+1,J,1),   &
                                GRID(IB)%X(I,J+1,1),   &
                                GRID(IB)%X(I+1,J+1,1), &
                                XBBOX(1,NN))
             XBBOX(4,NN) = MAX (GRID(IB)%X(I,J,1),     &
                                GRID(IB)%X(I+1,J,1),   &
                                GRID(IB)%X(I,J+1,1),   &
                                GRID(IB)%X(I+1,J+1,1), &
                                XBBOX(4,NN))
             XBBOX(2,NN) = MIN (GRID(IB)%Y(I,J,1),     &
                                GRID(IB)%Y(I+1,J,1),   &
                                GRID(IB)%Y(I,J+1,1),   &
                                GRID(IB)%Y(I+1,J+1,1), &
                                XBBOX(2,NN))
             XBBOX(5,NN) = MAX (GRID(IB)%Y(I,J,1),     &
                                GRID(IB)%Y(I+1,J,1),   &
                                GRID(IB)%Y(I,J+1,1),   &
                                GRID(IB)%Y(I+1,J+1,1), &
                                XBBOX(5,NN))
             XBBOX(3,NN) = MIN (GRID(IB)%Z(I,J,1),     &
                                GRID(IB)%Z(I+1,J,1),   &
                                GRID(IB)%Z(I,J+1,1),   &
                                GRID(IB)%Z(I+1,J+1,1), &
                                XBBOX(3,NN))
             XBBOX(6,NN) = MAX (GRID(IB)%Z(I,J,1),     &
                                GRID(IB)%Z(I+1,J,1),   &
                                GRID(IB)%Z(I,J+1,1),   &
                                GRID(IB)%Z(I+1,J+1,1), &
                                XBBOX(6,NN))
           END DO
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NQUAD+1)/2
       ALLOCATE (BB_IDS(NQUAD), BB_IDS_NEW(NQUAD), &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NQUAD),  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
                         "Memory allocation failure for help arrays.")

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NQUAD
       CUR_LEAF(1) = 1

       DO I = 1, NQUAD
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO J = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(J)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO J = 2, 6
               TMP = ADT(MM)%XMAX(J) - ADT(MM)%XMIN(J)
               IF(TMP > DIST) THEN
                 IDIR = J
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               XSORT(J-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT,  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_SURFACE_ADT", &
                         "Deallocation failure for help arrays.")

       END SUBROUTINE BUILD_STRUCTURED_SURFACE_ADT

!      ******************************************************************

       SUBROUTINE BUILD_STRUCTURED_VOLUME_ADT (NBLOCK, GRID, NHEX, CONN, UNUSED)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE HEX CELLS OF THE GIVEN MULTI-    *
!      * BLOCK VOLUME GRID.                                             *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003                                      *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      *                                                                *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter    *
!      *            ELORET/NASA ARC (packed list of quad cells version).*
!      * 06-07-04:  David Saunders  Work directly with a multiblock srf.*
!      *                            grid -- no need to repack the nodes.*
!      * 06-14-04:    "      "      Structured volume grid version.     *
!      * 07-09-04:    "      "      Switched the order of the indices   *
!      *                            for XBBOX in the hope of slightly   *
!      *                            better cache usage.                 *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                            New UNUSED argument avoids a clash  *
!      *                            with BUILD_STRUCTURED_SURFACE_ADT.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NBLOCK ! # blocks in multiblock grid >= 1

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK)
                                             ! Multiblock volume grid

       INTEGER, INTENT (IN)  :: NHEX  ! # volume cells found in the grid

       INTEGER, INTENT (OUT) :: CONN(4,NHEX) ! Connectivity information

       LOGICAL, INTENT (OUT) :: UNUSED  ! Added to make argument list distinct.

!      CONN(II,N) for the Nth hex cell uses II = 1 : 4 to store the patch
!      (block) number and the i,j,k of the "lower left" vertex of the cell

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER, PARAMETER :: INITIAL_SIZE = 100
       REAL,    PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,    PARAMETER :: BIG_NEGATIVE = -1.E+30

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR

       INTEGER :: I, J, K, IB, II, JJ, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       REAL    :: DIST, TMP, XSPLIT

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS,   BB_IDS_NEW,   &
                                              NBB_IDS,  NBB_IDS_NEW,  &
                                              CUR_LEAF, CUR_LEAF_NEW

       REAL,    DIMENSION (:), ALLOCATABLE :: XSORT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       UNUSED = .true.  ! To avoid compiler warnings about unused arguments.

!      The commented-out code should be feasible, treating CONN(:,:) as a
!      pointer instead of as allocatable (here and in the calling program),
!      but the Fortran 90 standard calls for an explicit interface.
!      Instead, we expect the calling program to count the structured grid cells
!      and do the allocation.

!!!!   ! Count the volume cells:

!!!!   NHEX = 0
!!!!   DO IB = 1, NBLOCK
!!!!     NHEX = (GRID(IB)%NI - 1) * (GRID(IB)%NJ - 1) * (GRID(IB)%NK - 1) + NHEX
!!!!   END DO

!!!!   ALLOCATE (CONN(4,NHEX), STAT=IERR)
!!!!   IF (IERR /= 0)                 &
!!!!     CALL TERMINATE ("BUILD_STRUCTURED_VOLUME_ADT", &
!!!!                     "Memory allocation failure for CONN(4,NHEX).")

       ! Set up indices that identify the implicitly-packed grid cells:

       NN = 0
       DO IB = 1, NBLOCK
         DO K = 1, GRID(IB)%NK - 1
           DO J = 1, GRID(IB)%NJ - 1
             DO I = 1, GRID(IB)%NI - 1
               NN = NN + 1
               CONN(1,NN) = IB
               CONN(2,NN) = I
               CONN(3,NN) = J
               CONN(4,NN) = K
             END DO
           END DO
         END DO
       END DO

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.


       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 &
                 FRONT_LEAVES(NALLOC_FRONT_LEAVES),         &
                 FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), &
                 STACK(NSTACK), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for BBOX_TARGETS, etc.")

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NHEX - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NHEX == 1 INTO ACCOUNT.

       NLEAVES = NHEX - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! CELLS AND FOR THE ADT.

       ALLOCATE (ADT(NLEAVES), XBBOX(6,NHEX), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for ADT and XBBOX.")

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE VOLUME CELLS.

       DO NN = 1, NHEX
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       NN = 0
       DO IB = 1, NBLOCK
         DO K = 1, GRID(IB)%NK - 1
           DO J = 1, GRID(IB)%NJ - 1
             DO I = 1, GRID(IB)%NI - 1
               NN = NN + 1
               XBBOX(1,NN) = MIN (GRID(IB)%X(I,J,K),       &
                                  GRID(IB)%X(I+1,J,K),     &
                                  GRID(IB)%X(I,J+1,K),     &
                                  GRID(IB)%X(I+1,J+1,K),   &
                                  GRID(IB)%X(I,J,K+1),     &
                                  GRID(IB)%X(I+1,J,K+1),   &
                                  GRID(IB)%X(I,J+1,K+1),   &
                                  GRID(IB)%X(I+1,J+1,K+1), &
                                  XBBOX(1,NN))
               XBBOX(4,NN) = MAX (GRID(IB)%X(I,J,K),       &
                                  GRID(IB)%X(I+1,J,K),     &
                                  GRID(IB)%X(I,J+1,K),     &
                                  GRID(IB)%X(I+1,J+1,K),   &
                                  GRID(IB)%X(I,J,K+1),     &
                                  GRID(IB)%X(I+1,J,K+1),   &
                                  GRID(IB)%X(I,J+1,K+1),   &
                                  GRID(IB)%X(I+1,J+1,K+1), &
                                  XBBOX(4,NN))
               XBBOX(2,NN) = MIN (GRID(IB)%Y(I,J,K),       &
                                  GRID(IB)%Y(I+1,J,K),     &
                                  GRID(IB)%Y(I,J+1,K),     &
                                  GRID(IB)%Y(I+1,J+1,K),   &
                                  GRID(IB)%Y(I,J,K+1),     &
                                  GRID(IB)%Y(I+1,J,K+1),   &
                                  GRID(IB)%Y(I,J+1,K+1),   &
                                  GRID(IB)%Y(I+1,J+1,K+1), &
                                  XBBOX(2,NN))
               XBBOX(5,NN) = MAX (GRID(IB)%Y(I,J,K),       &
                                  GRID(IB)%Y(I+1,J,K),     &
                                  GRID(IB)%Y(I,J+1,K),     &
                                  GRID(IB)%Y(I+1,J+1,K),   &
                                  GRID(IB)%Y(I,J,K+1),     &
                                  GRID(IB)%Y(I+1,J,K+1),   &
                                  GRID(IB)%Y(I,J+1,K+1),   &
                                  GRID(IB)%Y(I+1,J+1,K+1), &
                                  XBBOX(5,NN))
               XBBOX(3,NN) = MIN (GRID(IB)%Z(I,J,K),       &
                                  GRID(IB)%Z(I+1,J,K),     &
                                  GRID(IB)%Z(I,J+1,K),     &
                                  GRID(IB)%Z(I+1,J+1,K),   &
                                  GRID(IB)%Z(I,J,K+1),     &
                                  GRID(IB)%Z(I+1,J,K+1),   &
                                  GRID(IB)%Z(I,J+1,K+1),   &
                                  GRID(IB)%Z(I+1,J+1,K+1), &
                                  XBBOX(3,NN))
               XBBOX(6,NN) = MAX (GRID(IB)%Z(I,J,K),       &
                                  GRID(IB)%Z(I+1,J,K),     &
                                  GRID(IB)%Z(I,J+1,K),     &
                                  GRID(IB)%Z(I+1,J+1,K),   &
                                  GRID(IB)%Z(I,J,K+1),     &
                                  GRID(IB)%Z(I+1,J,K+1),   &
                                  GRID(IB)%Z(I,J+1,K+1),   &
                                  GRID(IB)%Z(I+1,J+1,K+1), &
                                  XBBOX(6,NN))
             END DO
           END DO
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NHEX+1)/2
       ALLOCATE (BB_IDS(NHEX),  BB_IDS_NEW(NHEX),  &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NHEX),   STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for help arrays.")

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NHEX
       CUR_LEAF(1) = 1

       DO I = 1, NHEX
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO J = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(J)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO J = 2, 6
               TMP = ADT(MM)%XMAX(J) - ADT(MM)%XMIN(J)
               IF(TMP > DIST) THEN
                 IDIR = J
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               XSORT(J-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT,  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_STRUCTURED_VOLUME_ADT", &
                         "Deallocation failure for help arrays.")

       END SUBROUTINE BUILD_STRUCTURED_VOLUME_ADT

!      ******************************************************************

       SUBROUTINE BUILD_UNSTRUCTURED_SURFACE_ADT (NNODE, NTRI, CONN, COOR)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE GIVEN SURFACE ELEMENTS.          *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003  Packed quads. version.              *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      *            ELORET/NASA ARC                                     *
!      * 06-25-04     "       "     Version for a list of triangles.    *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTRI) too. *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NNODE, &     ! # (x,y,z)s packed in COOR(1:3,*)
                               NTRI         ! # triangles in the list

       INTEGER, INTENT (IN) :: CONN(3,NTRI) ! Triangle connectivity info

       REAL,    INTENT (IN) :: COOR(3,NNODE)! (x,y,z)s pointed to by CONN(1:3,*)

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER, PARAMETER :: INITIAL_SIZE = 100
       REAL,    PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,    PARAMETER :: BIG_NEGATIVE = -1.E+30

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR

       INTEGER :: I, J, II, JJ, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       REAL    :: DIST, TMP, XSPLIT

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS,   BB_IDS_NEW,   &
                                              NBB_IDS,  NBB_IDS_NEW,  &
                                              CUR_LEAF, CUR_LEAF_NEW

       REAL,    DIMENSION (:), ALLOCATABLE :: XSORT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.


       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 &
                 FRONT_LEAVES(NALLOC_FRONT_LEAVES),         &
                 FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), &
                 STACK(NSTACK), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_SURFACE_ADT", &
                         "Memory allocation failure for BBOX_TARGETS, etc.")

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NTRI - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NTRI == 1 INTO ACCOUNT.

       NLEAVES = NTRI - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! SURFACE ELEMENTS AND FOR THE ADT.

       ALLOCATE (ADT(NLEAVES), XBBOX(6,NTRI), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_SURFACE_ADT", &
                         "Memory allocation failure for ADT and XBBOX.")

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE TRIANGLES.

       DO NN = 1, NTRI
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       DO II = 1, 3
         DO NN = 1, NTRI
           MM = CONN(II,NN)
           XBBOX(1,NN) = MIN (XBBOX(1,NN), COOR(1,MM))
           XBBOX(4,NN) = MAX (XBBOX(4,NN), COOR(1,MM))
           XBBOX(2,NN) = MIN (XBBOX(2,NN), COOR(2,MM))
           XBBOX(5,NN) = MAX (XBBOX(5,NN), COOR(2,MM))
           XBBOX(3,NN) = MIN (XBBOX(3,NN), COOR(3,MM))
           XBBOX(6,NN) = MAX (XBBOX(6,NN), COOR(3,MM))
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NTRI+1)/2
       ALLOCATE (BB_IDS(NTRI), BB_IDS_NEW(NTRI), &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NTRI),  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_SURFACE_ADT", &
                         "Memory allocation failure for help arrays.")

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NTRI
       CUR_LEAF(1) = 1

       DO I = 1, NTRI
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO J = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(J)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO J = 2, 6
               TMP = ADT(MM)%XMAX(J) - ADT(MM)%XMIN(J)
               IF(TMP > DIST) THEN
                 IDIR = J
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               XSORT(J-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT,  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_SURFACE_ADT", &
                         "Deallocation failure for help arrays.")

       END SUBROUTINE BUILD_UNSTRUCTURED_SURFACE_ADT

!      ******************************************************************

       SUBROUTINE BUILD_UNSTRUCTURED_VOLUME_ADT (NNODE, NTET, CONN, COOR, &
                                                 UNUSED)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE GIVEN MESH CELLS.                *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003  Packed quads. version.              *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      *            ELORET/NASA ARC                                     *
!      * 06-25-04     "       "     Version for a list of triangles.    *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTET) too. *
!      * 08-13-04     "       "     Version for a tetrahedral mesh.     *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                            New UNUSED argument needed because  *
!      *                            of BUILD_UNSTRUCTURED_SURFACE_ADT.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NNODE, &     ! # (x,y,z)s packed in COOR(1:3,*)
                               NTET         ! # tetrahedra in the list

       INTEGER, INTENT (IN) :: CONN(4,NTET) ! Connectivity info

       REAL,    INTENT (IN) :: COOR(3,NNODE)! (x,y,z)s pointed to by CONN(1:4,*)

       LOGICAL, INTENT (OUT) :: UNUSED  ! Added to make argument list distinct.

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER, PARAMETER :: INITIAL_SIZE = 100
       REAL,    PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,    PARAMETER :: BIG_NEGATIVE = -1.E+30

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR

       INTEGER :: I, J, II, JJ, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       REAL    :: DIST, TMP, XSPLIT

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS,   BB_IDS_NEW,   &
                                              NBB_IDS,  NBB_IDS_NEW,  &
                                              CUR_LEAF, CUR_LEAF_NEW

       REAL,    DIMENSION (:), ALLOCATABLE :: XSORT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       UNUSED = .true.  ! To avoid compiler warnings about unused arguments.

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.


       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 &
                 FRONT_LEAVES(NALLOC_FRONT_LEAVES),         &
                 FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), &
                 STACK(NSTACK), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for BBOX_TARGETS, etc.")

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NTET - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NTET == 1 INTO ACCOUNT.

       NLEAVES = NTET - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! MESH CELLS AND FOR THE ADT.

       ALLOCATE (ADT(NLEAVES), XBBOX(6,NTET), STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for ADT and XBBOX.")

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE TRIANGLES.

       DO NN = 1, NTET
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       DO II = 1, 4
         DO NN = 1, NTET
           MM = CONN(II,NN)
           XBBOX(1,NN) = MIN (XBBOX(1,NN), COOR(1,MM))
           XBBOX(4,NN) = MAX (XBBOX(4,NN), COOR(1,MM))
           XBBOX(2,NN) = MIN (XBBOX(2,NN), COOR(2,MM))
           XBBOX(5,NN) = MAX (XBBOX(5,NN), COOR(2,MM))
           XBBOX(3,NN) = MIN (XBBOX(3,NN), COOR(3,MM))
           XBBOX(6,NN) = MAX (XBBOX(6,NN), COOR(3,MM))
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NTET+1)/2
       ALLOCATE (BB_IDS(NTET), BB_IDS_NEW(NTET), &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NTET),  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_VOLUME_ADT", &
                         "Memory allocation failure for help arrays.")

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NTET
       CUR_LEAF(1) = 1

       DO I = 1, NTET
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO J = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(J)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO J = 2, 6
               TMP = ADT(MM)%XMAX(J) - ADT(MM)%XMIN(J)
               IF(TMP > DIST) THEN
                 IDIR = J
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               XSORT(J-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT,  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_UNSTRUCTURED_VOLUME_ADT", &
                         "Deallocation failure for help arrays.")

       END SUBROUTINE BUILD_UNSTRUCTURED_VOLUME_ADT

!      ******************************************************************

       SUBROUTINE BUILD_MIXED_CELL_ADT (NNODE, NCELL, CONN, COOR, IERR)

!      ******************************************************************
!      *                                                                *
!      * BUILD_*_ADT BUILDS THE 6-DIMENSIONAL ALTERNATING DIGITAL TREE  *
!      * FOR THE BOUNDING BOXES OF THE GIVEN MIXED-TYPE MESH CELLS.     *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE, Stanford University        *
!      * STARTING DATE: 11-06-2003  Packed quads. version.              *
!      * LAST MODIFIED: 11-21-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      *            ELORET/NASA ARC                                     *
!      * 06-25-04     "       "     Version for a list of triangles.    *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTET) too. *
!      * 08-13-04     "       "     Version for a tetrahedral mesh.     *
!      * 06-06-13   David Saunders  Generalization for a list of mixed  *
!      *            ERC Inc./ARC    cell types (US3D solver in mind).   *
!      *                            IERR is now an argument.            *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       INTEGER, INTENT (IN) :: NNODE, &     ! # (x,y,z)s packed in COOR(1:3,*)
                               NCELL        ! # cells in the list

       INTEGER, INTENT (IN) :: CONN(0:8,NCELL)  ! Connectivity info, presently
                                            ! limited to cells with up to 8
                                            ! vertices or nodes;
                                            ! CONN(0,N) = cell type for cell N
                                            ! as hard-coded below;
                                            ! CONN(1:NVERT,N) = vertex/node #s,
                                            ! where # vertices is derived from
                                            ! cell type as shown below;
                                            ! 8 here should match the largest
                                            ! entry in NVERT_PER_CELL below

       REAL,    INTENT (IN) :: COOR(3,NNODE)! (x,y,z)s pointed to by CONN(1:x,*)

       INTEGER, INTENT (OUT) :: IERR        ! Nonzero => fatal error (now an
                                            ! argument to allow proper clean-up
                                            ! by parallelized applications)

!      LOCAL CONSTANTS:
!      ----------------

       INTEGER, PARAMETER :: INITIAL_SIZE = 100
       REAL,    PARAMETER :: BIG_POSITIVE = +1.E+30
       REAL,    PARAMETER :: BIG_NEGATIVE = -1.E+30

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: I, J, II, JJ, LL, MM, NN, NF1, NF2
       INTEGER :: NLEAVES_TO_BE_DIVIDED, NLEAVES_TOT
       INTEGER :: NLEAVES_TO_BE_DIVIDED_NEW, IDIR

       REAL    :: DIST, TMP, XSPLIT

       INTEGER, DIMENSION (:), ALLOCATABLE :: BB_IDS,   BB_IDS_NEW,   &
                                              NBB_IDS,  NBB_IDS_NEW,  &
                                              CUR_LEAF, CUR_LEAF_NEW

       REAL,    DIMENSION (:), ALLOCATABLE :: XSORT

!      US3D-specific extensions for mixed cell types:
!      ----------------------------------------------

       INTEGER :: ITYPE
       INTEGER :: NVERT_PER_CELL(7)  ! # vertices for each cell type

       DATA NVERT_PER_CELL &  ! These follow Fluent convention
         /3,               &  ! 1 = triangle
          4,               &  ! 2 = tetrahedron
          4,               &  ! 3 = quadrilateral
          8,               &  ! 4 = hexahedron
          5,               &  ! 5 = pyramid with quadrilateral base
          6,               &  ! 6 = prism with triangular cross-section
          2/                  ! 7 = line segement (not a Fluent type)

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE NALLOC_BBOX, NALLOC_FRONT_LEAVES AND
       ! NALLOC_FRONT_LEAVES_NEW TO 100 AND ALLOCATE THE MEMORY FOR THE
       ! CORRESPONDING ARRAYS. ALTHOUGH THIS ARRAY IS NOT NEEDED IN THIS
       ! ROUTINE, IT CAN BE SEEN AS AN INITIALIZATION AND THUS THIS IS
       ! THE APPROPRIATE PLACE TO ALLOCATE IT. THE SAME FOR THE STACK
       ! ARRAY FOR THE QSORT ROUTINE.


       NALLOC_BBOX             = INITIAL_SIZE
       NALLOC_FRONT_LEAVES     = INITIAL_SIZE
       NALLOC_FRONT_LEAVES_NEW = INITIAL_SIZE
       NSTACK                  = INITIAL_SIZE

       ALLOCATE (BBOX_TARGETS(NALLOC_BBOX),                 &
                 FRONT_LEAVES(NALLOC_FRONT_LEAVES),         &
                 FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), &
                 STACK(NSTACK), STAT=IERR)
       IF (IERR /= 0) THEN
         CALL TERMINATE ("BUILD_MIXED_CELL_ADT", &
                         "Memory allocation failure for BBOX_TARGETS, etc.")
         GO TO 99
       END IF

       ! DETERMINE THE NUMBER OF LEAVES OF THE ADT. IT CAN BE PROVED THAT
       ! NLEAVES EQUALS NCELL - 1 FOR AN OPTIMALLY BALANCED TREE.
       ! TAKE THE EXCEPTIONAL CASE OF NCELL == 1 INTO ACCOUNT.

       NLEAVES = NCELL - 1
       NLEAVES = MAX (NLEAVES, 1)

       ! ALLOCATE THE MEMORY FOR THE BOUNDING BOX COORDINATES OF THE
       ! MESH CELLS AND FOR THE ADT.

       ALLOCATE (ADT(NLEAVES), XBBOX(6,NCELL), STAT=IERR)
       IF (IERR /= 0) THEN
         CALL TERMINATE ("BUILD_MIXED_CELL_ADT", &
                         "Memory allocation failure for ADT and XBBOX.")
         GO TO 99
       END IF

       ! DETERMINE THE BOUNDING BOX COORDINATES OF THE CELLS.

       DO NN = 1, NCELL
         XBBOX(1:3,NN) = BIG_POSITIVE
         XBBOX(4:6,NN) = BIG_NEGATIVE
       END DO

       DO NN = 1, NCELL
         ITYPE = CONN(0,NN)
         DO II = 1, NVERT_PER_CELL(ITYPE)
           MM = CONN(II,NN)
           XBBOX(1,NN) = MIN (XBBOX(1,NN), COOR(1,MM))
           XBBOX(4,NN) = MAX (XBBOX(4,NN), COOR(1,MM))
           XBBOX(2,NN) = MIN (XBBOX(2,NN), COOR(2,MM))
           XBBOX(5,NN) = MAX (XBBOX(5,NN), COOR(2,MM))
           XBBOX(3,NN) = MIN (XBBOX(3,NN), COOR(3,MM))
           XBBOX(6,NN) = MAX (XBBOX(6,NN), COOR(3,MM))
         END DO
       END DO

       ! ALLOCATE THE MEMORY FOR THE ARRAYS CONTROLLING THE SUBDIVISION
       ! OF THE ADT.

       NN = (NCELL+1)/2
       ALLOCATE (BB_IDS(NCELL), BB_IDS_NEW(NCELL), &
                 NBB_IDS(0:NN), NBB_IDS_NEW(0:NN), &
                 CUR_LEAF(NN),  CUR_LEAF_NEW(NN),  &
                 XSORT(NCELL),  STAT=IERR)
       IF (IERR /= 0) THEN
         CALL TERMINATE ("BUILD_MIXED_CELL_ADT", &
                         "Memory allocation failure for help arrays.")
         GO TO 99
       END IF

       ! INITIALIZE THE ARRAYS BB_IDS, NBB_IDS AND CUR_LEAF, SUCH THAT
       ! ALL BOUNDING BOXES BELONG TO THE ROOT LEAF. ALSO SET THE
       ! COUNTERS NLEAVES_TO_BE_DIVIDED AND NLEAVES_TOT TO 1.

       NBB_IDS(0)  = 0; NBB_IDS(1) = NCELL
       CUR_LEAF(1) = 1

       DO I = 1, NCELL
         BB_IDS(I) = I
       END DO

       NLEAVES_TO_BE_DIVIDED = 1
       NLEAVES_TOT = 1

       ! LOOP TO SUBDIVIDE THE LEAVES. THE DIVISION IS SUCH THAT THE
       ! ADT IS OPTIMALLY BALANCED.

       LEAF_DIVISION: DO

         ! CRITERION TO EXIT THE LOOP.

         IF (NLEAVES_TO_BE_DIVIDED == 0) EXIT

         ! INITIALIZATIONS FOR THE NEXT ROUND OF SUBDIVISIONS.

         NLEAVES_TO_BE_DIVIDED_NEW = 0
         NBB_IDS_NEW(0) = 0

         ! LOOP OVER THE CURRENT NUMBER OF LEAVES TO BE DIVIDED.

         CURRENT_LEAVES: DO I = 1, NLEAVES_TO_BE_DIVIDED

           ! STORE THE NUMBER OF BOUNDING BOXES PRESENT IN THE LEAF
           ! IN NN, THE CURRENT LEAF NUMBER IN MM AND I-1 IN II.

           II = I-1
           NN = NBB_IDS(I) - NBB_IDS(II)
           MM = CUR_LEAF(I)

           ! DETERMINE THE BOUNDING BOX COORDINATES OF THIS LEAF.

           LL = BB_IDS(NBB_IDS(II)+1)
           ADT(MM)%XMIN(1) = XBBOX(1,LL);  ADT(MM)%XMAX(1) = XBBOX(1,LL)
           ADT(MM)%XMIN(2) = XBBOX(2,LL);  ADT(MM)%XMAX(2) = XBBOX(2,LL)
           ADT(MM)%XMIN(3) = XBBOX(3,LL);  ADT(MM)%XMAX(3) = XBBOX(3,LL)
           ADT(MM)%XMIN(4) = XBBOX(4,LL);  ADT(MM)%XMAX(4) = XBBOX(4,LL)
           ADT(MM)%XMIN(5) = XBBOX(5,LL);  ADT(MM)%XMAX(5) = XBBOX(5,LL)
           ADT(MM)%XMIN(6) = XBBOX(6,LL);  ADT(MM)%XMAX(6) = XBBOX(6,LL)

           DO J = (NBB_IDS(II)+2), NBB_IDS(I)
             LL = BB_IDS(J)

             ADT(MM)%XMIN(1) = MIN(ADT(MM)%XMIN(1), XBBOX(1,LL))
             ADT(MM)%XMIN(2) = MIN(ADT(MM)%XMIN(2), XBBOX(2,LL))
             ADT(MM)%XMIN(3) = MIN(ADT(MM)%XMIN(3), XBBOX(3,LL))
             ADT(MM)%XMIN(4) = MIN(ADT(MM)%XMIN(4), XBBOX(4,LL))
             ADT(MM)%XMIN(5) = MIN(ADT(MM)%XMIN(5), XBBOX(5,LL))
             ADT(MM)%XMIN(6) = MIN(ADT(MM)%XMIN(6), XBBOX(6,LL))

             ADT(MM)%XMAX(1) = MAX(ADT(MM)%XMAX(1), XBBOX(1,LL))
             ADT(MM)%XMAX(2) = MAX(ADT(MM)%XMAX(2), XBBOX(2,LL))
             ADT(MM)%XMAX(3) = MAX(ADT(MM)%XMAX(3), XBBOX(3,LL))
             ADT(MM)%XMAX(4) = MAX(ADT(MM)%XMAX(4), XBBOX(4,LL))
             ADT(MM)%XMAX(5) = MAX(ADT(MM)%XMAX(5), XBBOX(5,LL))
             ADT(MM)%XMAX(6) = MAX(ADT(MM)%XMAX(6), XBBOX(6,LL))
           END DO

           ! DETERMINE THE SITUATION. THIS IS EITHER A TERMINAL LEAF,
           ! NN <= 2, OR A LEAF THAT MUST BE REFINED.

           TERMINAL_TEST: IF (NN <= 2) THEN

             ! TERMINAL LEAF. STORE THE ID'S OF THE BOUNDING BOXES
             ! IN CHILDREN WITH NEGATIVE NUMBERS.

             ADT(MM)%CHILDREN(1) = -BB_IDS(NBB_IDS(II)+1)
             ADT(MM)%CHILDREN(2) = -BB_IDS(NBB_IDS(I))

           ELSE TERMINAL_TEST

             ! LEAF MUST BE DIVIDED FURTHER. DETERMINE THE DIRECTION IN
             ! WHICH THE LEAF MUST BE DIVIDED. THE DIVISION IS SUCH THAT
             ! ISOTROPY IS REACHED AS QUICKLY AS POSSIBLE, I.E. THE
             ! LARGEST DISTANCE IS SPLIT.

             IDIR = 1
             DIST = ADT(MM)%XMAX(1) - ADT(MM)%XMIN(1)

             DO J = 2, 6
               TMP = ADT(MM)%XMAX(J) - ADT(MM)%XMIN(J)
               IF(TMP > DIST) THEN
                 IDIR = J
                 DIST = TMP
               END IF
             END DO

             ! DETERMINE THE SORTED VERSION OF THE COORDINATES IN
             ! THE DIRECTION IDIR.

             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               XSORT(J-NBB_IDS(II)) = XBBOX(IDIR,LL)
             END DO

             CALL QSORT_REALS (XSORT, NN)

             ! DETERMINE THE SPLIT COORDINATE SUCH THAT HALF THE NUMBER
             ! OF FACES IS STORED IN THE LEFT LEAF AND THE OTHER HALF IN
             ! THE RIGHT.

             JJ     = (NN+1)/2
             XSPLIT = XSORT(JJ)

             ! INITIALIZE THE COUNTERS NF1 AND NF2, SUCH THAT THEY
             ! CORRESPOND TO THE CORRECT ENTRIES IN NBB_IDS_NEW.

             NF1 = NBB_IDS_NEW (NLEAVES_TO_BE_DIVIDED_NEW)
             NF2 = NF1 + JJ

             ! LOOP OVER THE BOUNDING BOXES OF THE CURRENT LEAF AND
             ! DIVIDE THEM. MAKE SURE THAT LEAF 1 DOES NOT GET MORE THAN
             ! HALF THE NUMBER OF FACES + 1. THIS SITUATION COULD OCCUR
             ! WHEN MULTIPLE FACES HAVE THE SAME SPLIT COORDINATE.

             JJ = NF2
             DO J = (NBB_IDS(II)+1), NBB_IDS(I)
               LL = BB_IDS(J)
               IF (XBBOX(IDIR,LL) > XSPLIT .OR. NF1 == JJ) THEN
                 NF2 = NF2 + 1
                 BB_IDS_NEW(NF2) = LL
               ELSE
                 NF1 = NF1 + 1
                 BB_IDS_NEW(NF1) = LL
               END IF
             END DO

             ! STORE THE PROPERTIES OF THE NEW LEFT LEAF. THIS LEAF
             ! WILL ALWAYS BE CREATED.

             NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
             NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF1

             NLEAVES_TOT = NLEAVES_TOT + 1
             ADT(MM)%CHILDREN(1) = NLEAVES_TOT
             CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ! THE RIGHT LEAF WILL ONLY BE CREATED IF IT HAS MORE THAN
             ! ONE BOUNDING BOX IN IT, I.E. IF THE ORIGINAL LEAF HAS MORE
             ! THAN THREE BOUNDING BOXES. IF THE NEW LEAF ONLY HAS ONE
             ! BOUNDING BOX IN IT, IT IS NOT CREATED; INSTEAD THE
             ! BOUNDING BOX IS STORED IN THE CURRENT LEAF.

             IF (NN > 3) THEN

               ! RIGHT LEAF IS CREATED. STORE ITS PROPERTIES.

               NLEAVES_TO_BE_DIVIDED_NEW = NLEAVES_TO_BE_DIVIDED_NEW + 1
               NBB_IDS_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NF2

               NLEAVES_TOT = NLEAVES_TOT + 1
               ADT(MM)%CHILDREN(2) = NLEAVES_TOT
               CUR_LEAF_NEW(NLEAVES_TO_BE_DIVIDED_NEW) = NLEAVES_TOT

             ELSE

               ! RIGHT LEAF IS NOT CREATED. INSTEAD THE BOUNDING BOX
               ! ID IS STORED IN THE CURRENT LEAF.

               ADT(MM)%CHILDREN(2) = -BB_IDS_NEW(NF2)

             END IF

           END IF TERMINAL_TEST

         END DO CURRENT_LEAVES

         ! COPY THE NEW VALUES OF THE BOUNDING BOX ID'S AND THE LEAVES
         ! TO BE DIVIDED INTO THE ONES CONTROLLING THE DIVISION, SUCH
         ! THAT THE NEXT LEVEL OF THE ADT CAN BE CREATED.

         NLEAVES_TO_BE_DIVIDED = NLEAVES_TO_BE_DIVIDED_NEW
         DO I = 1, NLEAVES_TO_BE_DIVIDED
           NBB_IDS(I)  = NBB_IDS_NEW(I)
           CUR_LEAF(I) = CUR_LEAF_NEW(I)
         END DO

         DO I = 1, NBB_IDS(NLEAVES_TO_BE_DIVIDED)
           BB_IDS(I) = BB_IDS_NEW(I)
         END DO

       END DO LEAF_DIVISION

       ! RELEASE THE MEMORY OF THE HELP ARRAYS NEEDED FOR THE
       ! CONSTRUCTION OF THE TREE.

       DEALLOCATE (BB_IDS, BB_IDS_NEW, NBB_IDS, NBB_IDS_NEW, &
                   CUR_LEAF, CUR_LEAF_NEW, XSORT,  STAT=IERR)
       IF (IERR /= 0)                 &
         CALL TERMINATE ("BUILD_MIXED_CELL_ADT", &
                         "Deallocation failure for help arrays.")
 99    RETURN

       END SUBROUTINE BUILD_MIXED_CELL_ADT

!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!      SEARCH_ADT variants:
!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!      ******************************************************************

       SUBROUTINE SEARCH_STRUCTURED_CURVE_ADT (TARGET_COOR, ICELL, P, Q,     &
                                               DIST2, INIT_DISTANCE, NBLOCK, &
                                               GRID, NCELL, J, CONN, XB)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE 2-PT. CURVE CELL WHICH CONTAINS     *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.  THE CELL IS ON THE   *
!      * INDICATED J LINE OF CONSISTENTLY INDEXED CELLS IN A 2D MULTI-  *
!      * BLOCK VOLUME GRID, WHERE J IS PROBABLY 1 OR NJ.                *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003                                      *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      *                                                                *
!      * 08-02-13:  David Saunders  Version of the structured surface   *
!      *            ELORET/NASA ARC routine from which this curve       *
!                                   analogue has been adapted.          *
!      * 03-28-15:  David Saunders  Structured curve analogue added for *
!      *            ERC, Inc./ARC   2-space line/boundary intersection  *
!      *                            calculations needed for setting up  *
!      *                            line-of-sight data within an axi-   *
!      *                            symmetric flow solution.            *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT(IN)    :: TARGET_COOR(2)      ! Target (x,y)

       INTEGER, INTENT(OUT)   :: ICELL               ! CONN(:,ICELL) points to
                                                     ! the best cell found
       REAL,    INTENT(OUT)   :: P, Q                ! Corresponding interpo-
                                                     ! lation coefs. in [0,1]
       REAL,    INTENT(INOUT) :: DIST2               ! Corresponding squared
                                                     ! distance found, normally
                                                     ! (but see INIT_DISTANCE)
       LOGICAL, INTENT(IN)    :: INIT_DISTANCE       ! Enter .T. normally;
                                                     ! allows for a quick
                                                     ! return in some circum-
                                                     ! stances (with DIST2)
       INTEGER, INTENT(IN)    :: NBLOCK              ! Number of grid blocks

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK) ! Multiblock 2D vol. grid

       INTEGER, INTENT(IN)    :: NCELL               ! Number of 2-pt. cells
                                                     ! along the line J
       INTEGER, INTENT(IN)    :: J                   ! Defines the curve within
                                                     ! consistently indexed grid
                                                     ! blocks; probably 1 or nj
       INTEGER, INTENT(IN)    :: CONN(2,NCELL)       ! Block # and cell I for
                                                     ! each 2-pt. cell on line J
       REAL,    INTENT(OUT)   :: XB(2)               ! (x,y) of the projection
                                                     ! to the nearest 2-pt. cell
!      LOCAL CONSTANTS:
!      ----------------

       REAL,           PARAMETER :: LARGE = 1.E+37,  &
                                    ZERO  = 0.0
       CHARACTER (27), PARAMETER :: SEARCH_NAME = 'SEARCH_STRUCTURED_CURVE_ADT'

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR
       INTEGER :: I, IB, II, L, MM, NN
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       REAL :: DD1, DD2, DX, DY, DZ, U, V, X, Y, Z

       REAL, DIMENSION(3) :: X1, X2, XF, XTARGET

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF (INIT_DISTANCE) DIST2 = LARGE
       NPOS_BBOXES = 0

       X     = TARGET_COOR(1);  XTARGET(1) = X
       Y     = TARGET_COOR(2);  XTARGET(2) = Y
       Z     = ZERO;            XTARGET(3) = ZERO
       X1(3) = ZERO
       X2(3) = ZERO

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN(DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE QUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE (SEARCH_NAME, &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE (SEARCH_NAME, &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE TWO-POINT CELL.     *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS CELL IN NN.

         NN = BBOX_TARGETS(II)%ID
         IB = CONN(1,NN) ! Grid block number
         I  = CONN(2,NN) ! Left index on line J

         X1(1) = GRID(IB)%X(I,J,1)
         X2(1) = GRID(IB)%X(I+1,J,1)

         X1(2) = GRID(IB)%Y(I,J,1)
         X2(2) = GRID(IB)%Y(I+1,J,1)

         CALL NEAREST_EDGE_POINT (X1, X2, XTARGET, XF, U, V, DD1)

         IF(DD1 < DIST2) THEN
           DIST2 = DD1
           ICELL = NN
           P     = U
           Q     = V
           XB(:) = XF(1:2)
         ENDIF

       ENDDO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_STRUCTURED_CURVE_ADT

!      ******************************************************************

       SUBROUTINE SEARCH_STRUCTURED_SURFACE_ADT (TARGET_COOR, IQUAD, U, V,     &
                                                 DIST2, INIT_DISTANCE, NBLOCK, &
                                                 GRID, NQUAD, CONN, XB)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE QUADRILATERAL CELL WHICH CONTAINS   *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.                       *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003                                      *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      *                                                                *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 05-26-04:  ELORET/NASA ARC Eliminated handling of triangular   *
!      *                            surface elements to avoid carrying  *
!      *                            around the ELTYP(*) array.          *
!      * 06-07-04   David Saunders  Work directly with a multiblock     *
!      *                            grid - no need to repack the nodes. *
!      * 07-10-04:    "      "      Switched the order of the indices   *
!      *                            for XBBOX in the hope of slightly   *
!      *                            better cache usage.                 *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT(IN)    :: TARGET_COOR(3)      ! Target (x,y,z)

       INTEGER, INTENT(OUT)   :: IQUAD               ! CONN(:,IQUAD) points to
                                                     ! the best cell found
       REAL,    INTENT(OUT)   :: U, V                ! Corresponding interpo-
                                                     ! lation coefs. in [0,1]
       REAL,    INTENT(INOUT) :: DIST2               ! Corresponding squared
                                                     ! distance found, normally
                                                     ! (but see INIT_DISTANCE)
       LOGICAL, INTENT(IN)    :: INIT_DISTANCE       ! Enter .T. normally;
                                                     ! allows for a quick
                                                     ! return in some circum-
                                                     ! stances (with DIST2)
       INTEGER, INTENT(IN)    :: NBLOCK              ! Number of grid blocks

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK) ! Multiblock surface grid;
                                                     ! may be a volume grid of
                                                     ! which only k = 1 is used
       INTEGER, INTENT(IN)    :: NQUAD               ! Number of surface quads

       INTEGER, INTENT(IN)    :: CONN(3,NQUAD)       ! Patch # and (i,j) for
                                                     ! each surface quad
       REAL,    INTENT(OUT)   :: XB(3)               ! (x,y,z) of the projection
                                                     ! to the nearest quad cell
!      LOCAL CONSTANTS:
!      ----------------

!      PARAMETERS DESCRIBING THE MAXIMUM NUMBER OF ITERATIONS ALLOWED
!      AND THE THRESHOLD FOR STOPPING THE NEWTON ALGORITHM TO COMPUTE
!      THE PROJECTION ONTO THE QUADRILATERAL SURFACE.

       INTEGER, PARAMETER :: NITER_MAX = 15
       REAL,    PARAMETER :: EPS_STOP  = 1.E-5

!      Other constants previously obtained from a module:

       REAL,    PARAMETER :: EPS    = 1.E-25,  &
                             FOURTH = 0.25,    &
                             HALF   = 0.5,     &
                             LARGE  = 1.E+37,  &
                             ONE    = 1.0,     &
                             THIRD  = 1.0/3.0, &
                             ZERO   = 0.0
!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR
       INTEGER :: I, IB, II, J, L, MM, NN, ITER
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       REAL :: X, Y, Z, DX, DY, DZ
       REAL :: DD1, DD2
       REAL :: UU, VV, UUVV, DU, DV, UUOLD, VVOLD
       REAL :: INV_LEN, VN

       REAL, DIMENSION(3) :: X1, X21, X41, X3142, X32
       REAL, DIMENSION(3) :: X31, X2, X3, X4, N1, N2, N3
       REAL, DIMENSION(3) :: A, B, AN, BN, N, VF, VT, XF

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF (INIT_DISTANCE) DIST2 = LARGE
       NPOS_BBOXES = 0

       X = TARGET_COOR(1)
       Y = TARGET_COOR(2)
       Z = TARGET_COOR(3)

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN(DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE QUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_STRUCTURED_SURFACE_ADT", &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_STRUCTURED_SURFACE_ADT", &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE QUADRILATERAL       *
!      *         ELEMENT BY APPLYING A NEWTON ALGORITHM. THIS IS DONE   *
!      *         BY PROJECTING THE VECTOR FROM THE CURRENT ACTIVE       *
!      *         POINT ON THE BOUNDARY FACE. THIS TANGENTIAL COMPONENT  *
!      *         IS THEN USED TO DETERMINE THE NEW POINT ON THE FACE,   *
!      *         WHICH MINIMIZES THE DISTANCE. A LINEARIZATION IS USED  *
!      *         TO FIND THIS PROJECTION AND HERE IT IS ASSUMED THAT    *
!      *         THE SURFACE QUADRILATERAL FACE VARIES BILINEARLY. THE  *
!      *         SURFACE FACE IS PARAMETRIZED USING U AND V, WHERE      *
!      *         0 <= (UU,VV) <= 1. THE STARTING POINT OF THIS          *
!      *         ITERATIVE PROCEDURE IS THE CENTROID GIVEN BY           *
!      *         (UU,VV) = (1/2,1/2).                                   *
!      *                                                                *
!      *         Note that this version by Edwin van der Weide forces   *
!      *         (UU,VV) to stay in the unit square, while the similar  *
!      *         PROJECT4 (NASA ARC) allows convergence to a point      *
!      *         outside the quad. cell as part of determining whether  *
!      *         the cell contains the point or not.  Maybe Edwin's     *
!      *         approach is preferable, but is it viable only if all   *
!      *         relevant elements are searched for the closest one?    *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS QUADRILATERAL IN NN.

         NN = BBOX_TARGETS(II)%ID

         ! DETERMINE THE 4 VECTORS WHICH COMPLETELY DESCRIBE THE FACE.
         ! Vertex 1 is the "origin" for (u,v) at the "lower left" vertex of the
         ! quad. cell, whose vertices 2, 3, 4 follow in counterclockwise order.

         IB = CONN(1,NN) ! Grid block number
         I  = CONN(2,NN) ! Lower left indices
         J  = CONN(3,NN)

         X1(1) = GRID(IB)%X(I,J,1)
         X2(1) = GRID(IB)%X(I+1,J,1)
         X3(1) = GRID(IB)%X(I+1,J+1,1)
         X4(1) = GRID(IB)%X(I,J+1,1)

         X1(2) = GRID(IB)%Y(I,J,1)
         X2(2) = GRID(IB)%Y(I+1,J,1)
         X3(2) = GRID(IB)%Y(I+1,J+1,1)
         X4(2) = GRID(IB)%Y(I,J+1,1)

         X1(3) = GRID(IB)%Z(I,J,1)
         X2(3) = GRID(IB)%Z(I+1,J,1)
         X3(3) = GRID(IB)%Z(I+1,J+1,1)
         X4(3) = GRID(IB)%Z(I,J+1,1)

         UU   = HALF
         VV   = HALF
         UUVV = FOURTH

         DO L = 1, 3
           X21(L)   = X2(L)  - X1(L)
           X41(L)   = X4(L)  - X1(L)
           X32(L)   = X3(L)  - X2(L)
           X3142(L) = X32(L) - X41(L)  ! Equivalent to original formulation
           XF(L)    = X1(L)  + UU*X21(L) + VV*X41(L) + UUVV*X3142(L)
         END DO

         ! NEWTON LOOP TO DETERMINE THE POINT ON THE SURFACE, WHICH
         ! MINIMIZES THE DISTANCE TO X,Y,Z.

         NEWTON: DO ITER=1,NITER_MAX

           ! STORE THE CURRENT VALUES OF UU AND VV FOR A STOP CRITERION
           ! LATER ON.

           UUOLD = UU
           VVOLD = VV

           ! DETERMINE THE VECTOR VF FROM XF TO X,Y,Z.

           VF(1) = X - XF(1)
           VF(2) = Y - XF(2)
           VF(3) = Z - XF(3)

           ! DETERMINE THE TANGENT VECTORS IN UU- AND VV-DIRECTION.
           ! STORE THESE IN A AND B RESPECTIVELY.

           A(1) = X21(1) + VV*X3142(1)
           A(2) = X21(2) + VV*X3142(2)
           A(3) = X21(3) + VV*X3142(3)

           B(1) = X41(1) + UU*X3142(1)
           B(2) = X41(2) + UU*X3142(2)
           B(3) = X41(3) + UU*X3142(3)

           ! DETERMINE THE NORMAL VECTOR OF THE FACE BY TAKING THE
           ! CROSS PRODUCT OF A AND B. AFTERWARDS N WILL BE SCALED TO
           ! A UNIT VECTOR.

           N(1) = A(2)*B(3) - A(3)*B(2)
           N(2) = A(3)*B(1) - A(1)*B(3)
           N(3) = A(1)*B(2) - A(2)*B(1)

           INV_LEN = ONE/MAX(EPS,SQRT(N(1)*N(1) + N(2)*N(2) + N(3)*N(3)))

           N(1) = N(1)*INV_LEN
           N(2) = N(2)*INV_LEN
           N(3) = N(3)*INV_LEN

           ! DETERMINE THE PROJECTION OF THE VECTOR VF ONTO THE FACE.

           VN = VF(1)*N(1) + VF(2)*N(2) + VF(3)*N(3)
           VT(1) = VF(1) - VN*N(1)
           VT(2) = VF(2) - VN*N(2)
           VT(3) = VF(3) - VN*N(3)

           ! THE VECTOR VT POINTS FROM THE CURRENT POINT ON THE FACE
           ! TO THE NEW POINT. HOWEVER THIS NEW POINT LIES ON THE PLANE
           ! DETERMINED BY THE VECTORS A AND B, BUT NOT NECESSARILY ON
           ! THE FACE ITSELF. THE NEW POINT ON THE FACE IS OBTAINED BY
           ! PROJECTING THE POINT IN THE A-B PLANE ONTO THE FACE. THIS
           ! CAN BE DONE BY DETERMINING THE COEFFICIENTS DU AND DV,
           ! SUCH THAT VT = DU*A + DV*B. TO SOLVE DU AND DV THE VECTORS
           ! NORMAL TO A AND B INSIDE THE PLANE AB ARE NEEDED.

           AN(1) = A(2)*N(3) - A(3)*N(2)
           AN(2) = A(3)*N(1) - A(1)*N(3)
           AN(3) = A(1)*N(2) - A(2)*N(1)

           BN(1) = B(2)*N(3) - B(3)*N(2)
           BN(2) = B(3)*N(1) - B(1)*N(3)
           BN(3) = B(1)*N(2) - B(2)*N(1)

           ! SOLVE DU AND DV. THE CLIPPING OF VN SHOULD NOT BE ACTIVE,
           ! AS THIS WOULD MEAN THAT THE VECTORS A AND B ARE PARALLEL.
           ! THIS CORRESPONDS TO A QUAD DEGENERATED TO A LINE, WHICH
           ! SHOULD NOT OCCUR IN THE SURFACE MESH.

           VN = A(1)*BN(1) + A(2)*BN(2) + A(3)*BN(3)
           VN = SIGN(MAX(EPS,ABS(VN)),VN)
           DU = (VT(1)*BN(1) + VT(2)*BN(2) + VT(3)*BN(3))/VN

           VN = B(1)*AN(1) + B(2)*AN(2) + B(3)*AN(3)
           VN = SIGN(MAX(EPS,ABS(VN)),VN)
           DV = (VT(1)*AN(1) + VT(2)*AN(2) + VT(3)*AN(3))/VN

           ! DETERMINE THE NEW PARAMETER VALUES UU AND VV. THESE ARE
           ! LIMITED TO 0 <= (UU,VV) <= 1.

           UU = UU + DU; UU = MIN(ONE,MAX(ZERO,UU))
           VV = VV + DV; VV = MIN(ONE,MAX(ZERO,VV))

           ! DETERMINE THE FINAL VALUES OF THE CORRECTIONS.

           DU = ABS(UU-UUOLD)
           DV = ABS(VV-VVOLD)

           ! DETERMINE THE NEW COORDINATES OF THE POINT XF.

           UUVV  = UU*VV
           XF(1) = X1(1) + UU*X21(1) + VV*X41(1) + UUVV*X3142(1)
           XF(2) = X1(2) + UU*X21(2) + VV*X41(2) + UUVV*X3142(2)
           XF(3) = X1(3) + UU*X21(3) + VV*X41(3) + UUVV*X3142(3)

           ! ADDITIONAL CRITERION TO EXIT THE NEWTON LOOP.

           IF(MAX(DU,DV) <= EPS_STOP) EXIT

         ENDDO NEWTON


         ! COMPUTE THE DISTANCE SQUARED BETWEEN THE POINTS XF AND X,Y,Z.

         DX  = XF(1) - X
         DY  = XF(2) - Y
         DZ  = XF(3) - Z
         DD1 = DX*DX + DY*DY + DZ*DZ

         IF(DD1 < DIST2) THEN
           DIST2 = DD1
           IQUAD = NN
           U     = UU
           V     = VV
           XB(:) = XF(:)
         ENDIF

       ENDDO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_STRUCTURED_SURFACE_ADT

!      ******************************************************************

       SUBROUTINE SEARCH_STRUCTURED_VOLUME_ADT (TARGET_COOR, IHEX, P, Q, R,    &
                                                DIST2, INIT_DISTANCE, NBLOCK,  &
                                                GRID, NHEX, CONN, XB)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE HEXAHEDRAL CELL WHICH CONTAINS      *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.                       *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003                                      *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      *                                                                *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter    *
!      *                            (packed list of quad cells version).*
!      * 05-26-04:  ELORET/NASA ARC Eliminated handling of triangular   *
!      *                            surface elements to avoid carrying  *
!      *                            around the ELTYP(*) array.          *
!      * 06-07-04   David Saunders  Work directly with a multiblock srf.*
!      *                            grid - no need to repack the nodes. *
!      * 06-14-04:    "      "      Structured volume grid version.     *
!      * 07-09-04:    "      "      Switched the order of the indices   *
!      *                            for XBBOX in the hope of slightly   *
!      *                            better cache usage.                 *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      * 10-15-19     "       "     Handle the possibility of failure   *
!      *                            due to matrix singularity via a     *
!      *                            safeguarded solution that works     *
!      *                            with the augmented system           *
!      *                               |       |   | |                  *
!      *                               |   A   | ~ |b|                  *
!      *                               |       |   | |                  *
!      *                               | eps I |   |0|                  *
!      *                               |       |   | |                  *
!      *                            as has been observed within the     *
!      *                            boundary layer regions of 3D CFD    *
!      *                            volume grids.                       *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA
       USE GRID_BLOCK_STRUCTURE

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT(IN)    :: TARGET_COOR(3)      ! Target (x,y,z)

       INTEGER, INTENT(OUT)   :: IHEX                ! CONN(:,IHEX) points to
                                                     ! the best cell found
       REAL,    INTENT(OUT)   :: P, Q, R             ! Corresponding interpo-
                                                     ! lation coefs. in [0,1]
       REAL,    INTENT(INOUT) :: DIST2               ! Corresponding squared
                                                     ! distance found, normally
                                                     ! (but see INIT_DISTANCE)
       LOGICAL, INTENT(IN)    :: INIT_DISTANCE       ! Enter .T. normally;
                                                     ! allows for a quick
                                                     ! return in some circum-
                                                     ! stances (with DIST2)
       INTEGER, INTENT(IN)    :: NBLOCK              ! Number of grid blocks

       TYPE (GRID_TYPE), INTENT (IN) :: GRID(NBLOCK) ! Multiblock volume grid

       INTEGER, INTENT(IN)    :: NHEX                ! Number of volume cells

       INTEGER, INTENT(IN)    :: CONN(4,NHEX)        ! Block # and (i,j,k) for
                                                     ! each volume cell
       REAL,    INTENT(OUT)   :: XB(3)               ! (x,y,z) of the projection
                                                     ! to the nearest cell
!      LOCAL CONSTANTS:
!      ----------------

!      PARAMETERS DESCRIBING THE MAXIMUM NUMBER OF ITERATIONS ALLOWED
!      AND THE THRESHOLD FOR STOPPING THE NEWTON ALGORITHM TO COMPUTE
!      THE PROJECTION TO THE BEST HEXAHEDRAL CELL.

       INTEGER, PARAMETER :: NITER_MAX = 15
       REAL,    PARAMETER :: EPS_STOP  = 1.E-8
       REAL,    PARAMETER :: LAMBDA    = EPS_STOP  ! ~sqrt (machine eps)

!      Other constants previously obtained from a module:

       REAL,    PARAMETER :: HALF   = 0.5,     &
                             LARGE  = 1.E+37,  &
                             ONE    = 1.0,     &
                             ZERO   = 0.0
!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IERR
       INTEGER :: I, IB, II, J, K, L, MM, NN, ITER
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       LOGICAL :: SHOW_CELL

       REAL :: X, Y, Z, DX, DY, DZ
       REAL :: DD1, DD2, DSQ, RESIDSQ
       REAL :: AJAC(3,3), DP(3)
       REAL :: PL, QL, RL, POLD, QOLD, ROLD, XP, YP, ZP, XQ, YQ, ZQ
       REAL :: XR, YR, ZR, XPQ, YPQ, ZPQ, XQR, YQR, ZQR, XRP, YRP, ZRP
       REAL :: XPQR, YPQR, ZPQR, XT, YT, ZT

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF (INIT_DISTANCE) DIST2 = LARGE
       NPOS_BBOXES = 0

       X = TARGET_COOR(1)
       Y = TARGET_COOR(2)
       Z = TARGET_COOR(3)

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN(DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE GUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_STRUCTURED_VOLUME_ADT", &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_STRUCTURED_VOLUME_ADT", &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE HEXAHEDRAL ELEMENT  *
!      *         BY APPLYING A NEWTON ITERATION (3 EQNS., 3 VARIABLES). *
!      *         THE CELL VOLUME IS PARAMETRIZED USING P, Q, R WHERE    *
!      *         0 <= (P,Q,R) <= 1. THE STARTING POINT OF THIS          *
!      *         ITERATIVE PROCEDURE IS THE CENTROID GIVEN BY           *
!      *         (P,Q,R) = (1/2,1/2,1/2).                               *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS HEX CELL IN NN.

         NN = BBOX_TARGETS(II)%ID

         IB = CONN(1,NN) ! Grid block number
         I  = CONN(2,NN) ! Lower left indices
         J  = CONN(3,NN)
         K  = CONN(4,NN)

         ! The following iteration is adapted from that of TRILINT.  Here,
         ! p, q, r are forced to remain inside the unit cube, whereas TRILINT
         ! allows convergence to a point outside the current cell as part of
         ! the RIPPLE3D strategy for determining inside/outside status.

         XT = GRID(IB)%X(I,J,K) - X
         YT = GRID(IB)%Y(I,J,K) - Y
         ZT = GRID(IB)%Z(I,J,K) - Z

         XP = GRID(IB)%X(I+1,J,K) - GRID(IB)%X(I,J,K)
         YP = GRID(IB)%Y(I+1,J,K) - GRID(IB)%Y(I,J,K)
         ZP = GRID(IB)%Z(I+1,J,K) - GRID(IB)%Z(I,J,K)

         XQ = GRID(IB)%X(I,J+1,K) - GRID(IB)%X(I,J,K)
         YQ = GRID(IB)%Y(I,J+1,K) - GRID(IB)%Y(I,J,K)
         ZQ = GRID(IB)%Z(I,J+1,K) - GRID(IB)%Z(I,J,K)

         XR = GRID(IB)%X(I,J,K+1) - GRID(IB)%X(I,J,K)
         YR = GRID(IB)%Y(I,J,K+1) - GRID(IB)%Y(I,J,K)
         ZR = GRID(IB)%Z(I,J,K+1) - GRID(IB)%Z(I,J,K)

         XPQ = GRID(IB)%X(I+1,J+1,K) - GRID(IB)%X(I,J+1,K) - XP
         YPQ = GRID(IB)%Y(I+1,J+1,K) - GRID(IB)%Y(I,J+1,K) - YP
         ZPQ = GRID(IB)%Z(I+1,J+1,K) - GRID(IB)%Z(I,J+1,K) - ZP

         XRP = GRID(IB)%X(I+1,J,K+1) - GRID(IB)%X(I,J,K+1) - XP
         YRP = GRID(IB)%Y(I+1,J,K+1) - GRID(IB)%Y(I,J,K+1) - YP
         ZRP = GRID(IB)%Z(I+1,J,K+1) - GRID(IB)%Z(I,J,K+1) - ZP

         XQR = GRID(IB)%X(I,J+1,K+1) - GRID(IB)%X(I,J,K+1) - XQ
         YQR = GRID(IB)%Y(I,J+1,K+1) - GRID(IB)%Y(I,J,K+1) - YQ
         ZQR = GRID(IB)%Z(I,J+1,K+1) - GRID(IB)%Z(I,J,K+1) - ZQ

         XPQR = GRID(IB)%X(I+1,J+1,K+1) - GRID(IB)%X(I,J+1,K+1) -   &
                GRID(IB)%X(I+1,J,  K+1) + GRID(IB)%X(I,J,  K+1) - XPQ
         YPQR = GRID(IB)%Y(I+1,J+1,K+1) - GRID(IB)%Y(I,J+1,K+1) -   &
                GRID(IB)%Y(I+1,J,  K+1) + GRID(IB)%Y(I,J,  K+1) - YPQ
         ZPQR = GRID(IB)%Z(I+1,J+1,K+1) - GRID(IB)%Z(I,J+1,K+1) -   &
                GRID(IB)%Z(I+1,J,  K+1) + GRID(IB)%Z(I,J,  K+1) - ZPQ

         PL = HALF;  QL = HALF;  RL = HALF
         SHOW_CELL = .TRUE.

         NEWTON:  DO ITER = 1, NITER_MAX

           POLD = PL;  QOLD = QL;  ROLD = RL

           ! Jacobian (i, j) = partial df(i)/dp(j)

           AJAC(1,1) = QL * (RL * XPQR + XPQ) + RL * XRP + XP
           AJAC(2,1) = QL * (RL * YPQR + YPQ) + RL * YRP + YP
           AJAC(3,1) = QL * (RL * ZPQR + ZPQ) + RL * ZRP + ZP

           AJAC(1,2) = RL * (PL * XPQR + XQR) + PL * XPQ + XQ
           AJAC(2,2) = RL * (PL * YPQR + YQR) + PL * YPQ + YQ
           AJAC(3,2) = RL * (PL * ZPQR + ZQR) + PL * ZPQ + ZQ

           AJAC(1,3) = PL * (QL * XPQR + XRP) + QL * XQR + XR
           AJAC(2,3) = PL * (QL * YPQR + YRP) + QL * YQR + YR
           AJAC(3,3) = PL * (QL * ZPQR + ZRP) + QL * ZQR + ZR

           ! RHS elements are f (1), f (2), f (3):

           DP(1) = PL * AJAC(1,1) + QL * (RL * XQR + XQ) + RL * XR + XT
           DP(2) = PL * AJAC(2,1) + QL * (RL * YQR + YQ) + RL * YR + YT
           DP(3) = PL * AJAC(3,1) + QL * (RL * ZQR + ZQ) + RL * ZR + ZT

           ! The RHS elements can go to zero only if the target is inside the
           ! cell because p,q,r are forced to stay inside the unit cube.

!!!        DSQ = DP(1)**2 + DP(2)**2 + DP(3)**2

!!!        WRITE (*, &
!!!    '(A, I4, A, I2, A, 1P, E9.2, A, 3E9.2, A, 0P, 3F12.9, A, I6, I3, 3I4)') &
!!!    ' II', II, ' It', ITER, ' DSQ', DSQ, ' Xt', X, Y, Z,                    &
!!!    ' pqr', PL, QL, RL, ' nbijk', NN, IB, I, J, K

           CALL LUSOLVE (3, 3, AJAC, DP, IERR)       ! Solve J dp = f

!          Occasional singularity here is believed to be confined to boundary
!          layer regions during flow-field interpolations, where the grid cells
!          can have extremely high aspect ratios.  Correction: the most common
!          cause is the collapsed cells along Ox in a rotated full-body axi-
!          symmetric volume grid as needed for hemispherical radiation calcu-
!          ations at points on the aft body.  A consequence for FLOW_INTERP
!          users has been to favor the hybrid method, namely a KDTREE search for
!          the nearest cell centroid followed by refinement within that cell
!          as implemented here and separately in subroutine NEAREST_BRICK_POINT.
!          However, the nearest centroid can be a poor measure of the correct
!          cell within which to interpolate.  Consider the outer k planes of a
!          shock-aligned flow solution, which can be very close in the k dir-
!          ection while being quite large in the surface directions.  Interp-
!          olation along a line of sight for setting up a radiation calculation
!          can all too easily pick a cell in a k-plane outside the shock even
!          though the target LOS point is inside the shock, giving grossly wrong
!          free-stream temperatures instead of the correct high temperatures.
!          Now, with boundary layer situations in mind, we choose not to simply
!          stop upon encountering singularity but rather return a least squares
!          result by solving an augmented system guaranteed to be full rank and
!          promoting a small-norm solution.  This system adds lambda I below A
!          on the LHS, and the zero vector below b on the RHS, where lambda > 0
!          is small and ~sqrt (machine eps) should suffice.  If a better cell is
!          present, this ADT search will still find it.  We can't simply quit
!          with no way for the calling program to complete the interpolation and
!          keep searching at further target points as has been the case earlier.

           IF (IERR /= 0) THEN
!!!          CALL TERMINATE ("SEARCH_STRUCTURED_VOLUME_ADT", "Singular matrix.")

             CALL SAFEGUARDED_LSQR (3, 3, AJAC, DP, LAMBDA, DP, RESIDSQ, IERR)
             IF (IERR /= 0) THEN   ! This should never happen, but ...
               CALL TERMINATE ("SEARCH_STRUCTURED_VOLUME_ADT", &
                               "Allocation error in SAFE_GUARDED_LSQR?")
             END IF
             WRITE (*, '(A, I3, A, ES14.6)') &
               '*** Singular matrix trapped at iteration', ITER, &
               '; squared residual of augmented system:', RESIDSQ
             IF (SHOW_CELL) THEN
               SHOW_CELL = .FALSE.
               WRITE (*, '(A)') 'Cell vertices:'
               WRITE (*, '(3ES16.8)') &
       GRID(IB)%X(I,J,K),      GRID(IB)%Y(I,J,K),      GRID(IB)%Z(I,J,K),     &
       GRID(IB)%X(I+1,J,K),    GRID(IB)%Y(I+1,J,K),    GRID(IB)%Z(I+1,J,K),   &
       GRID(IB)%X(I,J+1,K),    GRID(IB)%Y(I,J+1,K),    GRID(IB)%Z(I,J+1,K),   &
       GRID(IB)%X(I+1,J+1,K),  GRID(IB)%Y(I+1,J+1,K),  GRID(IB)%Z(I+1,J+1,K), &
       GRID(IB)%X(I,J,K+1),    GRID(IB)%Y(I,J,K+1),    GRID(IB)%Z(I,J,K+1),   &
       GRID(IB)%X(I+1,J,K+1),  GRID(IB)%Y(I+1,J,K+1),  GRID(IB)%Z(I+1,J,K+1), &
       GRID(IB)%X(I,J+1,K+1),  GRID(IB)%Y(I,J+1,K+1),  GRID(IB)%Z(I,J+1,K+1), &
       GRID(IB)%X(I+1,J+1,K+1),GRID(IB)%Y(I+1,J+1,K+1),GRID(IB)%Z(I+1,J+1,K+1)
             END IF
           END IF

           PL = MIN (ONE, MAX (ZERO, PL - DP(1)));  DP(1) = ABS (PL - POLD)
           QL = MIN (ONE, MAX (ZERO, QL - DP(2)));  DP(2) = ABS (QL - QOLD)
           RL = MIN (ONE, MAX (ZERO, RL - DP(3)));  DP(3) = ABS (RL - ROLD)

           IF (MAX (DP(1), DP(2), DP(3)) < EPS_STOP) EXIT

         END DO NEWTON

         ! The deltas from the target (DP(:) before the solve) are one iteration
         ! behind, so update the squared distance:

         AJAC(1,1) = QL * (RL * XPQR + XPQ) + RL * XRP + XP
         AJAC(2,1) = QL * (RL * YPQR + YPQ) + RL * YRP + YP
         AJAC(3,1) = QL * (RL * ZPQR + ZPQ) + RL * ZRP + ZP

         DX  = PL * AJAC(1,1) + QL * (RL * XQR + XQ) + RL * XR + XT
         DY  = PL * AJAC(2,1) + QL * (RL * YQR + YQ) + RL * YR + YT
         DZ  = PL * AJAC(3,1) + QL * (RL * ZQR + ZQ) + RL * ZR + ZT

         DD1 = DX*DX + DY*DY + DZ*DZ

         IF (DD1 < DIST2) THEN
           DIST2 = DD1
           IHEX  = NN
           P     = PL
           Q     = QL
           R     = RL
           XB(1) = X + DX
           XB(2) = Y + DY
           XB(3) = Z + DZ
         END IF

       END DO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_STRUCTURED_VOLUME_ADT

!      ******************************************************************

       SUBROUTINE SEARCH_UNSTRUCTURED_SURFACE_ADT (TARGET_COOR, ITRI, U, V, W, &
                                                   DIST2, INIT_DISTANCE, NNODE,&
                                                   NTRI, CONN, COOR, XB)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE TRIANGULAR CELL WHICH CONTAINS      *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.                       *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003  Packed quads. version.              *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 05-26-04:  ELORET/NASA ARC Eliminated handling of triangular   *
!      *                            surface elements to avoid carrying  *
!      *                            around the ELTYP(*) array.          *
!      * 06-25-04     "       "     Version for a list of triangles.    *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTRI) too. *
!      * 08-18-04     "       "     The projection back to u + v = 1,   *
!      *                            inherited from UV_MAP, had the two  *
!      *                            signs reversed!                     *
!      * 08-27-04                   Introduced NEAREST_TRI_POINT after  *
!      *                            realizing that handling of PROJECT3 *
!      *                            results outside a triangle has been *
!      *                            flawed in several applications,     *
!      *                            including here.                     *
!      *                            Coefficient W has been added as an  *
!      *                            argument for symmetry reasons.      *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT (IN)   :: TARGET_COOR(3)     ! Target (x,y,z)

       INTEGER, INTENT (OUT)   :: ITRI              ! CONN(:,ITRI) points to
                                                    ! the best triangle found
       REAL,    INTENT (OUT)   :: U, V, W           ! Corresponding interpola-
                                                    ! tion coeffs. in [0, 1]
                                                    ! with U + V + W = 1; see
                                                    ! usage notes below
       REAL,    INTENT (INOUT) :: DIST2             ! Corresponding squared
                                                    ! distance found, normally
                                                    ! (but see INIT_DISTANCE)
       LOGICAL, INTENT (IN)    :: INIT_DISTANCE     ! Enter .T. normally;
                                                    ! allows for a quick return
                                                    ! in some circumstances
                                                    ! (with DIST2)
       INTEGER, INTENT (IN)    :: NNODE             ! # packed coordinates in
                                                    ! COOR(1:3,*)
       INTEGER, INTENT (IN)    :: NTRI              ! # triangles defined in
                                                    ! CONN(1:3,*)
       INTEGER, INTENT (IN)    :: CONN(3,NTRI)      ! Pointers to vertices 1:3
                                                    ! for all the triangles
       REAL,    INTENT (IN)    :: COOR(3,NNODE)     ! (x,y,z)s pointed to by
                                                    ! CONN(1:3,*)
       REAL,    INTENT (OUT)   :: XB(3)             ! (x,y,z) of the [adjusted]
                                                    ! projection to the nearest
                                                    ! triangle

!      (u,v,w) usage for interpolation of other quantities is indicated by:
!                       XB = U * X1 + V * X2 + W * X3
!
!      CONSTANTS previously obtained from a module:

       REAL, PARAMETER :: LARGE = 1.E+37,  &
                          ZERO  = 0.0
!      LOCAL VARIABLES.

       INTEGER :: IERR
       INTEGER :: I, II, MM, NN
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       REAL :: X, Y, Z, DX, DY, DZ
       REAL :: DD1, DD2, P, Q, R

       REAL, DIMENSION (3) :: X1, X2, X3, XF

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF( INIT_DISTANCE ) DIST2 = LARGE
       NPOS_BBOXES = 0

       X = TARGET_COOR(1)
       Y = TARGET_COOR(2)
       Z = TARGET_COOR(3)

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN(DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE QUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_UNSTRUCTURED_SURFACE_ADT", &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_UNSTRUCTURED_SURFACE_ADT", &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE TRIANGLE ELEMENT.   *
!      *                                                                *
!      *         Projecting the point to the plane of the triangle is   *
!      *         treated as a linear least squares problem.  The foot   *
!      *         of the projection is adjusted if necessary not to lie  *
!      *         outside the triangle. As long as all relevant elements *
!      *         are checked, this guarantees finding the closest       *
!      *         triangle even when the point lies outside all of them. *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS THE TRIANGLE IN NN.

         NN = BBOX_TARGETS(II)%ID

         ! Extract the coordinates of the three vertices.

         X1(:) = COOR(:,CONN(1,NN))
         X2(:) = COOR(:,CONN(2,NN))
         X3(:) = COOR(:,CONN(3,NN))

         ! Calculate non-negative coefficients p, q, r with sum 1 that produce
         ! p X1 + q X2 + r X3 = XF not outside this triangle:

         CALL NEAREST_TRI_POINT (X1, X2, X3, TARGET_COOR, XF, P, Q, R, DD1)

         IF (DD1 < DIST2) THEN
           DIST2 = DD1
           ITRI  = NN
           U     = P
           V     = Q
           W     = R
           XB(:) = XF(:)
           IF (DD1 == ZERO) EXIT ! Enclosing cell case - done
         END IF

       ENDDO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_UNSTRUCTURED_SURFACE_ADT

!      ******************************************************************

       SUBROUTINE SEARCH_UNSTRUCTURED_VOLUME_ADT (TARGET_COOR, ITET, PQRS,     &
                         DIST2, INIT_DISTANCE, NNODE, NTET, CONN, COOR, XB)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE TETRAHEDRAL CELL WHICH CONTAINS     *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.                       *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003  Packed quads. version.              *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 05-26-04:  ELORET/NASA ARC Eliminated handling of triangular   *
!      *                            surface elements to avoid carrying  *
!      *                            around the ELTYP(*) array.          *
!      * 06-25-04     "       "     Version for a list of triangle.     *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTET) too. *
!      * 08-18-04     "       "     Version for a tetrahedral mesh.     *
!      * 08-27-04     "       "     Introduced NEAREST_TET_POINT.       *
!      *                            Earlier usages of PROJECT3 for      *
!      *                            triangulations have been flawed,    *
!      *                            and hence so was the original       *
!      *                            analog for tet. meshes.             *
!      * 04-20-07     "       "     Renamed all build & search routines *
!      *                            to allow more than one grid type in *
!      *                            a single application.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT (IN)   :: TARGET_COOR(3)     ! Target (x,y,z)

       INTEGER, INTENT (OUT)   :: ITET              ! CONN(:,ITET) points to
                                                    ! the best mesh cell found
       REAL,    INTENT (OUT)   :: PQRS(4)           ! Corresponding interpola-
                                                    ! tion coeffs. in [0, 1]
                                                    ! with sum of 1
       REAL,    INTENT (INOUT) :: DIST2             ! Corresponding squared
                                                    ! distance found, normally
                                                    ! (but see INIT_DISTANCE)
       LOGICAL, INTENT (IN)    :: INIT_DISTANCE     ! Enter .T. normally;
                                                    ! allows for a quick return
                                                    ! in some circumstances
                                                    ! (with DIST2)
       INTEGER, INTENT (IN)    :: NNODE             ! # packed coordinates in
                                                    ! COOR(1:3,*)
       INTEGER, INTENT (IN)    :: NTET              ! # cells defined in
                                                    ! CONN(1:4,*)
       INTEGER, INTENT (IN)    :: CONN(4,NTET)      ! Pointers to vertices 1:4
                                                    ! for all the mesh cells
       REAL,    INTENT (IN)    :: COOR(3,NNODE)     ! (x,y,z)s pointed to by
                                                    ! CONN(1:4,*)
       REAL,    INTENT (OUT)   :: XB(3)             ! (x,y,z) of the [adjusted]
                                                    ! interpolation within the
                                                    ! nearest mesh cell, or on
                                                    ! its boundary:
!                                              XB = p X1 + q X2 + r X3 + s X4

!      CONSTANTS previously obtained from a module:

       REAL,    PARAMETER :: LARGE = 1.E+37,  &
                             ZERO  = 0.0
!      LOCAL VARIABLES.

       INTEGER :: IERR
       INTEGER :: I, II, MM, NN
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       REAL :: X, Y, Z, DX, DY, DZ
       REAL :: DD1, DD2, P, Q, R, S

       REAL, DIMENSION (3) :: X1, X2, X3, X4, XF

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF( INIT_DISTANCE ) DIST2 = LARGE
       NPOS_BBOXES = 0

       X = TARGET_COOR(1)
       Y = TARGET_COOR(2)
       Z = TARGET_COOR(3)

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN (DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE QUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN (DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_UNSTRUCTURED_VOLUME_ADT", &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_UNSTRUCTURED_VOLUME_ADT", &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE MESH CELL.          *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS THE MESH CELL IN NN.

         NN = BBOX_TARGETS(II)%ID

         ! Extract the coordinates of the vertices.

         X1(:) = COOR(:,CONN(1,NN))
         X2(:) = COOR(:,CONN(2,NN))
         X3(:) = COOR(:,CONN(3,NN))
         X4(:) = COOR(:,CONN(4,NN))

         ! Calculate nonnegative coefficients p, q, r, s with sum 1 that produce
         ! p X1 + q X2 + r X3 + s X4 = XF not outside this cell:

         CALL NEAREST_TET_POINT (X1, X2, X3, X4, TARGET_COOR, XF, P, Q, R, S, &
                                 DD1)

         IF (DD1 < DIST2) THEN
           DIST2   = DD1
           ITET    = NN
           PQRS(1) = P;  PQRS(2) = Q;  PQRS(3) = R;  PQRS(4) = S
           XB(:)   = XF(:)
           IF (DD1 == ZERO) EXIT ! Enclosing cell case - done
         END IF

       ENDDO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_UNSTRUCTURED_VOLUME_ADT

!      ******************************************************************

       SUBROUTINE SEARCH_MIXED_CELL_ADT (TARGET_COOR, ICELL, COEFS, DIST2,     &
                                         INIT_DISTANCE, NNODE, NCELL, CONN,    &
                                         COOR, XB, IERR)

!      ******************************************************************
!      *                                                                *
!      * SEARCH THE ADT TO FIND THE MIXED-TYPE CELL WHICH CONTAINS      *
!      * THE TARGET COORDINATE OR AT LEAST THE POINT ON THE CELL THAT   *
!      * MINIMIZES THE DISTANCE TO THIS COORDINATE.  CORRESPONDING      *
!      * INTERPOLATION COEFFICIENTS ARE RETURNED.                       *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-07-2003  Packed quads. version.              *
!      * LAST MODIFIED: 12-16-2003  (by Edwin)                          *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 05-26-04:  ELORET/NASA ARC Eliminated handling of triangular   *
!      *                            surface elements to avoid carrying  *
!      *                            around the ELTYP(*) array.          *
!      * 06-25-04     "       "     Version for a list of triangles.    *
!      *                            Storing triangle (x,y,z)s and node  *
!      *                            pointers as triples should be more  *
!      *                            efficient than the other order if   *
!      *                            we reorder XBBOX as (1:6,NTRI) too. *
!      * 08-18-04     "       "     Version for a tetrahedral mesh.     *
!      * 08-27-04     "       "     Introduced NEAREST_TET_POINT.       *
!      *                            Earlier usages of PROJECT3 for      *
!      *                            triangulations have been flawed,    *
!      *                            and hence so was the original       *
!      *                            analog for tet. meshes.             *
!      * 06-06-13   David Saunders  Version for a list of mixed cells,  *
!      *            ERC Inc./ARC    prompted by the US3D flow solver.   *
!      *                            The cell type conventions are US3D- *
!      *                            specific in isolated parts of       *
!      *                            BUILD_ADT and SEARCH_ADT that could *
!      *                            easily be changed to suit different *
!      *                            nomenclature.  IERR is now an       *
!      *                            argument to allow the application   *
!      *                            to clean up properly.               *
!      * 08-02-13     "       "     Made use of generic procedures and  *
!      *                            combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      ARGUMENTS:
!      ----------

       REAL,    INTENT (IN)   :: TARGET_COOR(3) ! Target (x,y,z)

       INTEGER, INTENT (OUT)   :: ICELL         ! CONN(*,ICELL) points to
                                                ! the best mesh cell found
       REAL,    INTENT (OUT)   :: COEFS(8)      ! Corresponding interpolation
                                                ! coefs. in [0, 1] with sum of
                                                ! 1; COEFS(1:NVERT) are relevant
                                                ! for each cell type
       REAL,    INTENT (INOUT) :: DIST2         ! Corresponding squared
                                                ! distance found, normally
                                                ! (but see INIT_DISTANCE)
       LOGICAL, INTENT (IN)    :: INIT_DISTANCE ! Enter .T. normally;
                                                ! allows for a quick return
                                                ! in some circumstances
                                                ! (with DIST2)
       INTEGER, INTENT (IN)    :: NNODE         ! # packed coordinates in
                                                ! COOR(1:3,1:NNODE)
       INTEGER, INTENT (IN)    :: NCELL         ! # cells defined in
                                                ! CONN(*,1:NCELL)
       INTEGER, INTENT (IN)  :: CONN(0:8,NCELL) ! Connectivity info, presently
                                                ! limited to cells with up to 8
                                                ! vertices or nodes;
                                                ! CONN(0,N) = cell type for cell
                                                ! N as hard-coded below;
                                                ! CONN(1:NVERT,N) = vertex #s,
                                                ! where # vertices is derived
                                                ! from cell type as shown below;
                                                ! 8 here must match the largest
                                                ! entry in NVERT_PER_CELL below
       REAL,    INTENT (IN)    :: COOR(3,NNODE) ! (x,y,z)s pointed to by
                                                ! CONN(1:# vertices,1:NCELL)
       REAL,    INTENT (OUT)   :: XB(3)         ! (x,y,z) of the [adjusted]
                                                ! interpolation within the
                                                ! nearest mesh cell, or on
                                                ! its boundary:
                                                ! XB = Sum (1:NVERT) COEFS(I)*XV
       INTEGER, INTENT (OUT)   :: IERR          ! Nonzero => fatal error

!      CONSTANTS previously obtained from a module:

       REAL,    PARAMETER :: LARGE = 1.E+37,  &
                             ZERO  = 0.0
!      LOCAL VARIABLES.

       INTEGER :: I, II, MM, NN
       INTEGER :: ACTIVE_LEAF, NPOS_BBOXES
       INTEGER :: NFRONT_LEAVES, NFRONT_LEAVES_NEW

       REAL :: X, Y, Z, DX, DY, DZ
       REAL :: DD1, DD2
       REAL :: XF(3)

!      US3D-specific extensions for mixed cell types:
!      ----------------------------------------------

       INTEGER :: ITYPE, IVERT, NVERT
       INTEGER :: NVERT_PER_CELL(7)  ! # vertices for each cell type
       REAL    :: XVERT(3,8)         ! For coordinates of up to 8 vertices

       DATA NVERT_PER_CELL &  ! These follow Fluent convention
         /3,               &  ! 1 = triangle
          4,               &  ! 2 = tetrahedron
          4,               &  ! 3 = quadrilateral
          8,               &  ! 4 = hexahedron
          5,               &  ! 5 = pyramid with quadrilateral base
          6,               &  ! 6 = prism with triangular cross-section
          2/                  ! 7 = line segement (not a Fluent type)

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! INITIALIZE THE DISTANCE SQUARED TO A LARGE NUMBER IF THE
       ! DISTANCE MUST BE INITIALIZED, SET THE NUMBER OF POSSIBLE
       ! BOUNDING BOXES TO 0 AND STORE THE TARGET COORDINATES IN X,Y,Z.

       IF( INIT_DISTANCE ) DIST2 = LARGE
       NPOS_BBOXES = 0

       X = TARGET_COOR(1)
       Y = TARGET_COOR(2)
       Z = TARGET_COOR(3)

!      ******************************************************************
!      *                                                                *
!      * STEP 1: FIND THE MOST LIKELY BOUNDING BOX WHICH MINIMIZES      *
!      *         THE GUARANTEED DISTANCE FROM THE POINT TO THAT         *
!      *         BOUNDING BOX.                                          *
!      *                                                                *
!      ******************************************************************

       ! DETERMINE THE POSSIBLE DISTANCE SQUARED TO THE ROOT LEAF.
       ! IF THE POSSIBLE MINIMUM DISTANCE IS LARGER THAN THE CURRENTLY
       ! STORED GUARANTEED VALUE, THERE IS NO NEED TO INVESTIGATE THE
       ! TREE AND A RETURN CAN BE MADE.

       ACTIVE_LEAF = 1

       DD1 = GET_POS_DIST2_LEAF(ACTIVE_LEAF)
       IF(DD1 >= DIST2) RETURN

       ! TRAVERSE THE TREE UNTIL A TERMINAL LEAF IS FOUND.

       TREE_TRAVERSAL_1: DO

         ! CONDITION TO EXIT THE LOOP.

         IF(ACTIVE_LEAF < 0) EXIT

         ! DETERMINE THE GUARANTEED DISTANCE SQUARED FOR BOTH CHILDREN
         ! OF THE ACTIVE LEAF. IF A CHILD HAS A NEGATIVE ID THIS
         ! INDICATES THAT IT IS A BOUNDING BOX; OTHERWISE IT IS A LEAF
         ! OF THE ADT.

         IF(ADT(ACTIVE_LEAF)%CHILDREN(1) > 0) THEN
           DD1 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(1))
         ELSE
           DD1 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(1))
         ENDIF

         IF(ADT(ACTIVE_LEAF)%CHILDREN(2) > 0) THEN
           DD2 = GET_GUAR_DIST2_LEAF(ADT(ACTIVE_LEAF)%CHILDREN(2))
         ELSE
           DD2 = GET_GUAR_DIST2_BBOX(-ADT(ACTIVE_LEAF)%CHILDREN(2))
         ENDIF

         ! DETERMINE WHICH WILL BE THE NEXT ACTIVE LEAF IN THE TREE
         ! TRAVERSAL. THIS WILL BE THE LEAF WHICH HAS THE MINIMUM
         ! GUARANTEED DISTANCE. IN CASE OF TIES TAKE THE RIGHT LEAF,
         ! BECAUSE THIS LEAF MAY HAVE MORE CHILDREN.

         IF(DD1 < DD2) THEN
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(1)
         ELSE
           ACTIVE_LEAF = ADT(ACTIVE_LEAF)%CHILDREN(2)
         ENDIF

       ENDDO TREE_TRAVERSAL_1

       ! STORE THE GUARANTEED MINIMUM DISTANCE SQUARED IN DIST2.

       DIST2 = MIN (DIST2, DD1, DD2)

!      ******************************************************************
!      *                                                                *
!      * STEP 2: FIND THE BOUNDING BOXES WHOSE POSSIBLE MINIMUM         *
!      *         DISTANCES ARE LESS THAN THE CURRENTLY STORED           *
!      *         GUARANTEED MINIMUM DISTANCE.                           *
!      *                                                                *
!      ******************************************************************

       ! IT IS ALREADY TESTED THAT THE ROOT LEAF HAS A SMALLER POSSIBLE
       ! DISTANCE THAN THE CURRENTLY STORED VALUE. THEREFORE INITIALIZE
       ! THE NUMBER OF LEAVES ON THE FRONT TO 1 AND SET THE FRONT LEAF
       ! TO THE ROOT LEAF.

       NFRONT_LEAVES   = 1
       FRONT_LEAVES(1) = 1

       ! TRAVERSE THE TREE AND STORE ALL POSSIBLE BOUNDING BOXES.

       TREE_TRAVERSAL_2: DO

         ! INITIALIZE THE NUMBER OF LEAVES ON THE NEW FRONT TO 0.

         NFRONT_LEAVES_NEW = 0

         ! LOOP OVER THE NUMBER OF LEAVES ON THE CURRENT FRONT.

         CURRENT_FRONT_LOOP: DO II=1,NFRONT_LEAVES

           ! STORE THE LEAF A BIT EASIER AND LOOP OVER ITS CHILDREN.

           NN = FRONT_LEAVES(II)

           CHILDREN_LOOP: DO MM=1,2

             ! DETERMINE WHETHER THIS CHILD CONTAINS A BOUNDING BOX
             ! OR A LEAF OF THE NEXT LEVEL.

             TERMINAL_TEST: IF(ADT(NN)%CHILDREN(MM) < 0) THEN

               ! CHILD CONTAINS A BOUNDING BOX. DETERMINE THE POSSIBLE
               ! AND GUARANTEED MINIMUM DISTANCE SQUARED TO THE GIVEN
               ! COORDINATES.

               DD1   = GET_POS_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_BBOX(-ADT(NN)%CHILDREN(MM))
               DIST2 = MIN(DIST2, DD2)

               ! IF DD1 IS LESS THAN THE QUARANTEED MINIMUM DISTANCE
               ! STORE THIS BOUNDING BOX IN BBOX_TARGETS. CHECK IF
               ! ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NPOS_BBOXES == NALLOC_BBOX) &
                   CALL REALLOC_BBOX_TARGETS

                 NPOS_BBOXES = NPOS_BBOXES + 1
                 BBOX_TARGETS(NPOS_BBOXES)%ID = -ADT(NN)%CHILDREN(MM)
                 BBOX_TARGETS(NPOS_BBOXES)%POS_DIST2 = DD1

               ENDIF

             ELSE TERMINAL_TEST

               ! CHILD CONTAINS A LEAF. COMPUTE ITS POSSIBLE AND
               ! GUARANTEED MINIMUM DISTANCE SQUARED.

               DD1   = GET_POS_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DD2   = GET_GUAR_DIST2_LEAF(ADT(NN)%CHILDREN(MM))
               DIST2 = MIN (DIST2, DD2)

               ! CHECK IF DD1 IS LESS THAN THE CURRENTLY STORED
               ! GUARANTEED DISTANCE SQUARED. IF SO STORE IT IN THE
               ! NEW FRONT. CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED.

               IF(DD1 < DIST2) THEN

                 IF(NFRONT_LEAVES_NEW == NALLOC_FRONT_LEAVES_NEW) &
                   CALL REALLOC_FRONT_LEAVES_NEW

                 NFRONT_LEAVES_NEW = NFRONT_LEAVES_NEW + 1
                 FRONT_LEAVES_NEW(NFRONT_LEAVES_NEW) = ADT(NN)%CHILDREN(MM)

               ENDIF

             ENDIF TERMINAL_TEST

           ENDDO CHILDREN_LOOP

         ENDDO CURRENT_FRONT_LOOP

         ! CONDITION TO EXIT THE LOOP TREE_TRAVERSAL_2.

         IF(NFRONT_LEAVES_NEW == 0) EXIT

         ! CHECK IF ENOUGH MEMORY HAS BEEN ALLOCATED FOR FRONT LEAVES.
         ! IF NOT REALLOCATE. NO NEED TO STORE THE OLD VALUES.

         NFRONT_LEAVES = NFRONT_LEAVES_NEW
         IF(NFRONT_LEAVES > NALLOC_FRONT_LEAVES) THEN

           DEALLOCATE(FRONT_LEAVES, STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_MIXED_CELL_ADT", &
                             "Deallocation error for FRONT_LEAVES.")

           NALLOC_FRONT_LEAVES = NALLOC_FRONT_LEAVES_NEW
           ALLOCATE(FRONT_LEAVES(NALLOC_FRONT_LEAVES), STAT=IERR)
           IF(IERR /= 0)                   &
             CALL TERMINATE ("SEARCH_MIXED_CELL_ADT", &
                             "Allocation failure for FRONT_LEAVES.")
         ENDIF

         ! COPY THE NEW FRONT LEAVES INTO FRONT LEAVES.

         DO II=1,NFRONT_LEAVES
           FRONT_LEAVES(II) = FRONT_LEAVES_NEW(II)
         ENDDO

       ENDDO TREE_TRAVERSAL_2

       ! SORT BBOX_TARGETS IN INCREASING ORDER, SUCH THAT THE BOUNDING
       ! BOX WITH THE MINIMUM POSSIBLE DISTANCE IS SEARCHED FIRST.

       CALL QSORT_BBOX_TARGET_TYPE (BBOX_TARGETS, NPOS_BBOXES)

!      ******************************************************************
!      *                                                                *
!      * STEP 3: LOOP OVER THE POSSIBLE BOUNDING BOXES AND CALCULATE    *
!      *         THE ACTUAL DISTANCE SQUARED TO THE MESH CELL.          *
!      *                                                                *
!      ******************************************************************

       POS_BBOXES: DO II=1,NPOS_BBOXES

         ! ADDITIONAL CONDITION TO EXIT THE LOOP.

         IF(DIST2 <= BBOX_TARGETS(II)%POS_DIST2) EXIT

         ! STORE THE ID OF THE BOUNDING BOX AND THUS THE MESH CELL IN NN.

         NN    = BBOX_TARGETS(II)%ID
         ITYPE = CONN(0,NN)
         NVERT = NVERT_PER_CELL(ITYPE)

         ! Extract the coordinates of the vertices.

         DO IVERT = 1, NVERT
            XVERT(:,IVERT) = COOR(:,CONN(IVERT,NN))
         END DO

         ! Calculate non-negative coefficients COEFS(1:NVERT) with sum 1 that
         ! produce Sum (1:NVERT) COEFS(I) * XVERT(I) = XF not outside this cell:

         CALL NEAREST_CELL_POINT (ITYPE, NVERT, XVERT, TARGET_COOR, XF, &
                                  COEFS, DD1)

         IF (DD1 < DIST2) THEN
           DIST2   = DD1
           ICELL   = NN
           XB(:)   = XF(:)
           IF (DD1 == ZERO) EXIT ! Enclosing cell case - done
         END IF

       ENDDO POS_BBOXES

       !=================================================================

       CONTAINS

         !===============================================================

         FUNCTION GET_GUAR_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_LEAF DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * LEAF OF THE ALTERNATING DIGITIAL TREE. A LEAF CAN BE         *
!        * INTERPRETED AS A 3D BOUNDING BOX OF THE BOUNDING BOXES. THE  *
!        * MINIMUM COORDINATES ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM   *
!        * COORDINATES BY XMAX(4-6). DUE TO THE CONSTRUCTION OF THE ADT *
!        * NO EMPTY LEAFS ARE PRESENT AND THE GUARANTEED DISTANCE IS    *
!        * OBTAINED BY THE WORST CASE SCENARIO.                         *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - ADT(LEAF)%XMIN(1))
         D2 = ABS(X - ADT(LEAF)%XMAX(4))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - ADT(LEAF)%XMIN(2))
         D2 = ABS(Y - ADT(LEAF)%XMAX(5))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - ADT(LEAF)%XMIN(3))
         D2 = ABS(Z - ADT(LEAF)%XMAX(6))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_LEAF

         !===============================================================

         FUNCTION GET_POS_DIST2_LEAF(LEAF)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_LEAF DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN LEAF OF THE *
!        * ALTERNATING DIGITIAL TREE. A LEAF CAN BE INTERPRETED AS A 3D *
!        * BOUNDING BOX OF THE BOUNDING BOXES. THE MINIMUM COORDINATES  *
!        * ARE GIVEN BY XMIN(1-3) AND THE MAXIMUM COORDINATES BY        *
!        * XMAX(4-6).                                                   *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_LEAF

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: LEAF

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < ADT(LEAF)%XMIN(1)) THEN
           DX =  X - ADT(LEAF)%XMIN(1)
         ELSE IF(X > ADT(LEAF)%XMAX(4)) THEN
           DX =  X - ADT(LEAF)%XMAX(4)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < ADT(LEAF)%XMIN(2)) THEN
           DY =  Y - ADT(LEAF)%XMIN(2)
         ELSE IF(Y > ADT(LEAF)%XMAX(5)) THEN
           DY =  Y - ADT(LEAF)%XMAX(5)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < ADT(LEAF)%XMIN(3)) THEN
           DZ =  Z - ADT(LEAF)%XMIN(3)
         ELSE IF(Z > ADT(LEAF)%XMAX(6)) THEN
           DZ =  Z - ADT(LEAF)%XMAX(6)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_LEAF = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_LEAF

         !===============================================================

         FUNCTION GET_GUAR_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_GUAR_DIST2_BBOX DETERMINES THE GUARANTEED MINIMUM        *
!        * DISTANCE SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN    *
!        * BOUNDING BOX. THIS IS DONE BY APPLYING THE WORST CASE        *
!        * SCENARIO, I.E. THE DISTANCE TO THE FARTHEST POINT OF THE BOX.*
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_GUAR_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        LOCAL VARIABLES.

         REAL :: D1, D2

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         D1 = ABS(X - XBBOX(1,BBOX))
         D2 = ABS(X - XBBOX(4,BBOX))
         DX = MAX(D1,D2)

         ! Y-COORDINATE.

         D1 = ABS(Y - XBBOX(2,BBOX))
         D2 = ABS(Y - XBBOX(5,BBOX))
         DY = MAX(D1,D2)

         ! Z-COORDINATE.

         D1 = ABS(Z - XBBOX(3,BBOX))
         D2 = ABS(Z - XBBOX(6,BBOX))
         DZ = MAX(D1,D2)

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_GUAR_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_GUAR_DIST2_BBOX

         !===============================================================

         FUNCTION GET_POS_DIST2_BBOX(BBOX)

!        ****************************************************************
!        *                                                              *
!        * GET_POS_DIST2_BBOX DETERMINES THE POSSIBLE MINIMUM DISTANCE  *
!        * SQUARED FROM THE ACTIVE POINT X,Y,Z TO THE GIVEN BOUNDING    *
!        * BOX. THIS IS DONE BY APPLYING THE BEST CASE SCENARIO, I.E.   *
!        * THE DISTANCE TO THE CLOSEST POINT OF THE BOX.                *
!        *                                                              *
!        ****************************************************************

         IMPLICIT NONE

!        FUNCTION TYPE

         REAL :: GET_POS_DIST2_BBOX

!        FUNCTION ARGUMENTS

         INTEGER, INTENT(IN) :: BBOX

!        ****************************************************************
!        *                                                              *
!        * BEGIN EXECUTION                                              *
!        *                                                              *
!        ****************************************************************

         ! X-COORDINATE.

         IF(     X < XBBOX(1,BBOX)) THEN
           DX =  X - XBBOX(1,BBOX)
         ELSE IF(X > XBBOX(4,BBOX)) THEN
           DX =  X - XBBOX(4,BBOX)
         ELSE
           DX = ZERO
         ENDIF

         ! Y-COORDINATE.

         IF(     Y < XBBOX(2,BBOX)) THEN
           DY =  Y - XBBOX(2,BBOX)
         ELSE IF(Y > XBBOX(5,BBOX)) THEN
           DY =  Y - XBBOX(5,BBOX)
         ELSE
           DY = ZERO
         ENDIF

         ! Z-COORDINATE.

         IF(     Z < XBBOX(3,BBOX)) THEN
           DZ =  Z - XBBOX(3,BBOX)
         ELSE IF(Z > XBBOX(6,BBOX)) THEN
           DZ =  Z - XBBOX(6,BBOX)
         ELSE
           DZ = ZERO
         ENDIF

         ! AND COMPUTE THE DISTANCE SQUARED.

         GET_POS_DIST2_BBOX = DX*DX + DY*DY + DZ*DZ

         END FUNCTION GET_POS_DIST2_BBOX

       END SUBROUTINE SEARCH_MIXED_CELL_ADT

!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
       subroutine terminate (module, message)
!      !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!      Diagnostic routine missing from ADT package.

       implicit none

!      Arguments:

       character, intent (in) :: module*(*), message*(*)

!      Execution:

       write (*, '(/, 3a)') module, ': ', message
       stop

       end subroutine terminate

!      ******************************************************************
!
       SUBROUTINE QSORT_BBOX_TARGET_TYPE (ARR, NN)
!
!      ******************************************************************
!      *                                                                *
!      * QSORT_BBOX_TARGET_TYPE SORTS THE GIVEN NUMBER OF ELEMENTS OF   *
!      * TYPE BBOX_TARGET_TYPE IN INCREASING ORDER BASED ON THE <=      *
!      * OPERATOR FOR THIS DERIVED DATA TYPE.                           *
!      *                                                                *
!      * FILE:          qsort_bbox_target_type.f90                      *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-10-2003                                      *
!      * LAST MODIFIED: 11-21-2003                                      *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 08-02-13     "       "     Combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************
!
       USE ADT_DATA

       IMPLICIT NONE
!
!      ARGUMENTS:.
!
       INTEGER, INTENT(IN) :: NN

       TYPE(BBOX_TARGET_TYPE), DIMENSION(*), INTENT(INOUT) :: ARR
!
!      LOCAL VARIABLES.
!
       INTEGER, PARAMETER :: M = 7

       INTEGER :: I, J, K, R, L, JSTACK

       TYPE(BBOX_TARGET_TYPE) :: A, TMP

       LOGICAL :: DEBUG_MODE =.FALSE.
!
!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************
!
       ! INITIALIZE THE VARIABLES THAT CONTROL THE SORTING.

       JSTACK = 0
       L      = 1
       R      = NN

       ! START OF THE ALGORITHM

       DO

         ! CHECK FOR THE SIZE OF THE SUBARRAY.

         IF((R-L) < M) THEN

           ! PERFORM INSERTION SORT

           DO J=L+1,R
             A = ARR(J)
             DO I=(J-1),L,-1
               IF(ARR(I) <= A) EXIT
               ARR(I+1) = ARR(I)
             ENDDO
             ARR(I+1) = A
           ENDDO

           ! IN CASE THERE ARE NO MORE ELEMENTS ON THE STACK, EXIT FROM
           ! THE OUTERMOST DO-LOOP. ALGORITHM HAS FINISHED.

           IF(JSTACK == 0) EXIT

           ! POP STACK AND BEGIN A NEW ROUND OF PARTITIONING.

           R = STACK(JSTACK)
           L = STACK(JSTACK-1)
           JSTACK = JSTACK - 2

         ELSE

           ! SUBARRAY IS LARGER THAN THE THRESHOLD FOR A LINEAR SORT.
           ! CHOOSE MEDIAN OF LEFT, CENTER AND RIGHT ELEMENTS AS PARTITIONING
           ! ELEMENT A. ALSO REARRANGE SO THAT (L) <= (L+1) <= (R).

           K = (L+R)/2
           TMP      = ARR(K)      ! SWAP THE ELEMENTS
           ARR(K)   = ARR(L+1)    ! K AND L+1.
           ARR(L+1) = TMP

           IF(ARR(R) < ARR(L)) THEN
             TMP    = ARR(L)             ! SWAP THE ELEMENTS
             ARR(L) = ARR(R)             ! R AND L.
             ARR(R) = TMP
           ENDIF

           IF(ARR(R) < ARR(L+1)) THEN
             TMP      = ARR(L+1)         ! SWAP THE ELEMENTS
             ARR(L+1) = ARR(R)           ! R AND L+1.
             ARR(R)   = TMP
           ENDIF

           IF(ARR(L+1) < ARR(L)) THEN
             TMP      = ARR(L+1)         ! SWAP THE ELEMENTS
             ARR(L+1) = ARR(L)           ! L AND L+1.
             ARR(L)   = TMP
           ENDIF

           ! INITIALIZE THE POINTERS FOR PARTITIONING.

           I = L+1
           J = R
           A = ARR(L+1)

           ! THE INNERMOST LOOP

           DO

             ! SCAN UP TO FIND ELEMENT >= A.
             DO
               I = I+1
               IF(A <= ARR(I)) EXIT
             ENDDO

             ! SCAN DOWN TO FIND ELEMENT <= A.
             DO
               J = J-1
               IF(ARR(J) <= A) EXIT
             ENDDO

             ! EXIT THE LOOP IN CASE THE POINTERS I AND J CROSSED.

             IF(J < I) EXIT

             ! SWAP THE ELEMENT I AND J.

             TMP    = ARR(I)
             ARR(I) = ARR(J)
             ARR(J) = TMP
           ENDDO

           ! SWAP THE ENTRIES J AND L+1. REMEMBER THAT A EQUALS
           ! ARR(L+1).

           ARR(L+1) = ARR(J)
           ARR(J)   = A

           ! PUSH POINTERS TO LARGER SUBARRAY ON STACK,
           ! PROCESS SMALLER SUBARRAY IMMEDIATELY.

           JSTACK = JSTACK + 2
           IF(JSTACK > NSTACK) CALL REALLOCATE_STACK

           IF((R-I+1) >= (J-L)) THEN
             STACK(JSTACK)   = R
             R               = J-1
             STACK(JSTACK-1) = J
           ELSE
             STACK(JSTACK)   = J-1
             STACK(JSTACK-1) = L
             L               = J
           ENDIF

         ENDIF
       ENDDO

       ! CHECK IN DEBUG MODE WHETHER THE ARRAY IS REALLY SORTED.

       IF( DEBUG_MODE ) THEN
         DO I=1,(NN-1)
           IF(ARR(I+1) < ARR(I))                       &
             CALL TERMINATE ("QSORT_BBOX_TARGET_TYPE", &
                             "Array is not sorted correctly")
         ENDDO
       ENDIF

       END SUBROUTINE QSORT_BBOX_TARGET_TYPE

!      ******************************************************************
!
       SUBROUTINE QSORT_REALS (ARR, NN)
!
!      ******************************************************************
!      *                                                                *
!      * QSORT_REALS SORTS THE GIVEN NUMBER OF REALS IN INCREASING      *
!      * ORDER.                                                         *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 03-03-2003                                      *
!      * LAST MODIFIED: 04-07-2003                                      *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 08-02-13     "       "     Combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************
!
       IMPLICIT NONE
!
!      ARGUMENTS:
!
       REAL, DIMENSION(*), INTENT(INOUT) :: ARR
       INTEGER, INTENT(IN)               :: NN
!
!      LOCAL VARIABLES
!
       INTEGER, PARAMETER :: M = 7

       INTEGER :: NSTACK
       INTEGER :: I, J, K, R, L, JSTACK, II
       INTEGER :: IERR

       REAL :: A, TMP

       INTEGER, ALLOCATABLE, DIMENSION(:) :: STACK, TMP_STACK

       LOGICAL :: DEBUG_MODE = .FALSE.
!
!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************
!
       ! ALLOCATE THE MEMORY FOR STACK.

       NSTACK = 100
       ALLOCATE(STACK(NSTACK), STAT=IERR)
       IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                                     "Memory allocation failure for STACK")

       ! INITIALIZE THE VARIABLES THAT CONTROL THE SORTING.

       JSTACK = 0
       L      = 1
       R      = NN

       ! START OF THE ALGORITHM

       DO

         ! CHECK FOR THE SIZE OF THE SUBARRAY.

         IF((R-L) < M) THEN

           ! PERFORM INSERTION SORT

           DO J=L+1,R
             A = ARR(J)
             DO I=(J-1),L,-1
               IF(ARR(I) <= A) EXIT
               ARR(I+1) = ARR(I)
             ENDDO
             ARR(I+1) = A
           ENDDO

           ! IN CASE THERE ARE NO MORE ELEMENTS ON THE STACK, EXIT FROM
           ! THE OUTERMOST DO-LOOP. ALGORITHM HAS FINISHED.

           IF(JSTACK == 0) EXIT

           ! POP STACK AND BEGIN A NEW ROUND OF PARTITIONING.

           R = STACK(JSTACK)
           L = STACK(JSTACK-1)
           JSTACK = JSTACK - 2

         ELSE

           ! SUBARRAY IS LARGER THAN THE THRESHOLD FOR A LINEAR SORT.
           ! CHOOSE MEDIAN OF LEFT, CENTER AND RIGHT ELEMENTS AS PARTITIONING
           ! ELEMENT A. ALSO REARRANGE SO THAT (L) <= (L+1) <= (R).

           K = (L+R)/2
           TMP      = ARR(K)      ! SWAP THE ELEMENTS
           ARR(K)   = ARR(L+1)    ! K AND L+1.
           ARR(L+1) = TMP

           IF(ARR(R) < ARR(L)) THEN
             TMP    = ARR(L)             ! SWAP THE ELEMENTS
             ARR(L) = ARR(R)             ! R AND L.
             ARR(R) = TMP
           ENDIF

           IF(ARR(R) < ARR(L+1)) THEN
             TMP      = ARR(L+1)         ! SWAP THE ELEMENTS
             ARR(L+1) = ARR(R)           ! R AND L+1.
             ARR(R)   = TMP
           ENDIF

           IF(ARR(L+1) < ARR(L)) THEN
             TMP      = ARR(L+1)         ! SWAP THE ELEMENTS
             ARR(L+1) = ARR(L)           ! L AND L+1.
             ARR(L)   = TMP
           ENDIF

           ! INITIALIZE THE POINTERS FOR PARTITIONING.

           I = L+1
           J = R
           A = ARR(L+1)

           ! THE INNERMOST LOOP

           DO

             ! SCAN UP TO FIND ELEMENT >= A.
             DO
               I = I+1
               IF(A <= ARR(I)) EXIT
             ENDDO

             ! SCAN DOWN TO FIND ELEMENT <= A.
             DO
               J = J-1
               IF(ARR(J) <= A) EXIT
             ENDDO

             ! EXIT THE LOOP IN CASE THE POINTERS I AND J CROSSED.

             IF(J < I) EXIT

             ! SWAP THE ELEMENT I AND J.

             TMP    = ARR(I)
             ARR(I) = ARR(J)
             ARR(J) = TMP
           ENDDO

           ! SWAP THE ENTRIES J AND L+1. REMEMBER THAT A EQUALS
           ! ARR(L+1).

           ARR(L+1) = ARR(J)
           ARR(J)   = A

           ! PUSH POINTERS TO LARGER SUBARRAY ON STACK,
           ! PROCESS SMALLER SUBARRAY IMMEDIATELY.

           JSTACK = JSTACK + 2
           IF(JSTACK > NSTACK) THEN

             ! STORAGE OF THE STACK IS TOO SMALL. REALLOCATE.

             ALLOCATE(TMP_STACK(NSTACK), STAT=IERR)
             IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                                "Memory allocation error for TMP_STACK")
             TMP_STACK = STACK

             ! FREE THE MEMORY OF STACK, STORE THE OLD VALUE OF NSTACK
             ! IN TMP AND INCREASE NSTACK.

             DEALLOCATE(STACK, STAT=IERR)
             IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                                        "Unexpected deallocation error")
             II = NSTACK
             NSTACK = NSTACK + 100

             ! ALLOCATE THE MEMORY FOR STACK AND COPY THE OLD VALUES
             ! FROM TMP_STACK.

             ALLOCATE(STACK(NSTACK), STAT=IERR)
             IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                                  "Memory reallocation error for STACK")
             STACK(1:II) = TMP_STACK(1:II)

             ! AND FINALLY RELEASE THE MEMORY OF TMP_STACK.

             DEALLOCATE(TMP_STACK, STAT=IERR)
             IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                                        "Unexpected deallocation error")
           ENDIF

           IF((R-I+1) >= (J-L)) THEN
             STACK(JSTACK)   = R
             R               = J-1
             STACK(JSTACK-1) = J
           ELSE
             STACK(JSTACK)   = J-1
             STACK(JSTACK-1) = L
             L               = J
           ENDIF

         ENDIF
       ENDDO

       ! RELEASE THE MEMORY OF STACK.

       DEALLOCATE(STACK, STAT=IERR)
       IF(IERR /= 0) CALL TERMINATE ("QSORT_REALS", &
                              "Unexpected deallocation error for STACK")

       ! CHECK IN DEBUG MODE WHETHER THE ARRAY IS REALLY SORTED.

       IF( DEBUG_MODE ) THEN
         DO I=1,(NN-1)
           IF(ARR(I+1) < ARR(I))          &
             CALL TERMINATE ("QSORT_REALS", &
                             "Array is not sorted correctly")
         ENDDO
       ENDIF

       END SUBROUTINE QSORT_REALS

!      ******************************************************************
!
       SUBROUTINE REALLOC_BBOX_TARGETS
!
!      ******************************************************************
!      *                                                                *
!      * REALLOC_BBOX_TARGETS REALLOCATES THE MEMORY FOR THE ARRAY      *
!      * BBOX_TARGETS.                                                  *
!      *                                                                *
!      * AUTHOR:        EDWIN VAN DER WEIDE                             *
!      * STARTING DATE: 11-10-2003                                      *
!      * LAST MODIFIED: 11-10-2003                                      *
!      * 05-19-04:  David Saunders  Dispensed with precision clutter.   *
!      * 08-02-13     "       "     Combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      LOCAL VARIABLES.

       INTEGER :: IERR

       INTEGER :: I, NN

       TYPE(BBOX_TARGET_TYPE), DIMENSION(:), ALLOCATABLE :: TMP
!
!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************
!
       ! STORE THE OLD VALUE OF NALLOC_BBOX AND ALLOCATE THE MEMORY
       ! FOR TMP.

       NN = NALLOC_BBOX
       ALLOCATE(TMP(NN), STAT=IERR)
       IF(IERR /= 0)                             &
         CALL TERMINATE ("REALLOC_BBOX_TARGETS", &
                         "Memory allocation failure for TMP.")

       ! COPY THE DATA OF BBOX_TARGETS INTO TMP.

       DO I=1,NN
         TMP(I) = BBOX_TARGETS(I)
       ENDDO

       ! RELEASE THE MEMORY OF BBOX_TARGETS AND ALLOCATE IT AGAIN WITH
       ! AN INCREASED NUMBER OF ENTITIES.

       NALLOC_BBOX = NALLOC_BBOX + 100

       DEALLOCATE(BBOX_TARGETS, STAT=IERR)
       IF(IERR /= 0)                             &
         CALL TERMINATE ("REALLOC_BBOX_TARGETS", &
                         "Deallocation error for BBOX_TARGETS.")

       ALLOCATE(BBOX_TARGETS(NALLOC_BBOX), STAT=IERR)
       IF(IERR /= 0)                             &
         CALL TERMINATE ("REALLOC_BBOX_TARGETS", &
                         "Memory allocation failure for BBOX_TARGETS.")

       ! COPY THE DATA FROM TMP BACK INTO BBOX_TARGETS.

       DO I=1,NN
         BBOX_TARGETS(I) = TMP(I)
       ENDDO

       ! FINALLY, RELEASE THE MEMORY OF TMP.

       DEALLOCATE(TMP, STAT=IERR)
       IF(IERR /= 0)                             &
         CALL TERMINATE ("REALLOC_BBOX_TARGETS", &
                         "Deallocation error for TMP.")

       END SUBROUTINE REALLOC_BBOX_TARGETS

!      ==================================================================

       SUBROUTINE REALLOC_FRONT_LEAVES_NEW
!
!      ******************************************************************
!      *                                                                *
!      * REALLOC_FRONT_LEAVES_NEW REALLOCATES THE MEMORY FOR THE ARRAY  *
!      * FRONT_LEAVES_NEW.                                              *
!      *                                                                *
!      ******************************************************************
!
       USE ADT_DATA

       IMPLICIT NONE

!      LOCAL VARIABLES.

       INTEGER :: IERR

       INTEGER :: I, NN

       INTEGER, DIMENSION(:), ALLOCATABLE :: TMP
!
!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************
!
       ! STORE THE OLD VALUE OF NALLOC_FRONT_LEAVES_NEW AND ALLOCATE THE
       ! MEMORY FOR TMP.

       NN = NALLOC_FRONT_LEAVES_NEW
       ALLOCATE(TMP(NN), STAT=IERR)
       IF(IERR /= 0)                                 &
         CALL TERMINATE ("REALLOC_FRONT_LEAVES_NEW", &
                         "Memory allocation failure for TMP.")

       ! COPY THE DATA OF FRONT_LEAVES_NEW INTO TMP.

       DO I=1,NN
         TMP(I) = FRONT_LEAVES_NEW(I)
       ENDDO

       ! RELEASE THE MEMORY OF FRONT_LEAVES_NEW AND ALLOCATE IT AGAIN
       ! WITH AN INCREASED NUMBER OF ENTITIES.

       NALLOC_FRONT_LEAVES_NEW = NALLOC_FRONT_LEAVES_NEW + 100

       DEALLOCATE(FRONT_LEAVES_NEW, STAT=IERR)
       IF(IERR /= 0)                                 &
         CALL TERMINATE ("REALLOC_FRONT_LEAVES_NEW", &
                         "Deallocation error for FRONT_LEAVES_NEW.")

       ALLOCATE(FRONT_LEAVES_NEW(NALLOC_FRONT_LEAVES_NEW), STAT=IERR)
       IF(IERR /= 0)                                 &
         CALL TERMINATE ("REALLOC_FRONT_LEAVES_NEW", &
                         "Memory allocation failure for &
                         FRONT_LEAVES_NEW.")

       ! COPY THE DATA FROM TMP BACK INTO FRONT_LEAVES_NEW.

       DO I=1,NN
         FRONT_LEAVES_NEW(I) = TMP(I)
       ENDDO

       ! FINALLY, RELEASE THE MEMORY OF TMP.

       DEALLOCATE(TMP, STAT=IERR)
       IF(IERR /= 0)                                 &
         CALL TERMINATE ("REALLOC_FRONT_LEAVES_NEW", &
                         "Deallocation error for TMP.")

       END SUBROUTINE REALLOC_FRONT_LEAVES_NEW

!      ==================================================================

       SUBROUTINE REALLOC_STACK
!
!      ******************************************************************
!      *                                                                *
!      * REALLOC_STACK REALLOCATES THE MEMORY FOR THE ARRAY STACK.      *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      LOCAL VARIABLES.

       INTEGER :: IERR

       INTEGER :: I, NN

       INTEGER, DIMENSION(:), ALLOCATABLE :: TMP

!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************

       ! STORE THE OLD VALUE OF NSTACK AND ALLOCATE THE MEMORY FOR TMP.

       NN = NSTACK
       ALLOCATE(TMP(NN), STAT=IERR)
       IF(IERR /= 0)                      &
         CALL TERMINATE ("REALLOC_STACK", &
                         "Memory allocation failure for TMP.")

       ! COPY THE DATA OF STACK INTO TMP.

       DO I=1,NN
         TMP(I) = STACK(I)
       ENDDO

       ! RELEASE THE MEMORY OF STACK AND ALLOCATE IT AGAIN WITH AN
       ! INCREASED NUMBER OF ENTITIES.

       NSTACK = NSTACK + 100

       DEALLOCATE(STACK, STAT=IERR)
       IF(IERR /= 0)                      &
         CALL TERMINATE ("REALLOC_STACK", &
                         "Deallocation error for STACK.")

       ALLOCATE(STACK(NSTACK), STAT=IERR)
       IF(IERR /= 0)                      &
         CALL TERMINATE ("REALLOC_STACK", &
                         "Memory allocation failure for STACK.")

       ! COPY THE DATA FROM TMP BACK INTO STACK.

       DO I=1,NN
         STACK(I) = TMP(I)
       ENDDO

       ! FINALLY, RELEASE THE MEMORY OF TMP.

       DEALLOCATE(TMP, STAT=IERR)
       IF(IERR /= 0)                      &
         CALL TERMINATE ("REALLOC_STACK", &
                         "Deallocation error for TMP.")

       END SUBROUTINE REALLOC_STACK

!      ==================================================================

       SUBROUTINE REALLOCATE_STACK
!
!      ******************************************************************
!      *                                                                *
!      * REALLOCATE_STACK REALLOCATES THE STACK ARRAY USED IN THE       *
!      * ROUTINE QSORT_BBOX_TARGET_TYPE. THE ARRAY STACK IS STORED IN   *
!      * THE MODULE ADT_DATA SUCH THAT IT IS NOT ALLOCATED, REALLOCATED *
!      * AND RELEASED ALL THE TIME.                                     *
!      *                                                                *
!      ******************************************************************
!
       USE ADT_DATA

       IMPLICIT NONE
!
!      LOCAL VARIABLES.
!
       INTEGER :: IERR

       INTEGER :: NSTACK_OLD, I

       INTEGER, DIMENSION(:), ALLOCATABLE :: TMP_STACK
!
!      ******************************************************************
!      *                                                                *
!      * BEGIN EXECUTION                                                *
!      *                                                                *
!      ******************************************************************
!
       ! ALLOCATE THE MEMORY OF TMP_STACK.

       ALLOCATE(TMP_STACK(NSTACK), STAT=IERR)
       IF(IERR /= 0)                          &
          CALL TERMINATE ("REALLOCATE_STACK", &
                          "Memory allocation error for TMP_STACK")

       ! COPY THE VALUES OF STACK INTO TMP_STACK; SAVE THE OLD VALUE
       ! OF NSTACK.

       NSTACK_OLD = NSTACK
       DO I=1,NSTACK
         TMP_STACK(I) = STACK(I)
       ENDDO

       ! RELEASE THE MEMORY OF STACK AND ALLOCATE IT AGAIN WITH A HIGHER
       ! VALUE OF NSTACK.

       DEALLOCATE(STACK, STAT=IERR)
       IF(IERR /= 0)                          &
          CALL TERMINATE ("REALLOCATE_STACK", &
                          "Deallocation error for STACK")

       NSTACK = NSTACK + 100
       ALLOCATE(STACK(NSTACK), STAT=IERR)
       IF(IERR /= 0)                          &
          CALL TERMINATE ("REALLOCATE_STACK", &
                          "Memory allocation error for STACK")

       ! COPY THE ORIGINAL DATA BACK INTO STACK AND RELEASE THE MEMORY
       ! OF TMP_STACK.

       DO I=1,NSTACK_OLD
         STACK(I) = TMP_STACK(I)
       ENDDO

       DEALLOCATE(TMP_STACK, STAT=IERR)
       IF(IERR /= 0)                          &
          CALL TERMINATE ("REALLOCATE_STACK", &
                          "Deallocation error for TMP_STACK")

       END SUBROUTINE REALLOCATE_STACK

!      ******************************************************************

       SUBROUTINE RELEASE_ADT ()

!      * RELEASE_ADT deallocates the internal work-space allocated by   *
!      * BUILD_*_ADT and shared by SEARCH_*_ADT.                        *
!      *                                                                *
!      * 04-15-05:  David Saunders    Added to the package for use by   *
!      *            ELORET/NASA ARC   applications building 2+ trees.   *
!      * 08-02-13   DAS, ERC/ARC    Combined all variants into 1 file.  *
!      *                                                                *
!      ******************************************************************

       USE ADT_DATA

       IMPLICIT NONE

!      LOCAL VARIABLES:
!      ----------------

       INTEGER :: IER

!      EXECUTION:
!      ----------

       IF (ALLOCATED (BBOX_TARGETS))     DEALLOCATE (BBOX_TARGETS,     STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for BBOX_TARGETS.")

       IF (ALLOCATED (FRONT_LEAVES))     DEALLOCATE (FRONT_LEAVES,     STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for FRONT_LEAVES.")

       IF (ALLOCATED (FRONT_LEAVES_NEW)) DEALLOCATE (FRONT_LEAVES_NEW, STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for FRONT_LEAVES_NEW.")

       IF (ALLOCATED (STACK))            DEALLOCATE (STACK,            STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for STACK.")

       IF (ALLOCATED (ADT))              DEALLOCATE (ADT,              STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for ADT.")

       IF (ALLOCATED (XBBOX))            DEALLOCATE (XBBOX,            STAT=IER)
       IF (IER /= 0) CALL TERMINATE ("RELEASE_ADT", &
          "Memory deallocation failure for XBBOX.")

       END SUBROUTINE RELEASE_ADT

   end module adt_utilities
