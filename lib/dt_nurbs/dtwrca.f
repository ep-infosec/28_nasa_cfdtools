      SUBROUTINE DTWRCA (DTRCF,IUNIT,CARY,ICARY,ISIZE,IERR)
C***********************************************************************
C
C FUNCTION-
C          WRITE DTRC FORMAT C-ARRAY SPLINE DATA TO A FILE
C          SPECIFIED BY THE USER.
C
C AUTHORS-
C          C.P.CHI             CREATION  SEPTEMBER 1989
C
C INPUT-
C         DTRCF  = FILE NAME FOR DTRC DATA FILE
C         IUNIT  = UNIT NUMBER FOR DTRC DATA FILE
C         CARY   = C-ARRAY CONTAINING DTRC FORMAT B-SPLINE DATA
C         ICARY  = DIMENSION OF C-ARRAY
C OUTPUT-
C         ISIZE  = NUMBER OF EFFECTIVE DATA IN C-ARRAY
C         IERR   = ERROR FLAG
C                = 0   NO ERROR DETECTED
C                = -1  MORE THAN 2 INDEPENDENT VARIABLES
C                = -2  NOT USED CURRNETLY
C                = -3  LENGTH IS GREATER THAN THE SPECIFIED
C                      SIZE OF THE C-ARRAY
C
C REFERENCES-
C          1.
C
C NOTES- INGNORE IERR= -2 ...NOT REQUIRED (RMA)
C
C TYPE/PARAMETER/DIMENSION/COMMON/EQUIVALENCE/DATA/FORMAT STATEMENTS-
C
      CHARACTER*(*) DTRCF
      CHARACTER CFMT*1,FMT*18
      DOUBLE PRECISION CARY(ICARY)
C
C
C ********************** START OF EXECUTABLE CODE **********************
C
      IERR=0
      NOBJ=0
      NLNS=0
      NOBJ=NOBJ+1
C
C...OPEN DTRC FILE (OUTPUT TO THIS ROUTINE)
C
      OPEN(UNIT=IUNIT,FILE=DTRCF,FORM='FORMATTED',STATUS='UNKNOWN')
C
C...ANALYSIZE C-ARRAY
C
C...NO OF INDEPENDENT VARIABLES
C
      NPV =INT(CARY(1))
C
      IF(NPV.LT.1.OR.NPV.GT.2) THEN
        IERR=-1
        GOTO 999
      ENDIF
C
C...NO OF DEPENDENT VARIABLE AND PHYSICAL DIMENSION
C
C      IF(CARY(2).GT.3.OR.CARY(2).LT.-4) THEN
C        IERR=-2
C        GOTO 999
C      ENDIF
C
      IF(CARY(2).GT.0.0) THEN
        IPHY=INT(CARY(2))
        NDIM=IPHY
      ELSEIF (CARY(2).LT.0.0) THEN
        IPHY=INT(ABS(CARY(2)))-1
        NDIM=IPHY+1
      ENDIF
C
C...OBJECT IS A SURFACE
C
      IF(NPV.EQ.2) THEN
C
C...NO OF CONTROL POINT IN T AND S
C
        NLNS=INT(CARY(5))
        NPTS=INT(CARY(6))
C
        NCTRP=NLNS*NPTS
C
C...DEGREE IN T AND S
C
        NDEGL=INT(CARY(3))-1
        NDEGP=INT(CARY(4))-1
C
C...NO OF KNOTS FOR T AND S KNOT VECTORS
C
        NKT=NDEGL+NLNS+1
        NKS=NDEGP+NPTS+1
C
C...CHECK ARRAY SIZE FOR C-ARRAY
C
        ISIZE=(NLNS*NPTS)*NDIM+NKS+NKT+8
C
        IF(ISIZE.GT.ICARY) THEN
          IERR=-3
          GOTO 999
        ENDIF
C
C...OBJECT IS A CURVE
C
      ELSEIF (NLNS.EQ.0) THEN
C
C...NO OF CONTROL POINT IN S
C
        NPTS=INT(CARY(4))
C
C...DEGREE IN S
C
        NDEGL=0
        NDEGP=INT(CARY(3))-1
C
C...NO OF KNOTS FOR S KNOT VECTORS
C
        NKT=0
        NKS=NDEGP+NPTS+1
C
C...CHECK ARRAY SIZE FOR C-ARRAY
C
        ISIZE=NPTS*NDIM+NKS+5
C
        IF(ISIZE.GT.ICARY) THEN
          IERR=-3
          GOTO 999
        ENDIF
      ENDIF
C
C...WRITE C-ARRAY TO A FILE
C
      WRITE(IUNIT,*) (CARY(I),I=1,ISIZE)
C
  999 CONTINUE
      CLOSE(UNIT=IUNIT)
      RETURN
      END
