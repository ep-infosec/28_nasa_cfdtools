      SUBROUTINE DTLSSL (A, NDIM, N, M, B, RSD, HOLD, NHOLD, RPERT, IER)
         INTEGER NDIM, N, M, NHOLD, IER
         DOUBLE PRECISION    A(NDIM,*), B(*), RSD(*), RPERT, HOLD(*)
C
C*********************************************************************
C
C PURPOSE   DTLSSL SOLVES AX=B FOR X WHERE A IS AN N BY M DOUBLE
C           PRECISION GENERAL MATRIX WITH M LESS THAN N. DTLSSL IS AN
C           COMPANION ROUTINE TO DTLSLE FOR USE WHEN SEVERAL SYSTEMS
C           OF EQUATIONS WITH THE SAME COEFFICIENT MATRIX A, BUT
C           DIFFERENT RIGHT HAND SIDES ARE TO BE SOLVED. DTLSLE IS
C           USED TO SOLVE THE FIRST SUCH SYSTEM.  DTLSSL CAN THEN
C           SOLVE EACH OF THE REMAINING SYSTEMS WITH MUCH LESS
C           COST.
C
C METHOD    THE LINPACK SUBROUTINE DQRSL IS CALLED TO COMPUTE THE
C           SOLUTION X. AN ESTIMATE OF THE CONDITIONUNG OF THE PROBLEM
C           IS RETRUNED IN RPERT.
C
C USAGE     DOUBLE PRECISION  A(NDIM,M), B(N), RSD(N)
C           REAL HOLD(NHOLD)
C           CALL DTLSLE (A, NDIM, N, M, B, RSD, HOLD, NHOLD, RPERT, IER)
C                " COMPUTE A NEW RIGHT HAND SIDE IN B"
C           CALL DTLSSL (A, NDIM, N, M, B, RSD, HOLD, NHOLD, RPERT, IER)
C
C INPUT     A         DOUBLY SUBSCRIPTED ARRAY WHICH CONTAINS THE
C                     THE FACTORS OF THE MATRIX A AS COMPUTED BY
C                     DTLSLE. THIS ARRAY SHOULD NOT BE CHANGED BY
C                     THE USER BETWEEN THE CALL TO DTLSLE AND
C                     THE USE OF DTLSSL.
C
C           NDIM      ROW DIMENSION OF THE ARRAY A WHICH MUST BE
C                     AT LEAST N.  (SEE INTRODUCTION TO LINEAR
C                     ALGEBRA SECTION FOR FURTHER DETAILS)
C
C           N         NUMBER OF ROWS IN A , THE LENGTH OF THE
C                     RIGHT HAND SIDE COLUMN VECTOR B, AND
C                     THE LENGTH OF THE RESIDUAL VECTOR RSD.
C
C           M         NUMBER OF COLUMNS IN A AND THE LENGTH OF THE
C                     SOLUTION VECTOR.
C
C           B         ARRAY WHICH CONTAINS THE RIGHT HAND SIDE
C                     COLUMN VECTOR B.
C
C WORKING   HOLD      WORK VECTOR OF LENGTH NHOLD.  THIS VECTOR
C STORAGE             MUST BE THE SAME WORK VECTOR AS USED BY DTLSLE.
C                     THIS VECTOR SHOULD NOT BE CHANGED BY THE USER
C                     BETWEEN THE CALL TO DTLSLE AND THE USE OF
C                     DTLSSL. IT CONTAINS INFORMATION REGARDING THE
C                     FACTORS OF A WHICH MUST BE PRESERVED IN ORDER
C                     TO SOLVE ADDITIONAL RIGHT HAND SIDES.
C
C           NHOLD     THE LENGTH OF THE VECTOR HOLD WHICH MUST BE AT
C                     LEAST M+2  .
C
C OUTPUT    B         IF IER .GE. 0, THEN THE FIRST M ENTRIES OF B HAVE
C                     BEEN OVERWRITTEN WITH THE COMPUTED SOLUTION.
C                     OTHERWISE IT IS UNCHANGED.
C
C           RSD       IF IER .GE. 0, THEN RSD CONTAINS THE RESIDUAL
C                     VECTOR B - A * X .
C
C           RPERT     ESTIMATE OF THE CONDITIONING OF THE PROBLEM. IF
C                     RPERT IS VERY SMALL THE COMPUTED SOLUTION MAY BE
C                     VERY SENSITIVE TO PERTURBATIONS.
C
C           IER       SUCCESS/ERROR CODE WHICH COMMUNICATES TO THE
C                     USER SUCCESS, WARNINGS, OR ERRORS.
C                     IF IER .LT. 0 THEN DTLSSL SETS RSD(1) = DTMCON(1).
C                     POSSIBLE RETURN VALUES ARE
C
C                     IER =  0, NORMAL RETURN
C                         =  1, SOLUTION HAS BEEN COMPUTED BUT IS
C                               SENSITIVE TO PERTURBATIONS IN A AND B.
C                         =  2, SOLUTION HAS BEEN COMPUTED BUT IS VERY
C                               SENSITIVE TO PERTURBATIONS IN A AND B.
C                         = -1, N IS LESS THAN 1
C                         = -2, NDIM IS LESS THAN N
C                         = -3, M IS LESS THAN 1 OR M IS GREATER THAN N
C                         = -4, NHOLD IS LESS THAN M+2
C                         = -5, COLUMN RANK OF A IS LESS THAN M
C
C  WRITTEN BY HORST D. SIMON ON OCTOBER 3, 1983
C            MODIFIED 06/28/86 BY A. B. LESTER
C            TO CONFORM TO FORTRAN 77 STANDARDS.
C*********************************************************************
C
C ... EXTERNAL SUBROUTINES CALLED ARE
C
C     FORTRAN INTRINSIC
C         LOG10, DBLE
C
C     DTRC SUBROUTINES
C        DTERR, DTMCON
C
C     LINPACK SUBROUTINES AND BLAS
C        DQRSL, DASUM
C
      DOUBLE PRECISION DTMCON, DASUM
C
C ... INTERNAL VARIABLES
C
      DOUBLE PRECISION BNRM, COLMAX, DIGCAL, DIGMAX, DUM(1), RNRM, XNRM
      CHARACTER*8 SNAME
      INTEGER IBEG, IEND, INFO, NEED
C
C ... INITIALIZE THE ERROR MESSAGE ARRAYS
C
      PARAMETER (SNAME='DTLSSL')
C
C ... ALLOCATE WORKSPACE
C
      IBEG = 1
      IEND = IBEG +   M
C
C ... INITIALIZATION
C
      IER = 0
      BNRM = DASUM ( N, B, 1 )
      RPERT = HOLD(IEND)
      COLMAX = HOLD(IEND + 1)
C
C ... CHECK INPUT PARAMETERS
C
      IF ( N .GE. 1 ) GO TO 10
            IER = -1
            CALL DTERR ( 1, SNAME, IER, 1)
            GO TO 200
C
  10     IF ( NDIM .GE. N ) GO TO 20
            IER = -2
            CALL DTERR ( 1, SNAME, IER, 1)
            GO TO 200
C
  20     IF ( M .GE. 1 .AND. M .LE. N  ) GO TO 30
            IER = -3
            CALL DTERR ( 1, SNAME, IER, 1)
            GO TO 200
C
  30     IF ( NHOLD .GE. M+2 ) GO TO 40
            NEED = M+2
            IER = -4
            CALL DTERR ( 2, SNAME, IER, NEED )
            GO TO 200
C
  40     IF ( RPERT .GT. 0.0D0 .AND. COLMAX .GT. 0.0D0 ) GO TO 50
            IER = -5
            CALL DTERR ( 1, SNAME, IER, 1)
            GO TO 200
C
C ...    SOLVE THE MATRIX EQUATION
C
  50     CALL DQRSL ( A, NDIM, N, M, HOLD(IBEG), B, DUM, B, B, RSD, DUM,
     1               110, INFO )
C
C ... CHECK FOR ZERO SOLUTION
C
         XNRM = DASUM ( M, B, 1)
         IF ( XNRM .EQ. 0.0D0 ) GO TO 60
C
C ... SENSITIVITY ANALYSIS OF THE SOLUTION
C
         RNRM = DASUM ( N, RSD, 1)
         RPERT = RPERT * RPERT * COLMAX * XNRM / ( RPERT * COLMAX * XNRM
     1            + RNRM + RPERT * BNRM )
  60     CONTINUE
         IF ( RPERT .LE. 0.0D0 ) THEN
            IER = -5
            CALL DTERR ( 3, SNAME, IER, 1 )
            GO TO 200
         ENDIF
         DIGCAL = - LOG10 (RPERT)
         DIGMAX = - LOG10 (DTMCON(5))
         IF ( 3.0D0 * DIGCAL .GT.         DIGMAX ) IER = 1
         IF ( 3.0D0 * DIGCAL .GT. 2.0D0 * DIGMAX ) IER = 2
         IF ( IER .EQ. 0  ) RETURN
            CALL DTERR ( 0, SNAME, IER, 1 )
            RETURN
  200    RSD(1) = DTMCON(1)
C
C ...    END OF SUBROUTINE
C
         RETURN
         END

