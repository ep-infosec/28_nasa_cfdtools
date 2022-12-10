C<*>
      SUBROUTINE DTSPV1(X,KORD,TKTS,INCK,
     1                  NCOEF,COEF,INCC,NDIMC,NRNG,
     2                  ISPAN,WORK,V,IER)
C
C  PURPOSE:  SPLINE EVALUATION FROM USER-DEFINED DATA ARRAYS.
C
C  INPUTS:
C
C           X       VALUE AT WHICH TO EVALUATE.
C           KORD    ORDER OF SPLINE,
C                   KORD .GE. 0.
C           TKTS    KNOT VECTOR.
C           INCK    INCREMENT FOR KNOT VECTOR,
C                   INCK .GT. 0.
C           NCOEF   NUMBER OF B-SPLINE COEFFICIENTS FOR EACH
C                   DEPENDENT VARIABLE,
C                   NCOEF .GE. KORD.
C           COEF    ARRAY OF B-SPLINE COEFFICIENTS.
C           INCC    INCREMENT FOR COEF ARRAY,
C                   INCC .GT. 0.
C           NDIMC   FIRST DIMENSION OF COEF ARRAY,
C                   NDIMC .GE. 1++INCC*(NCOEF-1).
C           NRNG    NUMBER OF DEPENDENT VARIABLES,
C                   NRNG .GT. 0.
C
C  WORKING STORAGE:
C
C           WORK    REAL ARRAY OF LENGTH NWORK, WHERE
C                   NWORK .GE. 5*KORD - 2
C
C  INPUT/OUTPUT:
C
C           ISPAN   ON INPUT, GUESS AT SPAN NUMBER IN WHICH X LIES.
C                   ON OUTPUT, TRUE SPAN NUMBER IN WHICH X LIES.
C
C  OUTPUT:
C
C           V       ARRAY CONTAINING THE SPLINE VALUES.
C                   V(1+INCV*(I-1)) = I'TH DEPENDENT VARIABLE.
C
C           IER     SUCCESS/ERROR CODE.
C                   IER=0     SUCCESS.
C                   IER=-8    INVALID KNOT SET.
C                   IER=-50   X OUT OF RANGE.
C                   IER=-38   ATTEMPT TO EVALUATE AT POINT THAT IS
C                             INSIDE AN INTERVAL THAT IS TOO SMALL.
C
C  SUBROUTINES CALLED:  DTSPV2,DTSPV3,DTBSP2,DTILC1,DTMCON,DTERR
C
C  AUTHOR:  A.K. JONES
C
C  DATE:  1-NOV-84
C
C  MINOR REVISIONS BY FRITZ KLEIN, 21-JAN-85
C
      DOUBLE PRECISION X,TKTS(*),COEF(NDIMC,*),WORK(*),V(NRNG)
      DOUBLE PRECISION ZERO
      EXTERNAL  DTSPV2,DTSPV3,DTBSP2,DTILC1,DTMCON,DTERR
C
      DATA ZERO/0.D0/
C
      NKTS = NCOEF + KORD
C
C  SPLIT UP WORK ARRAY.
C
      IW1 = 1
      IW2 = IW1 + KORD
      IW3 = IW2 + KORD
      IW4 = IW3 + KORD
      IW5 = IW4 + KORD - 1
C
C  FIND INTERVAL FOR EVALUATION.
C
      CALL DTSPV2(X,KORD,TKTS,INCK,NKTS,ISPAN,NEXT,IER)
      IF(IER .EQ. -50) GO TO 9900
      IK = 1 + INCK * (NEXT - KORD)
      IC = 1 + INCC * (NEXT - KORD)
      NKNOTS = 2 * KORD
C
C  PACK KNOTS INTO CONTIGUOUS ARRAY FOR DTBSPL.
C
      DO 10 I=1,NKNOTS
        IK1 = IW2 + I - 1
        IK2 = IK + (I-1) * INCK
        WORK(IK1) = TKTS(IK2)
   10 CONTINUE
      CALL DTILC1(WORK(IW2),NKNOTS,KORD,IFAIL)
      IF(IFAIL.EQ.0) GO TO 20
        IER=-8
        GO TO 9900
   20 CONTINUE
C
      IF(NRNG .GT. 1) GO TO 200
C
C  SPECIAL CASE NRNG = 1.
C     NOTE THAT IN THIS CASE, THE CURRENT VALUES IN WORK(IW2) ARE
C     NOT USED.  THIS AREA IS USED AS WORKING STORAGE BY HSSPV3.
C
      NDER = 0
      CALL DTSPV3(X,KORD,TKTS(IK),INCK,COEF(IC,1),INCC,NDER,
     1            WORK(IW1),WORK(IW2),WORK(IW3),V,NRNG,IER)
      IF (IER.NE.0) GO TO 9900
      GO TO 9000
C
C  CASE NRNG .GT. 1.
C
  200 CONTINUE
      K0 = 0
      CALL DTBSP2(WORK(IW2),X,KORD,K0,KORD,WORK(IW4),WORK(IW5),
     1            WORK(IW1))
C
C  B-SPLINE VALUES NOW IN WORK(1..KORD).
C  FORM INNER PRODUCTS.
C
  300 CONTINUE
      DO 500 I=1,NRNG
        V(I) = ZERO
        DO 400 J=1,KORD
          JC = IC + (J-1)*INCC
          V(I) = V(I) + COEF(JC,I) * WORK(J)
  400   CONTINUE
  500 CONTINUE
C
C  NORMAL EXIT.
C
 9000 CONTINUE
      IER = 0
      ISPAN = NEXT
C
C  ERROR EXITS.
C
 9900 CONTINUE
      RETURN
      END