C***** DTMIRI *****
C**********************************************************************
      SUBROUTINE DTMIRI (C,ICARY,AX,BY,CZ,DD,CI,IER)
C***********************************************************************
C
C FUNCTION-
C          GENERATE THE MIRROR IMAGE OF A SPLINE SURFACE WITH RESPECT TO
C          A REFERENCE PLANE
C
C AUTHORS-
C          C.P.CHI             CREATION  OCTOBER 1989
C          P.G.KRAUSHAR        CORRECTED JANUARY 1990
C
C INPUT-
C         C      = DTRC SPLINE ARRAY FOR A SURFACE
C         ICARY  = SIZE OF THE SPLINE ARRAYS
C         AX     = COEFFICIENT OF THE REFERENCE PLANE
C         BY     = COEFFICIENT OF THE REFERENCE PLANE
C         CZ     = COEFFICIENT OF THE REFERENCE PLANE
C         DD     = CONSTANT OF THE REFERENCE PLANE
C OUTPUT-
C         CI     = ARRAY CONTAINING THE SPLINE FOR THE MIRROR IMAGE
C                  OF THE INPUT SURFACE
C         IER     = ERROR FLAG
C                 = 0  NO ERROR DETECTED
C                 = -1 INPUT SPLINE ARRAY IS NOT FOR A SURFACE
C                 = -2 INCORRECT NUMBER OF DIMENSION
C                      SECOND ELEMENT OF C-ARRAY GREATER THAN 3 OR
C                      LESS THAN -4 OR EQUAL TO ZERO
C                 = -3 SIZE OF SPLINE ARRAY TOO SMALL
C
C REFERENCES-
C          1.
C
C NOTES-
C
C TYPE/PARAMETER/DIMENSION/COMMON/EQUIVALENCE/DATA/FORMAT STATEMENTS-
C
      DOUBLE PRECISION C(ICARY), CI(ICARY)
      DOUBLE PRECISION AX,BY,CZ,DD
C
      DOUBLE PRECISION VECTL, AXN, BYN, CZN, DDN, DIS
      INTEGER IX0, IY0, IZ0, ID0
C
C ********************** START OF EXECUTABLE CODE **********************
C
      IER=0
      NLNS=0
C ***
C...CHECK AND ANALYSIS SPLINE DATA FOR A SURFACE
C ***
C
C...NO OF INDEPENDENT VARIABLES
C
      NPV =DINT(C(1))
C
      IF(NPV.NE.2) THEN
        IER=-1
        GOTO 999
      ENDIF
C
      IH = NPV*3+2
C
C...NO OF DEPENDENT VARIABLE AND PHYSICAL DIMENSION
C
      IF(C(2).GT.0.0) THEN
        IPHY=DINT(C(2))
        NDIM=IPHY
      ELSEIF (C(2).LT.0.0) THEN
        IPHY=DINT(ABS(C(2)))-1
        NDIM=IPHY+1
      ENDIF
C
      IF (IPHY.NE.3) THEN
        IER=-2
        GOTO 999
      ENDIF
C
C...OBJECT SHALL BE A SURFACE
C
C...NO OF CONTROL POINT IN T AND S
C
        NLNS=DINT(C(5))
        NPTS=DINT(C(6))
C
        NCTRP=NLNS*NPTS
C
C...DEGREE IN T AND S
C
        NDEGL=DINT(C(3))-1
        NDEGP=DINT(C(4))-1
C
C...NO OF KNOTS FOR T AND S KNOT VECTORS
C
        NKT=NDEGL+NLNS+1
        NKS=NDEGP+NPTS+1
C
C...COMPUTE ARRAY SIZE
C
        ISIZE=(NLNS*NPTS)*NDIM+NKS+NKT+8
        IF(ISIZE.GT.ICARY) THEN
          IER=-3
          GOTO 999
        ENDIF
C ***
C...END OF DATA ANALYSIS
C ***
C
C...COMPUTE UNIT NORMAL VECTOR COMPONENTS OF THE REFERENCE PLANE
C
      VECTL = DSQRT(AX**2+BY**2+CZ**2)
      IF (VECTL .EQ. 0.0D0) THEN
        IER = -7
        GO TO 999
      END IF
      AXN = AX/VECTL
      BYN = BY/VECTL
      CZN = CZ/VECTL
      DDN = DD/VECTL
C
C...LOCATE X, Y, Z, COEFFICENTS (AND DENOMINATOR, IF RATIONAL)
C
      IX0 = IH + NKT + NKS
      IY0 = IX0 + NCTRP
      IZ0 = IY0 + NCTRP
      ID0 = IZ0 + NCTRP
C
C...COPY THE FIRST PART OF THE C ARRAY UNCHANGED
C
      DO 100 I=1,IX0
        CI(I) = C(I)
  100 CONTINUE
C
C...MOVE TO OPPOSITE SIDE OF MIRROR PLANE
C
      DO 300 I=1,NCTRP
        DIS = AXN*C(IX0+I) + BYN*C(IY0+I) + CZN*C(IZ0+I)
        IF (NDIM .NE. IPHY) THEN
C         RATIONAL SPLINE CASE
          DIS = 2.0D0*(DIS + DDN*C(ID0+I))
          CI(ID0+I) = C(ID0+I)
        ELSE
C         POLYNOMIAL SPLINE CASE
          DIS = 2.0D0*(DIS + DDN)
        END IF
        CI(IX0+I) = C(IX0+I) - DIS*AXN
        CI(IY0+I) = C(IY0+I) - DIS*BYN
        CI(IZ0+I) = C(IZ0+I) - DIS*CZN
  300 CONTINUE
C
  999 CONTINUE
      RETURN
      END