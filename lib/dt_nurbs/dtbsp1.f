      SUBROUTINE DTBSP1 ( XKNOTS, X, IPOS, K, NDERV, WK, VAL, NDIM )
C
C  PURPOSE  DTBSP1 COMPUTES THE VALUES (INCLUDING A SPECIFIED NUMBER OF
C           THE POSSIBLY NONZERO DERIVATIVES) OF THE POSSIBLY NONZERO
C           B-SPLINES OF ORDER  K  AT  X  FOR THE KNOT SEQUENCE XKNOTS.
C           DTBSP1 IS INTENDED AS A LOWER LEVEL MATH LIBRARY ROUTINE
C           AND DOES NOT PERFORM ANY ARGUMENT VALIDITY CHECKING.
C
C  REMARK   IF DERIVATIVES ARE NOT REQUIRED, DTBSP2 COULD BE USED.
C
C  METHOD   DTBSP1 CALCULATES DERIVATIVES BY DIFFERENCING THE SPLINE
C           COEFFICIENTS AND TAKING THE DOT PRODUCT WITH B-SPLINE VALUES
C           OF A APPROPRIATE ORDER.  DTBSP2 IS USED TO COMPUTE THE
C           B-SPLINE VALUES FOR ALL REQUIRED ORDERS.
C
C  REF.     DTBSP1 IS BASED ON DE BOOR SUBROUTINE BSPLVD.  SEE PAGE 288
C           IN DE BOOR, A PRACTICAL GUIDE TO SPLINES, SPRINGER-VERLAG,
C           1978.
C
C  USAGE    DOUBLE PRECISION XKNOTS(NKNOTS), WK(K*K), VAL(NDIM,NDERV+1)
C           CALL DTBSP1 ( XKNOTS, X, IPOS, K, NDERV, WK, VAL, NDIM )
C
C  INPUT    XKNOTS  ARRAY OF LENGTH  NKNOTS  CONTAINING THE KNOTS.
C
C           X       VALUE AT WHICH EVALUATION IS DESIRED.
C
C           IPOS    POSITION OF  X  WITHIN KNOTS.  IPOS IS SUCH THAT
C                        XKNOTS(IPOS) .LT. XKNOTS(IPOS+1)
C                   AND  XKNOTS(IPOS) .LE. X .LE. XKNOTS(IPOS+1)
C                   AND  K .LE. IPOS .LE. NKNOTS-K+1.
C
C           K       ORDER OF THE B-SPLINES TO BE COMPUTED.
C
C           NDERV   NUMBER OF THE POSSIBLY NONZERO DERIVATIVES
C                   DESIRED, 0 .LE. NDERV .LE. K-1.
C
C           NDIM    LEADING DIMENSION OF THE TWO-DIMENSIONAL ARRAY  VAL.
C
C  WORKING  WK      WORKING STORAGE ARRARY OF LENGTH AT LEAST  K*K.
C  STORAGE
C
C  OUTPUT   VAL     ARRAY CONTAINING THE FUNCTION AND DERIVATIVE
C                   VALUES OF THE B-SPLINES WHERE VAL(I,J) IS THE
C                   (J-1)-ST DERIVATIVE OF THE I-TH B-SPLINE,
C                   I = 1, ..., K AND J = 1, ..., NDERV+1.
C
C  CALLS    DTBSP2
C
C  AUTHOR   LYNN T. WINTER.
C
C  DATE     4 - JAN - 1985.
C
C=======================================================================
C
C ... ARGUMENT DECLARATIONS.
C
      INTEGER IPOS, K, NDERV, NDIM
      DOUBLE PRECISION    XKNOTS(*), X, WK(K,*), VAL(NDIM,*)
C
C ... LOCAL VARIABLE DECLARATIONS.
C
      INTEGER I,IL, J, ID, IT, KT, M, IK, JT, KP1, L, ND, ILKT
      DOUBLE PRECISION    FACTOR, SUM, AKT
C
C=======================================================================
C
C ... BEGIN EXECUTABLE CODE.
C
      ND = NDERV + 1
C
C ... COMPUTE VALUES OF B-SPLINES AT  X  FOR ORDERS K-ND+1
C     THROUGH K.  THESE ARE STORED TEMPORARILY IN ARRAY VAL.
C
      KP1 = K+1
      IK  = 0
      KT  = KP1-ND
      CALL DTBSP2 (XKNOTS, X, IPOS, IK, KT, WK(1,1), WK(1,2), VAL(1,1))
C
      IF ( ND .EQ. 1 ) GO TO 100
C
      ID = ND
      DO 20 M = 2, ND
        JT = 1
        DO 10 J = ID, K
          VAL(J,ID) = VAL(JT,1)
          JT = JT+1
   10   CONTINUE
C
        ID = ID-1
        KT = KT+1
        CALL DTBSP2(XKNOTS, X, IPOS, IK, KT, WK(1,1), WK(1,2), VAL(1,1))
   20 CONTINUE
C
C
C ... INITIALIZE WORK ARRAY WITH THE COEFFICIENTS OF THE B-SPLINES
C     VIEWED AS LINEAR COMBINATIONS OF THEMSELVES.  THAT IS, THE
C     COEFFICIENTS ARE ONE.
C
      JT = 1
      DO 40 I = 1, K
        DO 30 J = JT, K
          WK(J,I) = 0.D0
   30   CONTINUE
        JT = I
        WK(I,I) = 1.D0
   40 CONTINUE
C
C ... COMPUTE THE DERIVATIVE VALUES BY DIFFERENCING THE B-SPLINE
C     COEFFICIENTS AND TAKING THE DOT PRODUCT WITH THE B-SPLINE
C     VALUES OF THE APPROPRIATE ORDER.
C
      DO 90 M = 2, ND
        KT  = KP1-M
        AKT = FLOAT(KT)
        IL  = IPOS
        I   = K
C
        DO 60 L = 1, KT
          ILKT = IL + KT
          FACTOR = AKT / ( XKNOTS(ILKT) - XKNOTS(IL) )
          IT = I-1
          DO 50 J = 1, I
            WK(I,J) = ( WK(I,J) - WK(IT,J) ) * FACTOR
   50     CONTINUE
          IL = IL-1
          I  = I-1
   60   CONTINUE
        DO 80 I = 1, K
          SUM = 0.D0
          JT  = MAX0 (I, M)
          DO 70 J = JT, K
            SUM = SUM + WK(J,I) * VAL(J,M)
   70     CONTINUE
          VAL(I,M) = SUM
   80   CONTINUE
   90 CONTINUE
C
  100 RETURN
C
      END