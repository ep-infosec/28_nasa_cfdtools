      SUBROUTINE DTSCRC (NDIM, CTR, NORM, START, END, 
     1                   WORK, NWORK, C, IER)
C
C     GENERATE A CIRCULAR ARC IN B-SPLINE FORM.  THE GENERATED CIRCLE
C     IS ORIENTED RIGHT-HANDED (IE., COUNTER CLOCKWISE FROM START TO
C     END WHEN LOOKING AT THE CIRCLE WITH THE NORMAL POINTING TOWARD 
C     THE VIEWER).
C
C
C     USAGE
C
C         DOUBLE PRECISION CTR(NDIM), NORM(3), START(NDIM)
C         DOUBLE PRECISION END(NDIM), C(NC)
C         CALL DTSCRC (NDIM, CTR, NORM, START, END, 
C        X             WORK, NWORK, C, IER)
C
C         WHERE NC >= 53.
C
C
C     INPUT
C
C         NDIM    THE DIMENSION OF THE CIRCLE.  NDIM = 2 (PLANAR) OR
C                 NDIM = 3 (3-SPACE).
C
C         CTR     THE COORDINATES OF THE CENTER OF THE CIRCLE.
C
C         NORM    THE NORMAL VECTOR TO THE CIRCLE.  REQUIRED TO 
C                 DETERMINE THE ORIENTATION OF THE CIRCLE.
C
C         START   THE STARTING POINT OF THE CIRCULAR ARC.
C
C         END     THE ENDING POINT OF THE CIRCULAR ARC.
C
C                 NOTE:  IF START = END, THE ENTIRE CIRCLE WILL BE
C                        RETURNED.
C
C
C     WORKING STORAGE
C
C         WORK    WORK ARRAY OF LENGTH NWORK.
C
C         NWORK   LENGTH OF ARRAY WORK;
C                 NWORK >= 273
C                      
C
C     OUTPUT
C
C         C       THE SPLINE ARRAY.
C
C         IER     SUCCESS/ERROR CODE.
C                 FOR IER < 0, DTSCRC HAS SET C(1) = -1.
C
C                 IER =  0    NO ERRORS DETECTED.
C
C                 IER = -1    NDIM < 2 OR NDIM > 3.
C
C                 IER = -2    CTR, START AND END DO NOT LIE ON THE
C                             PLANE INDICATED BY THE NORMAL (NORM).
C
C                 IER = -3    NORM(I) = 0 FOR ALL I, I=1..NDIM.
C
C                 IER = -4    RADIUS (DISTANCE FROM CTR TO START) = 0.
C
C                 IER = -5    INCONSISTENT RADIUS (IE., DISTANCE FROM
C                             CTR TO START .NE. DISTANCE FROM CTR TO
C                             END).
C
C                 IER = -6    INSUFFICIENT WORKING STORAGE.
C
C
      DOUBLE PRECISION ZERO, ONE, NEG1
      PARAMETER (ZERO=0.0D0, ONE=1.0D0, NEG1=-1.0D0)
C
      EXTERNAL DTMCON, DTSTRM, DDOT
      INTEGER I, NDIM, NWORK, IER
      INTEGER IP, IX, IY, IZ, IW, NEED
      DOUBLE PRECISION NORM(*), CTR(*), START(*), END(*), C(*)
      DOUBLE PRECISION WORK(*)
      DOUBLE PRECISION LNORM, XAXIS(3), YAXIS(3), ZAXIS(3)
      DOUBLE PRECISION EPS, RADE, HOLD(4), RCOND
      DOUBLE PRECISION EPARM(2), RADIUS, V(3)
      DOUBLE PRECISION XEND, YEND, TANTH, PARM, CIRC(44), TEMP
      DOUBLE PRECISION DTMCON, DDOT
      LOGICAL XBIGR
      CHARACTER*8 SUBNAM
C
      DATA SUBNAM /'DTSCRC  '/
C     INITIALIZE CIRC TO REPRESENT THE UNIT CIRCLE IN THE PLANE
      DATA CIRC /ONE, -3.0D0, 3.0D0, 9.0D0, 3.0D0,
     +    3*ZERO, 2*0.25D0, 2*0.5D0, 2*0.75D0, 3*ONE,
     +     ONE,  ONE, ZERO, NEG1, NEG1, NEG1, ZERO,  ONE,  ONE,
     +    ZERO,  ONE,  ONE,  ONE, ZERO, NEG1, NEG1, NEG1, ZERO,
     +    9*ONE/
C     1ST LINE - 5 MAIN PARAMETERS
C     2ND LINE - 12 KNOTS (DOUBLE KNOT EVERY QUARTER CIRCLE)
C     3RD LINE - 9 X CONTROL VALUES
C     4TH LINE - 9 Y CONTROL VALUES
C     5TH LINE - 9 WEIGHTS (FOR DENOMINATOR)
C     THE 2,4,6,8TH ELEMENTS OF LINES 3,4,5 NEED TO BE MULTIPLIED BY 
C     SQRT(.5) TO BE CORRECT.  CANNOT GET THIS VALUE IN PORTABLE FORM
C     WITH MAXIMUM ACCURACY AS A PARAMETER, SO DO IT AT RUN TIME.
C
      EPS = SQRT(DTMCON(5))
      IF (CIRC(19).EQ.ONE) THEN
        TEMP = SQRT(0.5D0)
        DO 2 I=17,35,9
          DO 1 IP=2,8,2
            CIRC(I+IP) = CIRC(I+IP)*TEMP
    1     CONTINUE
    2   CONTINUE
      END IF
C
C     ERROR CHECKING
C
      IER = 0
      IF ((NDIM .LT. 2) .OR. (NDIM .GT. 3)) THEN
          IER = -1
          GOTO 9900
      ENDIF
C
      LNORM = SQRT(NORM(1)**2 + NORM(2)**2 + NORM(3)**2)
      IF (LNORM .LE. EPS) THEN
          IER = -3
          GOTO 9900
      ENDIF
C
      IF (NDIM .EQ. 2) THEN
          RADIUS = SQRT((START(1)-CTR(1))**2 + (START(2)-CTR(2))**2)
      ELSE
          RADIUS = SQRT((START(1)-CTR(1))**2 + (START(2)-CTR(2))**2
     1                + (START(3)-CTR(3))**2)
      ENDIF
      IF (RADIUS .LE. EPS) THEN
          IER = -4
          GOTO 9900
      ENDIF
C
      IF (NDIM .EQ. 2) THEN
          RADE = SQRT((END(1)-CTR(1))**2 + (END(2)-CTR(2))**2)
      ELSE
          RADE = SQRT((END(1)-CTR(1))**2 + (END(2)-CTR(2))**2
     1              + (END(3)-CTR(3))**2)
      ENDIF
      IF (ABS(RADIUS-RADE) .GT. EPS) THEN
          IER = -5
          GOTO 9900
      ENDIF
C
C     CHECK THE WORKING STORAGE
C
      NEED   = 273
      IF ( NWORK .LT. NEED ) THEN
          IER     = -6
          GOTO 9900
      END IF
C
C     LOCATE PLANE OF DESIRED CIRCLE
C       THIS PLANE IS CONSTRUCTED TO BE THE PLANE CONTAINING THE CENTER AND
C       START POINT WHICH IS PERPENDICULAR TO THE PLANE CONTAINING CENTER,
C       START AND NORMAL VECTOR.  THE END POINT IS NOT USED BECAUSE IT WILL
C       OFTEN BE COLLINEAR WITH CENTER AND START (WHOLE AND SEMI-CIRCLES).
C
      DO 10 I = 1, 3
          ZAXIS(I) = NORM(I) / LNORM
   10 CONTINUE
      XAXIS(3) = 0.0
      DO 20 I = 1, NDIM
          XAXIS(I) = (START(I)-CTR(I)) / RADIUS
   20 CONTINUE
      YAXIS(1) = ZAXIS(2)*XAXIS(3) - ZAXIS(3)*XAXIS(2)
      YAXIS(2) = ZAXIS(3)*XAXIS(1) - ZAXIS(1)*XAXIS(3)
      YAXIS(3) = ZAXIS(1)*XAXIS(2) - ZAXIS(2)*XAXIS(1)                
C
C     LOCATE END POINT IN PLANE OF DESIRED CIRCLE IN TERMS OF COORDINATE
C     AXES XAXIS AND YAXIS
C
      V(3) = ZERO
      DO 30 I = 1, NDIM
          V(I) = END(I) - CTR(I)
   30 CONTINUE
      XEND = DDOT (3, XAXIS, 1, V, 1)
      YEND = DDOT (3, YAXIS, 1, V, 1)
C
C     CHECK THAT END POINT LIES ON THE EXPECTED PLANE
C
      DO 40 I = 1, 3
          IF (ABS(XEND*XAXIS(I)+YEND*YAXIS(I)-V(I)) .GT. EPS) THEN
              IER = -2
              GOTO 9900
          ENDIF
   40 CONTINUE
C
C     FIND THE PARAMETER CORRESPONDING TO THE END POINT
C
C     FIND TAN(THETA), WHERE THETA IS ANGLE BETWEEN END RADIUS AND 
C     NEAREST AXIS.  THIS ENSURES TANTH BETWEEN ZERO AND ONE AND AVOIDS
C     AN OCCASIONAL DIVIDE BY ZERO.
      XBIGR = ABS(XEND) .GE. ABS(YEND)
      IF (XBIGR) THEN
        TANTH = ABS( YEND/XEND)
      ELSE
        TANTH = ABS( XEND/YEND)
      END IF
      IF (TANTH .NE. ZERO) THEN
        TEMP = SQRT(2.0D0)
        PARM = ((2.0D0+TEMP)*(ONE+TANTH)/(SQRT(ONE+TANTH*TANTH)+TEMP)
     +      - TEMP)*0.125D0
C       THIS EXPRESSION FOR PARAMETER VALUE AS A FUNCTION OF TAN(THETA)
C       IS GOOD FOR 0 <= THETA <= 45 DEGREES.  IT WAS FOUND BY DIRECT
C       SOLUTION OF THE RATIONAL POLYNOMIAL EXPRESSION USED TO PARAME-
C       TRIZE THE FIRST QUARTER CIRCLE.  THIS SOLUTION WAS THEN ALGE-
C       BRAICALLY MANIPULATED TO ELIMINATE A COMPUTATIONAL SINGULARITY
C       (ZERO/ZERO) AT TAN(THETA)=1.
      ELSE
        PARM = ZERO
C       FORMULA WOULD WORK FOR ZERO, TOO, BUT WHY RISK ROUND-OFF ERROR
      END IF
C     NOW USE ALL THE SYMMETRY OF THE PARAMETRIZATION TO EXTEND THE
C     CALCULATION TO THE WHOLE CIRCLE
      IF (XBIGR) THEN
        IF (XEND.GT.ZERO) THEN
          IF (YEND.GT.ZERO) THEN
            CONTINUE
C           0 < THETA <= 45 DEGREES
          ELSE
            PARM = ONE - PARM
C           315 <= THETA <= 360 DEGREES (0 DEGREES IS USELESS ARC)
          END IF
        ELSE
          IF (YEND.GT.ZERO) THEN
            PARM = 0.5D0 - PARM
C           135 <= THETA < 180 DEGREES
          ELSE
            PARM = 0.5D0 + PARM
C           180 <= THETA <= 225 DEGREES
          END IF
        END IF
      ELSE
        IF (YEND.GT.ZERO) THEN
          IF (XEND.GT.ZERO) THEN
            PARM = 0.25D0 - PARM
C           45 < THETA < 90 DEGREES
          ELSE
            PARM = 0.25D0 + PARM
C           90 <= THETA < 135 DEGREES
          END IF
        ELSE
          IF (XEND.LT.ZERO) THEN
            PARM = 0.75D0 - PARM
C           225 < THETA < 270 DEGREES
          ELSE
            PARM = 0.75D0 + PARM
C           270 <= THETA < 315 DEGREES
          END IF
        END IF
      END IF
C
C     TRIM THE SPLINE TO THE REQUESTED ARC
C
      EPARM(1) = ZERO
      EPARM(2) = PARM
      CALL DTERPT(0)
      CALL DTSTRM (CIRC, EPARM, 1, WORK(45), 229, WORK(1), IER)
      CALL DTERPT(1)
      IF (IER .NE. 0) THEN
          IER = -10
          GOTO 9900
      ENDIF
C
C     CREATE THE NEW C ARRAY FROM THE TRIMMED OUTPUT BY SCALING,
C     ROTATING AND TRANSLATING.
C
C     FIRST, COPY THE SPLINE ARRAY THROUGH THE KNOTS
C
      IP = 5+WORK(3)+WORK(4)
      DO 50 I = 1, IP
          C(I) = WORK(I)
   50 CONTINUE
      IF (NDIM .EQ. 3) C(2) = -4.0
C
C     GENERATE THE NEW CIRCLE COEFFICIENTS
C
      IX = IP+1
      IP = C(4)
      IY = IX+IP
      IZ = IY+IP
      IW = IZ+IP
      DO 60 I = 1, IP
          WORK(IX) = WORK(IX) * RADIUS
          WORK(IY) = WORK(IY) * RADIUS
          C(IX) = WORK(IX)*XAXIS(1)+WORK(IY)*YAXIS(1)+WORK(IZ)*CTR(1)
          C(IY) = WORK(IX)*XAXIS(2)+WORK(IY)*YAXIS(2)+WORK(IZ)*CTR(2)
          IF (NDIM .EQ. 3) THEN
              C(IZ) = WORK(IX)*XAXIS(3)+WORK(IY)*YAXIS(3)+
     *                WORK(IZ)*CTR(3)
              C(IW) = WORK(IZ)
          ELSE
              C(IZ) = WORK(IZ)
          ENDIF
          IX = IX+1
          IY = IY+1
          IZ = IZ+1
          IW = IW+1
   60 CONTINUE
 9900 IF (IER .LT. 0) THEN
          C(1) = -1.0
          IF (IER .EQ. -6) THEN
              CALL DTERR (2, SUBNAM, IER, NEED)
          ELSE
              CALL DTERR (1, SUBNAM, IER, 0)
          ENDIF
      ENDIF
      RETURN
      END