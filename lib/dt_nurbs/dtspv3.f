C<*>
      SUBROUTINE DTSPV3(X,KORD,TKTS,INCK,COEF,INCC,NDER,
     1                  A,B,C,V,INCV,IER)
C
C  PURPOSE:  EVALUATE VALUE AND DERIVATIVES AT X OF A SCALAR-VALUED
C            UNIVARIATE SPLINE, GIVEN ONLY THE KNOTS AND COEFFS
C            RELEVANT TO THE SPAN CONTAINING X.
C
C  INPUTS:
C
C           X       VALUE AT WHICH TO EVALUATE.
C           KORD    ORDER OF SPLINE.
C           TKTS    ARRAY OF 2*KORD KNOTS, SUCH THAT
C                       KNOT #KORD .LE. X .LE. KNOT #(KORD1).
C           INCK    INCREMENT PARAMETER FOR TKTS.
C           COEF    ARRAY OF KORD B-SPLINE COEFFICIENTS.
C           INCC    INCREMENT PARAMETER FOR COEF.
C           NDER    NUMBER OF DERIVATIVES TO EVALUATE.
C                   NDER .GE. KORD IS ALLOWED.
C                   NDER .LT. 0 IS TREATED AS ZERO.
C           INCV    INCREMENT PARAMETER FOR V.
C
C  WORKING STORAGE:
C
C          A,B    TWO ARRAYS, EACH OF LENGTH KORD-1.
C          C      AN ARRAY OF LENGTH KORD.
C
C  OUTPUT:
C
C           V      ARRAY CONTAINING VALUE AND DERIVATIVES.
C                  V(1+J*INCV) = J'TH DERIVATIVE.
C           IER    SUCCESS/ERROR CODE.
C                  IER=0     SUCCESS.
C                  IER=-38   ATTEMPT TO EVALUATE AT POINT THAT IS
C                            INSIDE AN INTERVAL THAT IS TOO SMALL.
C
C  METHOD:  DEBOOR - LEE.  X NEAR LEFT END OF INTERVAL IS EVALUATED
C           USING DIFFERENCES FROM RIGHT, AND VICE-VERSA, TO
C           ENHANCE STABILITY, MAKE EVALUATION CONTINUOUS AT BOTH
C           ENDPOINTS OF THE INTERVAL.
C
C  AUTHOR:  A.K. JONES
C
C  DATE:  27-SEP-84
C
C  MINOR REVISIONS BY FRITZ KLEIN, 21-JAN-85
C
      DOUBLE PRECISION X,TKTS(INCK,*),COEF(INCC,*),A(*),B(*),C(*)
      DOUBLE PRECISION FACTOR,ZERO,V(INCV,*)
C
      DATA ZERO / 0.D0 /
      M = KORD - 1
      ND = MAX0(0,MIN0(M,NDER))
      IF(M .GT. 0) GO TO 100
C
C  SPECIAL CASE OF DEGREE = 0.
C
      C(1) = COEF(1,1)
      GO TO 1000
C
C  GENERAL CASE OF DEGREE GREATER THAN 0.
C
  100 CONTINUE
      DO 110 I=1,M
        A(I) = X - TKTS(1,I+1)
        IB = KORD + I
        B(I) = TKTS(1,IB) - X
  110 CONTINUE
      IF ( ( (B(1).LE.A(M)) .AND. (A(M).LE.0.D0) ) .OR.
     1     ( (A(M).LE.B(1)) .AND. (B(1).LE.0.D0) ) )  GO TO 1220
      IF(B(1) .LE. A(M)) GO TO 500
C
C  X IN LEFT HALF OF INTERVAL, SO EVALUATE FROM RIGHT.
C
      DO 200 I=1,KORD
        C(I) = COEF(1,I)
  200 CONTINUE
      DO 300 J=1,M
        ILAST = KORD - J
        DO 290 I=1,ILAST
          IA = I + J - 1
          C(I) = (A(IA)*C(I+1) + B(I)*C(I)) / (A(IA) + B(I))
  290   CONTINUE
  300 CONTINUE
      IF(ND .LT. 1) GO TO 410
      DO 400 J=1,ND
        FACTOR = KORD - J
        DO 390 II=J,ND
          I = ND + J - II
          IB = I - J + 1
          C(I+1) = FACTOR * (C(I+1) - C(I)) / B(IB)
  390   CONTINUE
  400 CONTINUE
  410 CONTINUE
      GO TO 1000
C
C  X IN RIGHT HALF OF INTERVAL, SO EVALUATE FROM THE LEFT.
C
  500 CONTINUE
      DO 600 I=1,KORD
        IC = KORD + 1 - I
        C(I) = COEF(1,IC)
  600 CONTINUE
      DO 700 J=1,M
        ILAST = KORD - J
        DO 690 I=1,ILAST
          IA = KORD - I
          IB = KORD + 1 - (I+J)
          C(I) = (B(IB)*C(I+1) + A(IA)*C(I)) / (A(IA) + B(IB))
  690   CONTINUE
  700 CONTINUE
      IF(ND .LT. 1) GO TO 810
      DO 800 J=1,ND
        FACTOR = KORD - J
        DO 790 II=J,ND
          I = ND + J - II
          IA = M + J - I
          C(I+1) = FACTOR * (C(I) - C(I+1)) / A(IA)
  790   CONTINUE
  800 CONTINUE
  810 CONTINUE
C
 1000 CONTINUE
      ND1 = ND + 1
      DO 1100 I=1,ND1
        V(1,I) = C(I)
 1100 CONTINUE
      IF(ND1 .GT. NDER) GO TO 1210
      DO 1200 I=ND1,NDER
        V(1,I+1) = ZERO
 1200 CONTINUE
 1210 CONTINUE
C
C  NORMAL RETURN
C
      IER = 0
      RETURN
 1220 CONTINUE
C
C  ERROR EXIT
C
      IER = -38
      RETURN
      END