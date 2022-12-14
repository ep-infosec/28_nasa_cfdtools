      SUBROUTINE DTSMGD(NS,NT,NDIM,ICYL,IFX,SGST,XSC,XSR,GST,IER)
C***********************************************************************
C
C FUNCTION-
C          TO SMOOTH THE POINTS OF A GRID SYSTEM BY USING THREE
C          OR FIVE POINTS SMOOTHER.
C
C AUTHORS-
C          C.P.CHI             REVISION  SEPTEMBER 1989
 
C  INPUT    NS    NUMBER OF ROWS OF THE GRID SYSTEM 
C           NT    NUMBER OF COLUMNS OF THE GRID SYSTEM
C           NDIM  DIMENSION FOR THE POINTS OF THE GRID 
C           ICYL  NUMBER OF SMOOTHING CYCLES 
C           IFX   INDEX FOR FIXED POINTS OF THE GRID 
C            = 0  NON-FIXED POINT
C            = 1  FIXED POINT
C  
C  WORKING 
C  STORAGE  SGST  ARRAY CONTAINING THE SMOOTHED GRID DATA FOR EACH CYCLE 
C           XSC   ARRAY FOR TEMPORARY STORING THE COLUMN-WISE SMOOTHED POINT 
C           XSR   ARRAY FOR TEMPORARY STORING THE ROW-WISE SMOOTHED POINT 
C  
C  INPUT/
C  OUTPUT   GST   ON INPUT, THE ARRAY CONTAINING THE GRID OF POINTS, ON OUTPUT, 
C                 THE ARRAY CONTAINING THE SMOOTHED POINTS
C  
C  OUTPUT   IER   ERROR FLAG 
C            =  0 NO ERROR
C            = -1 THE DIMENSION FOR GRID POINT IS LESS THAN 1 OR GREATER THAN 3. 
C            = -2 NUMBER OF GRID POINTS IN ANY DIRECTION OF THE GRID SYSTEM IS 
C                 LESS THAN 1. 
C
C NOTES-
C          1. THE FOUR CORNER POINTS OF THE GRID SYSTEM ARE FIXED.
C          2. THREE POINTS SMOOTHER IS APPLIED TO POINTS NEXT TO
C             THE END POINTS. FIVE POINTS SMOOTHER IS APPLIED TO
C             OTHER INTERNAL POINTS. THE USER MAY SPECIFY FIXED
C             INTERNAL POINTS.
C          3. EACH POINT IS TO BE SMOOTHED N CYCLES BOTH CLOUMNWISE
C             AND ROWWISE. THE AVERAGED VALUE WILL BE STORED AFTER
C             EACH CYCLE AND IS TO BE USED IN NEXT CYCLE.
C          4. NO SMOOTHED POINTS FROM THE CURRENT CYCLE ARE USED
C             IN THAT CYCLE.
C
C TYPE/PARAMETER/DIMENSION/COMMON/EQUIVALENCE/DATA/FORMAT STATEMENTS-
C
      INTEGER IFX(NS,NT)
      DOUBLE PRECISION GST(NS,NT,NDIM), SGST(NS,NDIM,3)
      DOUBLE PRECISION XSC(NDIM), XSR(NDIM)
C
C ********************** START OF EXECUTABLE CODE **********************
C
C...CHECK INPUT DATA
C
C...CHECK FOR ILLEGAL DIMENSION
C
      IF(NDIM.LT.1.OR.NDIM.GT.3) THEN
        IERR=-1
        GOTO 9999
      ENDIF
C
      IF(NS.LT.1 .OR. NT.LT.1) THEN
        IERR=-2
        GOTO 9999
      ENDIF
C
C...START SMOOTHING
C   APPLY THE SMOOTHERS ICYL CYCLES
C
      DO 2000 IC=1, ICYL
C
C...SELECT THE POINTS TO BE SMOOTHED
C
      DO 1000 J=1, NT
      DO  900 I=1, NS
C
C...COPY THE FIXED POINT
C
      IF(IFX(I,J).EQ.1) THEN
        DO 100 K=1, NDIM
        SGST(I,K,3)=GST(I,J,K)
  100   CONTINUE
        GOTO 1000
      ENDIF
C
C...START COLUMN-WISE SMOOTHING
C
C...COPY THE COLUMN-WISE END POINT
C
      IF(I.EQ.1.OR.I.EQ.NS) THEN
        DO 150 K=1, NDIM
        XSC(K)=GST(I,J,K)
  150   CONTINUE
C
        GOTO 500
C
      ELSEIF (I.EQ.2.OR.I.EQ.NS-1) THEN
C
C...USE 3-POINT SMOOTHER ON THE POINT NEXT TO END POINTS
C
        DO 200 K=1, NDIM
        XSC(K)=(GST(I-1,J,K)+2.0*GST(I,J,K)+GST(I+1,J,K))/4.0
  200   CONTINUE
C
      ELSE
C
C...USE 5-POINT SMOOTHER ON ALL OTHER INTERNAL POINTS
C
        DO 300 K=1, NDIM
        XSC(K)=(-GST(I-2,J,K)+4.0*GST(I-1,J,K)+10.0*GST(I,J,K)
     $          +4.0*GST(I+1,J,K)-GST(I+2,J,K))/16.0
  300   CONTINUE
C
      ENDIF
C
  500 CONTINUE
C
C...PERFORM ROW-WISE SMOOTHING ONLY IF NUMBER OF POINTS IN THE SECOND
C   DIRECTION IS GREATER THAN 2.
C
      IF(NT.LE.2) GOTO 800
C
C...START ROW-WISE SMOOTHING
C
C...COPY THE ROW-WISE END POINT
C
      IF(J.EQ.1.OR.J.EQ.NT) THEN
        DO 550 K=1, NDIM
        XSR(K)=GST(I,J,K)
  550   CONTINUE
C
        GOTO 800
C
      ELSEIF (J.EQ.2.OR.J.EQ.NT-1) THEN
C
C...USE 3-POINT SMOOTHER ON THE POINT NEXT TO END POINTS
C
        DO 600 K=1, NDIM
        XSR(K)=(GST(I,J-1,K)+2.0*GST(I,J,K)+GST(I,J+1,K))/4.0
  600   CONTINUE
C
      ELSE
C
C...USE 5-POINT SMOOTHER ON ALL OTHER INTERNAL POINTS
C
        DO 700 K=1, NDIM
        XSR(K)=(-GST(I,J-2,K)+4.0*GST(I,J-1,K)+10.0*GST(I,J,K)
     $          +4.0*GST(I,J+1,K)-GST(I,J+2,K))/16.0
  700   CONTINUE
C
      ENDIF
C
  800 CONTINUE
C
C...TRANSFER THE AVEREAGE VALUES TO THE WORKING ARRAY
C
      DO 810 K=1, NDIM
      IF(NT.GT.2) THEN
        SGST(I,K,3)=(XSC(K)+XSR(K))/2.0
      ELSE
        SGST(I,K,3)=XSC(K)
      ENDIF
  810 CONTINUE
C
  900 CONTINUE
C
C...PUT BACK THE AVERAGE OF COLUMN- AND ROW-WISE SMOOTHED VALUES
C   ONLY WHEN THE CURRENT POINT NOT BE USED ANY MORE.
C
      IF(J.GT.2) THEN
        J2=J-2
        DO 930 I=1, NS
        DO 925 K=1, NDIM
        GST(I,J2,K)=SGST(I,K,1)
  925   CONTINUE
  930   CONTINUE
      ENDIF
C
C...ROTATE THE VALUES IN THE WORKING ARRAY SO THAT IT CONTAINS
C   THE VALUES FOR J-2, J-1, AND J, WHEN ENTERING THE FOLLOWING
C   LOOP
C
      DO 980 IK=1, 2
      IK1=IK+1
      DO 960 I=1, NS
      DO 950 K=1, NDIM
      SGST(I,K,IK)=SGST(I,K,IK1)
  950 CONTINUE
  960 CONTINUE
  980 CONTINUE
C
 1000 CONTINUE
C
C...PUT BACK THE LAST TWO COLUMNS
C
      IF(NT .GT. 1) THEN
        IJ=0
        DO 1050 J=NT-1, NT
        IJ=IJ+1
        DO 1030 I=1, NS
        DO 1020 K=1, NDIM
        GST(I,J,K)=SGST(I,K,IJ)
 1020   CONTINUE
 1030   CONTINUE
 1050   CONTINUE
      ELSE
        DO 1070 I=1, NS
        DO 1060 K=1, NDIM
        GST(I,1,K)=SGST(I,K,2)
 1060   CONTINUE
 1070   CONTINUE
      ENDIF
C
 2000 CONTINUE
C
 9999 CONTINUE
      RETURN
      END
