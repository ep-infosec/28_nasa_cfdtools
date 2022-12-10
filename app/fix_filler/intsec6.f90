!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   subroutine intsec6 (npatches, surface_patches, nquad, conn,                 &
                       nline, xline, yline, zline, tline, lcs_method,          &
                       iquad, pint, qint, tint, xyzint, dsq)
!  Purpose:
!
!     Calculate the intersection of a 3-space line or curve defined by two or
!  more points with a structured surface defined by one or more surface patches.
!  If the line and curve do not actually meet, the curve may be extrapolated
!  (tint outside [0, 1]), but the surface will not be extrapolated.  The point
!  on the surface nearest to the [possibly extrapolated] line will always be
!  determined.  The shortest squared distance returned indicates whether a true
!  intersection was found or not (although a tangential meeting is possible and
!  not easily distinguished).
!
!  Strategy:
!
!     The two-point line case is explained most readily.  Any point on P1 P2
!  may be represented as P(t) = (1 - t) P1 + t P2.  The surface quadrilateral
!  closest to this point may be determined efficiently via an ADT search of the
!  surface grid.  A 1-D minimization of the squared distance w.r.t. t solves the
!  problem.  In the case of a curve, the local spline method of LCSFIT can be
!  used similarly to calculate (x,y,z) as functions of normalized arc length t.
!
!  Outline of search tree construction:
!
!  nquad = 0
!  do ib = 1, npatches
!    nquad = (surface_patches(ib)%ni - 1) * (surface_patches(ib)%nj - 1) + nquad
!  end do
!
!  allocate (conn(3,nquad)) ! For patch # and (i,j)
!
!  call build_adt (npatches, surface_patches, nquad, conn)
!
!  History:
!
!  06/13/05  DAS  Initial implementation for the 2-point line case; leave hooks
!                 for the 3+-point line case, piecewise linear or not.
!  08/25/06   "   Completed the 3+-point case.  The fact that the arc lengths
!                 are normalized still allows tline(1) and tline(n) to be used
!                 to define the search interval (because we know those arcs are
!                 0 and 1), but two other arguments would have been better.
!                 The 0 and 1 have to be substituted here, then ta and tb are
!                 restored before the return.
!                 Requiring tline(:) as input (as opposed to deriving arcs from
!                 x/y/zline(:) here) is considered better since the application
!                 is likely to need those arc lengths anyway.
!
!  Author:  David Saunders, ELORET/NASA Ames Research Center, Moffett Field, CA
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   use grid_block_structure  ! For derived data type used by the ADT package

   implicit none

!  Arguments:

   integer, intent (in)  :: npatches       ! # surface grid patches

   type (grid_type), intent (in) :: &
            surface_patches (npatches)     ! Surface grid; may be a volume grid
                                           ! of which only k = 1 is used
   integer, intent (in)  :: nquad          ! # surface quads., all patches

   integer, intent (in)  :: conn(3,nquad)  ! Patch # and (i,j) for each quad.

   integer, intent (in)  :: nline          ! # points defining the line, >= 2

   real,    intent (in), dimension (nline) :: &
            xline, yline, zline            ! Line coordinates

   real,    intent (inout) :: tline(nline) ! Input with normalized arc lengths
                                           ! if nline > 2.  Use tline(1) and
                                           ! tline(nline) to indicate the range
                                           ! of t (possibly beyond [0, 1]) that
                                           ! should contain the intersection;
                                           ! see the 08/25/06 history above
   character, intent (in) :: lcs_method*1  ! 'L', 'M', or 'B' as for LCSFIT
                                           ! (if nline > 2)
   integer, intent (out)  :: iquad         ! conn(:,iquad) points to the best
                                           ! surface cell cell found
   real,    intent (out)  :: pint, qint    ! Corresponding interpolation coefs.
                                           ! in the unit square
   real,    intent (out)  :: tint          ! Normalized arc length along the
                                           ! line at the best point found
   real,    intent (out)  :: xyzint(3)     ! Surface point nearest to the
                                           ! intended intersection point
   real,    intent (out)  :: dsq           ! Corresponding squared distance
                                           ! to the nearest line point

!  Local constants:

   integer,   parameter :: lunout = -6     ! Suppress FMINRC iteration printout
   integer,   parameter :: nfmax  = 50     ! Limit on # function evaluations
   real,      parameter :: one    = 1.
   real,      parameter :: zero   = 0.
   logical,   parameter :: false  = .false.
   logical,   parameter :: true   = .true.
   character, parameter :: caller * 7 = 'INTSEC6'

!  Local variables:

   integer :: ieval, istat, lunerr, numfun
   real    :: t, ta, tb, tol
   logical :: new_plscrv3d, two_points

!  Execution:

!  A minimum can be found to within sqrt (machine epsilon), but avoid the sqrt:

   if (epsilon (tol) < 1.e-10) then
      tol = 1.e-8
   else
      tol = 1.e-4
   end if

   two_points = nline == 2

   ta = tline(1)       ! 0 and 1 ...
   tb = tline(nline)   ! ... unless extrapolation is being permitted

   if (.not. two_points) then
      tline(1)     = zero
      tline(nline) = one
      ieval        = nint (0.5 * (ta + tb) * real (nline))
      ieval        = min (nline - 1, max (1, ieval))
      new_plscrv3d = true
   end if

   numfun = nfmax      ! Limit; FMINRC typically takes about 6 iterations
   lunerr = abs (lunout)
   istat = 2           ! Initialize the minimization

10 continue

      call fminrc (ta, tb, t, dsq, tol, numfun, caller, -lunout, istat)

      if (istat < -1) then

         write (lunerr, '(/, 2a)') caller, ': FMINRC fatal error'
         stop

      else if (istat < 0) then ! Iteration limit; may be usable

         write (lunerr, '(/, 2a)') caller, ': Iteration limit.'

      else if (istat > 0) then ! Evaluate the objective function at t

         call objective   ! Internal procedure below
         go to 10

      else ! istat = 0 (success).

      end if

!  Ensure that everything matches t(best), not t(last):

   call objective ()

   tint = t

   if (.not. two_points) then
      tline(1)     = ta
      tline(nline) = tb
   end if

!  Internal procedure for subroutine intsec6:

   contains

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine objective ()

!     Calculate the squared distance from the line point defined by t to the
!     nearest cell of the structured surface grid.

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      integer :: i
      real :: tm1, xyztarget(3)
      real, save :: derivs = -999. ! -999. suppresses partial deriv. calcs.

      if (two_points) then

         tm1 = one - t

         xyztarget(1) = tm1 * xline(1) + t * xline(2)
         xyztarget(2) = tm1 * yline(1) + t * yline(2)
         xyztarget(3) = tm1 * zline(1) + t * zline(2)

      else  ! Spline interpolation at t:

         write (6, *) 'nline', nline
         write (6, '(i4, 3f12.6)') (i, xline(i), yline(i), zline(i), i=1,nline)

         call plscrv3d (nline, xline, yline, zline, tline, lcs_method,         &
                        new_plscrv3d, false, t, ieval, xyztarget(1),           &
                        xyztarget(2), xyztarget(3), derivs)
         write (6, *) 'xyztarget:', xyztarget

         new_plscrv3d = false  ! After the first call
      end if

      write (6, '(a, 1p, 3e19.11)') ' xyztarget:', xyztarget

      call search_adt (xyztarget, iquad, pint, qint, dsq, true, npatches,      &
                       surface_patches, nquad, conn, xyzint)

      write (6, '(a, 1p, 3e19.11)') ' pint, qint, dsq:', pint, qint, dsq
      write (6, '(i4, 3i6)') (i, conn(:,i), i = 1, nquad)

      if (i > 0) stop

      end subroutine objective

   end subroutine intsec6
