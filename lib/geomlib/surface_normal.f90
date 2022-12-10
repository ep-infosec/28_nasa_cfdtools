!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   subroutine surface_normal (ni, nj, x, y, z, ic, jc, pc, qc, unit_normal)

!  Description:
!
!     Calculate a unit normal to a structured surface patch in a way that takes
!     account of cells surrounding the indicated cell.  This is motivated by the
!     desire to obtain the same result for equivalent specifications that are
!     all possible from surface search algorithms.  For instance:
!
!        i     j     p    q                These all specify the same
!        3     7     1.   1.               surface grid point, but the
!        4     8     0.   0.               simple approaches of using cell
!        3     8     1.   0.               sides or diagonals can easily
!        4     7     0.   1.               produce four different normals.
!
!  Technique:
!
!     Construct an artificial cell surrounding the target point using points
!        (p-0.5, q-0.5), (p+0.5, q-0.5), (p-0.5, q+0.5), (p+0.5, q+0.5)
!     except if (say) p+0.5 > 1.0 then use p-0.5 in cell (i+1,*), and so on.
!
!     This is still not perfect at a patch boundary where any neighboring patch
!     should really be made use of, but treating multipatch surfaces properly
!     would require patch connectivity information that is beyond the scope of
!     this single-patch utility.  Instead, points at or near a patch edge are
!     surrounded by partial new cells.
!
!     In all cases, cell diagonals are used for the cross-product that produces
!     the desired unit vector.  If the surface is a right-handed patch, the unit
!     normal points outward.
!
!  History:
!
!     10/12/05  D.A.Saunders  Initial implementation.
!     02/21/14    "     "     The requirement to avoid i = ni or j = nj has
!                             caused too much grief.  Handle those cases here
!                             instead of in the application.  The i/j/p/q
!                             arguments have been renamed ic/jc/pc/qc to
!                             avoid changing the main code.
!
!  Author:  David Saunders, ELORET/NASA Ames Research Center, Moffett Field, CA
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   implicit none

!  Arguments:

   integer, intent (in)  :: ni, nj                 ! (Packed) patch array dims.
   real, intent (in), dimension (ni,nj) :: x, y, z ! Patch coordinates
   integer, intent (in)  :: ic, jc                 ! Indicated cell, normally
                                                   ! "lower left" vertex if
                                                   ! the result of a search,
                                                   ! but ic = ni or jc = nj is
                                                   ! handled here now
   real,    intent (in)  :: pc, qc                 ! Fractional coords. in [0,1]
   real,    intent (out) :: unit_normal(3)         ! Desired unit normal vector

!  Local constants:

   real, parameter :: half = 0.5, one = 1.0, zero = 0.0

!  Local variables;

   integer :: i, im, ip, j, jm, jp
   real    :: p, pm, pp, q, qm, qp
   real    :: cell(3,2,2), vec1(3), vec2(3), vsize

!  Execution:

!  Avoid difficulties in the application: allow it to pass ic = ni or jc = nj,
!  but use adjusted indices if necessary.

   i = ic;  p = pc
   if (ic == ni) then  ! Be sure to point to the lower left vertex of a cell
       i = i - 1
       p = one         ! Presumably, the input pc is 0.
   end if

   j = jc;  q = qc
   if (jc == nj) then
       j = j - 1
       q = one
   end if

!  Set up an artifical cell surrounding the target point:

   if (p >= half) then
      pm = p - half
      im = i
   else if (i > 1) then
      pm = p + half
      im = i - 1
   else  ! i = 1
      pm = zero
      im = 1
   end if

   if (p < half) then
      pp = p + half
      ip = i
   else if (i < ni - 1) then
      pp = p - half
      ip = i + 1
   else  ! i = ni - 1
      pp = one
      ip = i
   end if

   if (q >= half) then
      qm = q - half
      jm = j
   else if (j > 1) then
      qm = q + half
      jm = j - 1
   else  ! j = 1
      qm = zero
      jm = 1
   end if

   if (q < half) then
      qp = q + half
      jp = j
   else if (j < nj - 1) then
      qp = q - half
      jp = j + 1
   else  ! j = nj - 1
      qp = one
      jp = j
   end if

!  Interpolate the x/y/z coordinates at these artificial cell vertices:

   call bilinear (im, jm, pm, qm, cell(:,1,1))
   call bilinear (ip, jm, pp, qm, cell(:,2,1))
   call bilinear (im, jp, pm, qp, cell(:,1,2))
   call bilinear (ip, jp, pp, qp, cell(:,2,2))

!  Diagonals of the artificial cell:

   vec1(1) = cell(1,2,2) - cell(1,1,1)
   vec1(2) = cell(2,2,2) - cell(2,1,1)
   vec1(3) = cell(3,2,2) - cell(3,1,1)

   vec2(1) = cell(1,1,2) - cell(1,2,1)
   vec2(2) = cell(2,1,2) - cell(2,2,1)
   vec2(3) = cell(3,1,2) - cell(3,2,1)

   call cross (vec1, vec2, unit_normal)  ! Not normalized yet

   vsize = sqrt (dot_product (unit_normal, unit_normal))
   unit_normal = unit_normal / vsize

!  Internal procedure for subroutine surface_normal:

   contains

      subroutine bilinear (ic, jc, p, q, xyz)

!     Not really bilinear because of the pq term ...

      integer, intent (in)  :: ic, jc  ! Lower left indices in x, y, z arrays
      real,    intent (in)  :: p, q    ! Fractional coordinates in that cell
      real,    intent (out) :: xyz(3)  ! Interpolated surface coordinates

      real :: pm1, qm1

      pm1 = one - p;  qm1 = one - q

      xyz(1) = qm1 * (pm1 * x(ic,jc  )  +  p * x(ic+1,jc  )) + &
                 q * (pm1 * x(ic,jc+1)  +  p * x(ic+1,jc+1))
      xyz(2) = qm1 * (pm1 * y(ic,jc  )  +  p * y(ic+1,jc  )) + &
                 q * (pm1 * y(ic,jc+1)  +  p * y(ic+1,jc+1))
      xyz(3) = qm1 * (pm1 * z(ic,jc  )  +  p * z(ic+1,jc  )) + &
                 q * (pm1 * z(ic,jc+1)  +  p * z(ic+1,jc+1))

      end subroutine bilinear

   end subroutine surface_normal
