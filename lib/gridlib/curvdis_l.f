C+------------------------------------------------------------------------------
C
      SUBROUTINE CURVDIS_L (NDAT, XDAT, YDAT, N, POWER, ISMOOTH,
     >                      LUNOUT, ARCS_ONLY, X, Y, IER)
C
C     Acronym:  CURVature-based DIStribution, Linear interpolation (2-space)
C               ----            ---           -
C
C     Purpose:
C
C        CURVDIS_L is a variant of the much earlier CURVDIS that uses
C     linear interpolation when evaluating X and Y and the redistributed
C     arc lengths.  The remaining description is from CURVDIS.
C
C        CURVDIS redistributes points along a curve in 2-space which is
C     represented by a discrete dataset, not necessarily monotonic, such
C     that the local spacing is inversely proportional to the local
C     curvature (with adjustments to handle the zero curvature regions).
C     CURVDIS is intended for geometric applications where the coord-
C     inates have comparable units, although it may be used for non-
C     geometric purposes as well (e.g. plotting applications).  In both
C     cases, if the units of the curve coordinates are large (producing
C     small values of curvatures), the coordinates should be normalized
C     to the range [0,1].  For geometric curves, only one of the coord-
C     inate axes should be scaled to [0,1] and the other axis should be
C     scaled such that the true geometric shape is retained.
C
C
C     Method:
C
C        Given the availability of subroutine ARBDIS for translating
C     arbitrary "shape" functions into 1-D distributions whose spacing
C     at any abscissa is proportional to the shape function at that
C     abscissa, the problem then is to set up a shape function related
C     to curvature; ARBDIS does the rest.  (Abscissas in this case are
C     measures of arc length along the curve, and the shape function is
C     defined at each of the original data points.)
C        The subroutine is passed NDAT coordinates (XDAT, YDAT), of the
C     curve, for which it computes the cumulative arc lengths (or more
C     precisely, the cumulative chord lengths), s(n).  Next, FD12K is
C     called twice to compute the 2nd derivatives (d2x/ds2 and d2y/ds2)
C     in order to approximate the local curvatures' magnitudes, k(s),
C     which are given by:
C
C        (1)   k(s) = sqrt((d2x/ds2)**2 + (d2y/ds2)**2)
C
C        A direct inverse proportionality would yield a shape function
C     with smaller spacings in regions of larger curvature.  However,
C     for straight segments of the curve where k(s) = 0., a simple
C     inverse proportionality such as shape(s) = 1./k(s) would produce
C     an infinite local spacing.  Therefore, some arbitrary constant
C     (say 1.) should be added to k(s) in the denominator.
C        Clustering may be controlled by raising this fraction to some
C     exponent in the range [0,1].  0 would produce shape(s) = 1., or
C     uniform spacing; 1 would yield "direct" inverse proportionality
C     spacing; and an exponent in between (0,1) would produce spacings
C     between these two extremes.  Thus, our spacing function becomes:
C
C         (2)   shape(s) = [1./(k(s) + 1.)]**exponent
C
C        After the relative spacings (defining the shape function) are
C     calculated from eqn. (2), an option is provided to smooth the
C     shape function to reduce abrupt changes observed in sphere/cone
C     capsule defining sections.  The ARBDIS utility is then called to
C     compute redistributed arc lengths for the specified number N of
C     output points.  A further option is provided to smooth those
C     arc-lengths (with index-based abscissas) as also found desirable
C     for sphere/cone applications.  LCSFIT then serves to evaluate the
C     new X-Y coordinates corresponding to the new arc lengths.
C
C        Note:  The work space is used/reused in the following sequence:
C
C     (1)  WORK(1:NDAT)                 Input curve chord lengths
C     (2)  WORK(NDAT+1:2*NDAT)          FP values for FD12K calls
C     (3)  WORK(2*NDAT+1:3*NDAT)        d2x/ds2 values
C     (4)  WORK(3*NDAT+1:4*NDAT)        d2y/ds2 values
C     (5)  WORK(NDAT+1:2*NDAT)          xdat-ydat relative spacings
C                                          defining the shape function
C     (6)  WORK(2*NDAT+1:2*NDAT+N)      New curve chord lengths
C     (7)  WORK(2*NDAT+N+1:5*NDAT+6*N)  Work area used by ARBDIS
C     (8)  WORK(2*NDAT+N+1:2*NDAT+2*N)  Reused for index-based abscissas
C                                       if ARBDIS results are smoothed
C
C     Procedures:
C
C        ARBDIS           Distributes points in an interval according to an
C                         arbitrary shape function
C        FD12K            Calculates derivatives by finite differencing
C        CHORDS2D         Computes the cumulative chord lengths of a curve
C        LCSFIT           Interpolates x and y to the redistributed arc
C                         lengths along the parameterized curve
C        SMOOTH1D_NITERS  Explicit smoothing utility with iteration control
C
C
C     Error Handling:
C
C        See IER description below.  It is the user's responsibility
C     to check IER on return from CURVDIS.  Error messages are sent to |LUNOUT|.
C
C
C     Environment:
C        FORTRAN 77 + minor extensions (originally)
C        Fortran 90 (now)
C
C     History:
C        08/12/88    D.A.Saunders   Initial design.
C        09/09/88    B.A.Nishida    Initial implementation.
C        06/05/89    DAS            Refined the description a little.
C        02/15/96     "             Cubic interpolation rather than linear.
C        12/01/10    DAS, ERC, Inc. Inserted explicit smoothing of the shape
C                                   function, as suggested by the defining
C                                   section of a sphere/cone capsule forebody.
C        12/03/10     "    "        Index-based smoothing of the redistributed
C                                   arc-lengths helps for cases with extreme
C                                   jumps in curvature, such as a sphere/cone.
C                                   New argument ISMOOTH allows suppression of
C                                   either or both smoothings.
C                                   The work-space is no longer an argument, as
C                                   an automatic array is now preferable.
C        12/06/10     "    "        Option to return only the redistributed arc-
C                                   length distribution (as X(1:N)), as is more
C                                   convenient for the HEAT_SHIELD program.
C        08/01/12     "    "        Very large grids can mean the original limit
C                                   of 30 smoothing iterations may not be enough
C                                   yet n/8 may still be too many.  Compromise
C                                   by using n/10 with a limit of 100.
C        10/23/13     "    "        Now that CURVDIS2 has been introduced on top
C                                   of CURVDIS to normalize the data before any
C                                   curvature calculations, less smoothing seems
C                                   to be desirable.  (A loop in CURVDIS2 that
C                                   lowers the exponent by 0.1 if CURVDIS does
C                                   not converge also helps adhering to the
C                                   curvature-based shape function as much as
C                                   possible without failing.)
C        04/24/14     "    "        CURVDIS_L adapted from CURVDIS to use linear
C                                   interpolation of X/Y in order to retain the
C                                   the input curve shape precisely.  This may
C                                   be desirable when X/Y aren't geometric data
C                                   and/or are coarsely defined.
C
C     Authors:  David Saunders, Brian Nishida, Sterling Software
C               NASA Ames Research Center, Moffett Field, CA
C
C ------------------------------------------------------------------------------


      IMPLICIT NONE

C     Arguments:
C     ----------

      INTEGER, INTENT (IN)  :: NDAT       ! Number of input curve points
      REAL,    INTENT (IN)  :: XDAT(NDAT) ! X coordinates of input curve
      REAL,    INTENT (IN)  :: YDAT(NDAT) ! Y coordinates of input curve
      INTEGER, INTENT (IN)  :: N          ! Number of output curve points
      REAL,    INTENT (IN)  :: POWER      ! Exponent for spacing function;
                                          ! controls the point clustering.
                                          ! POWER must be in [0., 1.];
                                          ! 0.0 produces uniform spacing;
                                          ! 1.0 maximizes the curvature effect;
                                          ! 0.5 is suggested, but start with 1.0
                                          ! if CURVDIS2 is being employed, as is
                                          ! now recommended
      INTEGER, INTENT (IN)  :: ISMOOTH    ! 0 => no smoothing;
                                          ! 1 => smooth shape function only;
                                          ! 2 => smooth redistributed arcs only;
                                          ! 3 => perform both smoothings
      INTEGER, INTENT (IN)  :: LUNOUT     ! Logical unit for showing convergence
                                          ! history; LUNOUT < 0 suppresses it
      LOGICAL, INTENT (IN)  :: ARCS_ONLY  ! T => skip calculations of X & Y(1:N)
                                          ! but return revised arcs as X(1:N)
      REAL,    INTENT (OUT) :: X(N), Y(N) ! X & Y coordinates of output curve,
                                          ! unless ARCS_ONLY = T, in which case
                                          ! just the arc-lengths are returned as
                                          ! X(1:N)
      INTEGER, INTENT (OUT) :: IER        ! 0 => no errors;
                                          ! 1 => POWER is out of range;
                                          ! 2 => failure in ARBDIS


C------------------------------------------------------------------------------


C     Local Constants:
C     ----------------

      REAL,      PARAMETER :: ALPHA    = 1.E+0,  ! In case curvature = 0.
     >                        ONE      = 1.E+0,
     >                        HALF     = 0.5+0,
     >                        ZERO     = 0.E+0
      LOGICAL,   PARAMETER :: FALSE    = .FALSE.,
     >                        TRUE     = .TRUE.
      CHARACTER, PARAMETER :: LINEAR*1 = 'L',
     >                        NAME*11  = 'CURVDIS_L: '


C     Local Variables:
C     ----------------

      INTEGER :: I, ISMTH, LUNERR, NITERS
      REAL    :: DSQ, DSQMIN, ONEOVERN, STOTAL, XD, YD
      REAL    :: WORK(5*NDAT + 6*N)


C     Procedures:
C     -----------

      EXTERNAL :: ARBDIS, CHORDS2D, FD12K, LCSFIT, SMOOTH1D_NITERS
      EXTERNAL :: DETECT_VERTICES, VERTEX_CURVATURE


C     Execution:
C     ----------

      ISMTH  = ABS (ISMOOTH)
      LUNERR = ABS (LUNOUT)

      IF (POWER < ZERO .OR. POWER > ONE) THEN
         WRITE (LUNERR, '(/, 2A, ES12.4)')
     >      NAME, 'Bad POWER input outside [0, 1]:', POWER
         IER = 1
         GO TO 999
      END IF


C     Compute the cumulative chord lengths of the input data:

      CALL CHORDS2D (NDAT, XDAT, YDAT, FALSE, STOTAL, WORK(1))


C     Calculate the 2nd derivatives, d2x/ds2 and d2y/ds2:

      CALL FD12K (NDAT, WORK(1), XDAT, WORK(NDAT+1), WORK(2*NDAT+1),
     >            WORK(2*NDAT+1))
      CALL FD12K (NDAT, WORK(1), YDAT, WORK(NDAT+1), WORK(3*NDAT+1),
     >            WORK(3*NDAT+1))


C     Local curvature magnitudes:

      DO I = 1, NDAT
         WORK(NDAT+I) = SQRT (WORK(2*NDAT+I)**2 + WORK(3*NDAT+I)**2)
      END DO

C     Moderate the local curvatures:

      IF (POWER == HALF) THEN  ! Avoid logarithms
         DO I = 1, NDAT
            WORK(NDAT+I) = ONE / SQRT (WORK(NDAT+I) + ALPHA)
         END DO
      ELSE
         DO I = 1, NDAT
            WORK(NDAT+I) = (WORK(NDAT+I) + ALPHA)**(-POWER)
         END DO
      END IF

CCCC  write (50, '(a)') '# Unsmoothed shape function'
CCCC  write (50, '(2es14.6)') (work(i), work(ndat+i), i = 1, ndat)

      IF (ISMTH == 1 .OR. ISMTH == 3) THEN

C        Smooth the shape function further with an explicit method:

CCCC     NITERS = MAX (5, MIN (NDAT/10, 30))
         NITERS = MAX (4, MIN (NDAT/40, 15))
CCCC     write (*, '(a, i5)') 'NITERS for shape function:', NITERS

         CALL SMOOTH1D_NITERS (NITERS, 1, NDAT, WORK(1), WORK(NDAT+1))

CCCC     write (51, '(a)') '# smoothed shape function'
CCCC     write (51, '(2es14.6)') (work(i), work(ndat+i), i = 1, ndat)

      END IF

C     Redistribute the arc lengths based on the shape function:

      STOTAL = WORK(NDAT)

      CALL ARBDIS (N, ZERO, STOTAL, NDAT, WORK(1), WORK(NDAT+1), 'A',
     >             LUNOUT, WORK(2*NDAT+N+1), WORK(2*NDAT+1), IER)

      IF (IER /= 0) THEN
         WRITE (LUNERR, '(/, 2A, I4)') NAME, 'ARBDIS IER:', IER
         IER = 2
         GO TO 999
      END IF

      IF (ISMTH >= 2) THEN  ! Smooth the redistributed arc-lengths

         ONEOVERN = ONE / REAL (N)  ! Index-based abscissas in ARBDIS workspace
         DO I = 1, N
            WORK(2*NDAT+N+I) = REAL (I) * ONEOVERN
         END DO

CCCC     NITERS = MAX (5, MIN (N/10, 30))
         NITERS = MAX (5, MIN (N/20, 20))
CCCC     write (*, '(a, i5)') 'NITERS for redistributed arc lengths:',
CCCC >      NITERS

CCCC     write (52, '(a)') '# Unsmoothed redistributed arc lengths'
CCCC     write (52, '(2es14.6)')
CCCC >      (work(2*ndat+n+i), work(2*ndat+i), i = 1, n)

         CALL SMOOTH1D_NITERS (NITERS, 1, N, WORK(2*NDAT+N+1),
     >                         WORK(2*NDAT+1))
CCCC     write (53, '(a)') '# smoothed redistributed arc lengths'
CCCC     write (53, '(2es14.6)')
CCCC >      (work(2*ndat+n+i), work(2*ndat+i), i = 1, n)

      END IF

C     Redistribute the curve coordinates, unless only revised arcs are wanted:

      IF (ARCS_ONLY) THEN
         X(1:N) = WORK(2*NDAT+1:2*NDAT+N)
      ELSE

         CALL LCSFIT (NDAT, WORK(1), XDAT, TRUE, LINEAR, N,
     >                WORK(2*NDAT+1), X, WORK(2*NDAT+1+N))  ! Unused derivatives

         CALL LCSFIT (NDAT, WORK(1), YDAT, TRUE, LINEAR, N,
     >                WORK(2*NDAT+1), Y, WORK(2*NDAT+1+N))  !    "     "
      END IF


C     Error handling:
C     ---------------

  999 RETURN

      END SUBROUTINE CURVDIS_L
