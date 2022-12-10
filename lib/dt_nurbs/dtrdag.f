      SUBROUTINE DTRDAG (IUN,AGPSF,JUN,DTRCF,ICARY,CARRAY,IERR)
C***********************************************************************
C
C FUNCTION-
C          READ AGPS B-SPLINE DATA FILE GENERATED BY AGPS 'WBS'
C          COMMAND. CONVERT THE DATA AND WRITE TO A FILE AND
C          LOAD INTO THE C-ARRAY IN DTRC FORMAT.
C
C AUTHORS-
C          C.P.CHI             CREATION  JULY 17   1989
C
C INPUT-
C         IUN    = UNIT TO USE FOR INPUT FILE
C         AGPSF  = FILE NAME FOR INPUT FILE IN AGPS FORMAT
C         JUN    = UNIT TO USE FOR OUTPUT FILE
C         DTRCF  = FILE NAME FOR OUTPUT FILE IN DTRC FORMAT
C         ICARY  = DIMENSION OF C-ARRAY
C OUTPUT-
C         CARRAY = C-ARRAY CONTAINING DTRC FORMAT B-SPLINE DATA
C         IERR   = ERROR FLAG
C                = 0   NO ERROR DETECTED
C                = -1  INCORRECT PHYSICAL DIMENSION
C                      GREATER THAN 3 OR LESS THAN ONE
C                = -2  NUMBER OF DATA GREATER THAN SPECIFIED SIZE
C                      OF C-ARRAY
C                = -3  READ ERROR
C
C REFERENCES-
C          1.
C
C NOTES-
C
C TYPE/PARAMETER/DIMENSION/COMMON/EQUIVALENCE/DATA/FORMAT STATEMENTS-
C
      INTEGER MAXD
      PARAMETER (MAXD=3)
C
      CHARACTER*(*) DTRCF,AGPSF
      CHARACTER CFMT*1,FMT*18
C
      DOUBLE PRECISION PARRAY(MAXD),TKNTPT(5),TKNTLN(5)
      DOUBLE PRECISION CARRAY(ICARY)
      DOUBLE PRECISION DENOM
C
      LOGICAL DIS1, ZIS0
C
      INTEGER J, NLNS, NPTS, NDEGL, NDEGP, MKNT, MSET, IPHY, IJ
      INTEGER NKT, NKS, ISIZE, NCTRP, KP, IK, L, M, N, NT, NS, NCPT
      INTEGER NIK, NCE, IK2, NKNOTS, NLINE, KT, I, K, NK, NKNOTT
C
      DATA DIS1, ZIS0 /.TRUE., .TRUE./
C
   20 FORMAT(8I5)
   40 FORMAT(I3)
   45 FORMAT(5F12.6)
C
C ********************** START OF EXECUTABLE CODE **********************
C
C...OPEN AGPS FILE (INPUT TO THIS ROUTINE)
C
      OPEN(UNIT=IUN,FILE=AGPSF,FORM='FORMATTED',STATUS='OLD')
C
C...OPEN DTRC FILE (OUTPUT FROM THIS ROUTINE)
C
      OPEN(UNIT=JUN,FILE=DTRCF,FORM='FORMATTED',STATUS='UNKNOWN')
C
      REWIND IUN
  100 CONTINUE
C
C...READ IN AGPS DATA FILE
C
      READ(IUN,20,ERR=888,END=999)J,NLNS,NPTS,NDEGL,NDEGP,MKNT,MSET,IPHY
      IF(NDEGP.LE.0.AND.NDEGL.LE.0)GO TO 100
C     IF(IPHY.EQ.0)IPHY=3
      IF(IPHY.LT.1.OR.IPHY.GT.3) THEN
        IERR=-1
        GOTO 999
      ENDIF
      IDIM=IPHY+1
C
C...TRANSFER DATA TO THE C-ARRAY OF DTRC FORMAT
C
      IF(NLNS.GT.0)THEN
       CARRAY(1) = 2.0D0
       CARRAY(2) = - DBLE(IDIM)
       CARRAY(3) = DBLE(NDEGL+1)
       CARRAY(4) = DBLE(NDEGP+1)
       CARRAY(5) = DBLE(NLNS)
       CARRAY(6) = DBLE(NPTS)
       CARRAY(7) = 1.0D0
       CARRAY(8) = 1.0D0
        IJ   = 8
      ELSE
       CARRAY(1) = 1.0D0
       CARRAY(2) = -DBLE(IDIM)
       CARRAY(3) = DBLE(NDEGP+1)
       CARRAY(4) = DBLE(NPTS)
       CARRAY(5) = 1.0D0
        IJ   = 5
      ENDIF
C
      NKT=NDEGL+1+NLNS
      NKS=NDEGP+1+NPTS
C
C...CHECK ARRAY SIZE FOR C-ARRAY
C
      IF(NLNS.GT.0) THEN
        ISIZE=(NLNS*NPTS)*IDIM+NKS+NKT+8
      ELSE
        ISIZE=NPTS*IDIM+NKS+5
      ENDIF
C
      IF(ISIZE.GT.ICARY) THEN
        IERR=-2
        GOTO 999
      ENDIF
C
C...DEFINE FORMAT FOR READ CONTROL POINT DATA
C
      WRITE(CFMT,'(I1)') IDIM
      FMT='(1X,'//CFMT//'F12.6,3I4,I5)'
      IF(NLNS.GT.0)THEN
C
C...RBS OBJECT IS A SURFACE (NLNS>0)
C
C...READ IN CONTROL POINTS
C
        NCTRP=NLNS*NPTS
C
        KP=0
        IK=IJ+NKT+NKS
        DO 110 L=1,NLNS
        DO 110 N=1,NPTS
        READ(IUN,FMT,ERR=888) (PARRAY(M),M=1,IPHY),DENOM,J,NT,NS,NCPT
        IF (DENOM .EQ. 0.0D0) GO TO 887
        NIK = IK + (N-1)*NLNS + L
        DO 105 NCE=1,IPHY
        CARRAY(NIK)=PARRAY(NCE)*DENOM
        NIK = NIK + NCTRP
  105   CONTINUE
        CARRAY(NIK) = DENOM
        DIS1 = DIS1 .AND. (DENOM .EQ. 1.0D0)
        ZIS0 = ZIS0 .AND. (PARRAY(3) .EQ. 0.0D0)
  110   CONTINUE
C
C...READ KNOT VECTORS IN THE SECOND INDEPENDENT VARIABLE
C
        IK2=IJ+NKT
        READ(IUN,40,ERR=888)NKNOTS
        NLINE=NKNOTS/5
        IF(REAL(NKNOTS)/5.0.GT.REAL(NLINE)) NLINE=NLINE+1
        KT=0
        DO 120 I=1,NLINE
        READ(IUN,45,ERR=888) (TKNTPT(K),K=1,5)
        DO 115 NK=1,5
        KT=KT+1
        IF(KT.LE.NKNOTS) THEN
          IK2=IK2+1
          CARRAY(IK2)=TKNTPT(NK)
        ENDIF
  115   CONTINUE
  120   CONTINUE
C
C...READ KNOT VECTORS IN THE FIRST INDEPENDENT VARIABLE
C
        READ(IUN,40,ERR=888)NKNOTT
        NLINE=NKNOTT/5
        IF(REAL(NKNOTT)/5.0.GT.REAL(NLINE)) NLINE=NLINE+1
        KT=0
        DO 130 I=1,NLINE
        READ(IUN,45,ERR=888) (TKNTLN(K),K=1,5)
        DO 125 NK=1,5
        KT=KT+1
        IF(KT.LE.NKNOTT) THEN
          IJ=IJ+1
          CARRAY(IJ)=TKNTLN(NK)
        ENDIF
  125   CONTINUE
  130   CONTINUE
      ELSE
C
C...OBJECT IS ACURVE
C
C
        NCTRP = NPTS
        IK=IJ+NKS
        DO 150 KP=1,NPTS
        READ(IUN,FMT,ERR=888) (PARRAY(M),M=1,IPHY),DENOM,J,NT,NS,NCPT
        IF (DENOM .EQ. 0.0D0) GO TO 887
        NIK = IK + KP 
        DO 140 NCE=1,IPHY
        CARRAY(NIK)=PARRAY(NCE)*DENOM
        NIK = NIK + NCTRP
  140   CONTINUE
        CARRAY(NIK) = DENOM
        DIS1 = DIS1 .AND. (DENOM .EQ. 1.0D0)
        ZIS0 = ZIS0 .AND. (PARRAY(3) .EQ. 0.0D0)
  150   CONTINUE
C
C...READ KNOT VECTORS
C
        READ(IUN,40,ERR=888)NKNOTS
        NLINE=NKNOTS/5
        IF(REAL(NKNOTS)/5.0.GT.REAL(NLINE)) NLINE=NLINE+1
        KT=0
        DO 170 I=1,NLINE
        READ(IUN,45,ERR=888) (TKNTPT(K),K=1,5)
        DO 160 NK=1,5
        KT=KT+1
        IF(KT.LE.NKNOTS) THEN
          IJ=IJ+1
          CARRAY(IJ)=TKNTPT(NK)
        ENDIF
  160   CONTINUE
  170   CONTINUE
C
      ENDIF
C
C   FIX CARRAY IF Z IS ALWAYS ZERO OR DENOM IS ALWAYS ONE
      IF (DIS1) THEN
        CARRAY(2) = DBLE(IPHY)
        ISIZE = ISIZE - NCTRP
        IF (IPHY .EQ. 3 .AND. ZIS0) THEN
          CARRAY(2) = 2.0D0
          ISIZE = ISIZE - NCTRP
        END IF
      ELSE IF (IPHY .EQ. 3 .AND. ZIS0) THEN
        CARRAY(2) = -3.0D0
        DO 180 KP=ISIZE-NCTRP+1,ISIZE
          CARRAY(KP-NCTRP) = CARRAY(KP)
  180   CONTINUE
        ISIZE = ISIZE - NCTRP
      END IF
C
C...WRITE C-ARRAY TO DTRC FORMAT FILE
C
      WRITE (JUN,*) (CARRAY(I),I=1,ISIZE)
C
C...READ AND WRITE NEXT OBJECT
C
      GOTO 100
C
C...ZERO DENOMINATOR ERROR IN AGPS RATIONAL SPLINE DATA
  887 IERR=-4
      GOTO 999
C
  888 CONTINUE
      IERR=-3
  999 CONTINUE
      CLOSE (IUN)
      CLOSE (JUN)
      RETURN
      END
