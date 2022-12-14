C***** DTPLAR *****
C   COMPUTE AREA BOUNDED BY CLOSED PLANAR CURVE.
C
C   INPUT:
C     C       SPLINE ARRAY FOR THE CLOSED PLANAR CURVE.
C   WORKSPACE:
C     WORK    WORK ARRAY OF LENGTH AT LEAST NWORK.
C     NWORK   LENGTH OF WORK ARRAY.  IT IS SUFFICIENT FOR 
C             NWORK >= C(3)*C(3) + 5.0*C(3).
C   OUTPUT:
C     AREA    THE AREA BOUNDED BY THE CURVE C.
C     IER     ERROR FLAG.  ZERO RETURNED IN AREA IF IER < 0.
C
C   CALLS:
C     DTERR
C     DTGET
C     DTMCON
C     DTQUAD
C     DTSPVL
C   USES FUNCTION DTPLA1 AS ARGUMENT TO DTQUAD
C*****
      SUBROUTINE DTPLAR (C, WORK, NWORK, AREA, IER)
      INTEGER NWORK, IER
      DOUBLE PRECISION C(*), WORK(NWORK), AREA
C
C   LOCAL VARIABLES
      DOUBLE PRECISION A, B, AA, BB, DTPLA1, AREA1, TOL, ERR, 
     +    VA(3), VB(3), ONEMEP
      INTEGER N, M, K, NCOEF, ISNG, LIMIT, LEVEL, JER
      CHARACTER*8 SUBNAM
C
      DOUBLE PRECISION DTMCON
      EXTERNAL DTPLA1
C
      DATA ISNG, LIMIT, TOL /0,12,1.E-4/
      DATA SUBNAM /'DTPLAR'/
C
C   INITIALIZE AND GET SPLINE PARAMETERS
      ONEMEP = 1.0D0 - DTMCON(6)
      JER = 0
      AREA = 0.0D0
      CALL DTGET (C, .TRUE., 1, N, MRAW, M, K, NCOEF, A, B, IER)
      IF (IER .NE. 0) GO TO 9900
      IF (N .NE. 1) GO TO 9001
      IF (M .NE. 2) GO TO 9002
      IF (NWORK .LT. K*(K+5)) GO TO 9006
C
C   VERIFY CURVE IS CLOSED
      CALL DTSPVL (A, C, WORK, NWORK, VA, IER)
      IF (IER.NE.0) GO TO 9099
      CALL DTSPVL (B, C, WORK, NWORK, VB, IER)
      IF (IER.NE.0) GO TO 9099
      IF (DABS( VA(1)-VB(1) ) .GT. TOL .OR.
     +    DABS( VA(2)-VB(2) ) .GT. TOL) GO TO 9007
C
C   FIND AND INTEGRATE SMOOTH PIECES OF CURVE
      AA = A
      DO 30 I=6+K,5+NCOEF
        IF (C(I+K-2) .LE. C(I) .AND. C(I) .GT. AA) THEN
          BB = ONEMEP*C(I)
          CALL DTQUAD (DTPLA1, C, AA, BB, TOL, ISNG, LIMIT, AREA1,
     +      LEVEL, WORK, NWORK, ERR, IER)
          AREA = AREA + AREA1
          IF (IER .LT. 0) GO TO 9099
          IF (IER .GT. 0) THEN
            IF (JER .EQ. 0) THEN
              JER = IER
            ELSE
              JER = 3
            END IF
          END IF
          AA = C(I)
        END IF
  30  CONTINUE
C
C     INTEGRATE LAST SMOOTH PIECE OF CURVE (IF NOT TRIVIAL)
      IF (B .GT. AA) THEN
        CALL DTQUAD (DTPLA1, C, AA, B, TOL, ISNG, LIMIT, AREA1,
     +      LEVEL, WORK, NWORK, ERR, IER)
        AREA = AREA + AREA1
        IF (IER .LT. 0) GO TO 9099
        IF (IER .GT. 0) THEN
          IF (JER .EQ. 0) THEN
            JER = IER
          ELSE
            JER = 3
          END IF
        END IF
      END IF
C     RECOVER ACCURACY WARNING NUMBER, IF ANY, AND EXIT
      IF (IER .GE. 0 .AND. JER .NE. 0) IER = JER
      IF (IER .GT. 0) CALL DTERR (0, SUBNAM, IER, 0)
      RETURN
C
C   ERROR EXITS
C   NOT A CURVE
 9001 IER = -1
      GO TO 9900
C   NOT PLANAR
 9002 IER = -2
      GO TO 9900
C   NOT ENOUGH WORKSPACE
 9006 IER = -6
      CALL DTERR (2, SUBNAM, IER, K*(K+5))
      GO TO 9990
C   NOT CLOSED
 9007 IER = -7
      GO TO 9900
C   ERROR DETECTED IN CALLED SUBROUTINE
 9099 IER = -99
      CALL DTERR (4, SUBNAM, IER, 0)
      GO TO 9990
C   COMMON ERROR MESSAGE
 9900 CONTINUE
      CALL DTERR (1, SUBNAM, IER, 0)
 9990 CONTINUE
      AREA = DTMCON(1)
      RETURN
      END
C
C
C***** DTPLA1 *****
C   INTEGRAND FUNCTION FOR DTPLAR - USED AS ARGUMENT TO DTQUAD
C
C   CALLS:
C     DTSPDR
C*****
      DOUBLE PRECISION FUNCTION DTPLA1 (X, CC, WORK, NWORK)
C
      INTEGER NWORK
      DOUBLE PRECISION X, CC(*), WORK(NWORK)
C
      DOUBLE PRECISION V(3,2)
C
C   COMPUTE COORDINATES AND FIRST DERIVATIVES OF PLANAR CURVE AT X
      CALL DTSPDR (X, 1, CC, WORK, NWORK, V, 3, IER)
C   FUNCTION IS FIRST COORDINATE TIMES DERIVATIVE OF SECOND
      IF (IER .EQ. 0) THEN
        DTPLA1 = V(1,1) * V(2,2)
      ELSE
C       DTQUAD MAKES NO PROVISION FOR PASSING ERROR CODES BACK
        DTPLA1 = 0.0D0
      END IF
      RETURN
      END
