       SUBROUTINE DTUPDG(CIN,IDOM,NCOUT,WORK,NWORK,
     1                  COUT,IER)
C+
C  PURPOSE:  DRIVER FOR RAISING THE FORMAL POLYNOMIAL
C            DEGREE OF A SPLINE FUNCTION BY ONE.
C
C  INPUTS:  CIN   INPUT SPLINE, IN C VECTOR FORM.
C           IDOM  INDEX OF THE INDEPENDENT VARIABLE IN WHICH
C                 THE DEGREE IS TO BE INCREASED.
C           NCOUT LENGTH OF COUT ARRAY PASSED IN.
C                 A VALUE WHICH IS ALWAYS SAFE IS
C                 NCOUT = 2*(THE LENGTH OF THE INPUT SPLINE).
C                 THE LENGTH OF THE INPUT SPLINE CAN BE CALCULATED AS
C                 CIN(3) + (CIN(2)+1)*CIN(4)
C
C  WORKING STORAGE:
C
C           WORK  WORK ARRAY OF LENGTH NWORK.
C           NWORK LENGTH OF WORK ARRAY,
C                 NWORK .GE. 2*CIN(2).
C
C  OUTPUT:  COUT  OUTPUT SPLINE, IN C VECTOR FORM.
C                 THE FUNCTION REPRESENTED IS EXACTLY THE SAME, BUT
C                 THE FORMAL DEGREE IS ONE HIGHER.  E.G., A QUADRATIC
C                 ON INPUT WILL BE WRITTEN AS A DEGENERATE CUBIC
C                 ON OUTPUT.
C
C           IER   SUCCESS/ERROR CODE.
C                 IER =  0   SUCCESS
C                 IER = -1   ORDER OF INPUT SPLINE .LT. 1.
C                 IER = -3   NWORK TOO SMALL.
C                 IER = -6   INPUT SPLINE HAS TOO FEW COEFFICIENTS.
C                 IER = -8   KNOTS NOT INCREASING, OR MULTIPLICITIES TOO HIGH.
C                 IER = -51  NUMBER OF INDEPENDENT VARIABLES IN INPUT SPLINE
C                            .LT. 1.
C                 IER = -52  NUMBER OF DEPENDENT VARIABLES IN INPUT SPLINE
C                            .LT. 1.
C                 IER = -61  NCOUT TOO SMALL.
C                 IER = -62  IDOM .LT. 1, OR GREATER THAN NUMBER OF DEPENDENT
C                            VARIABLES IN INPUT SPLINE.
C                 IER = -100 NUMERICAL ERROR DUE TO A PROBLEM WITH THE
C                            KNOT SET.
C
C  DATE:  23-JAN-86
C-
      DOUBLE PRECISION CIN(*),WORK(*),COUT(*)
      INTEGER IDOM, NWORK, NCOUT, IER
      INTEGER NDOM, NRNG, KIN, NCPIN, NKTIN, NDEG, KOUT, KDLT, IKPTR
      INTEGER NCPLO, I, J, KORDJ, NCPJ, NDK, MLT, ILPTR, NCPOUT, NKTOUT
      INTEGER NCPHI, ICPTR, ICPTR2, NCNEED, NEED, INC1, INC2, NDIM1
      INTEGER NDIM2, ICC, MODE
      CHARACTER*8 SUBNAM
      DATA SUBNAM   / 'DTUPDG'  /
C
      IER   = 0
      NDOM  = CIN(1)
      NRNG  = CIN(2)
      IF(NDOM .LT. 1) THEN
        IER = -51
        GO TO 9100
      ELSE IF(NRNG .LT. 1) THEN
        IER = -52
        GO TO 9100
      ELSE IF(IDOM .LT. 1 .OR. IDOM .GT. NDOM) THEN
        IER = -62
        GO TO 9100
      END IF
      KIN   = CIN(2+IDOM)
      NCPIN = CIN(2+NDOM+IDOM)
      NKTIN = NCPIN + KIN
      IF(KIN .LT. 1) THEN
        IER = -1
        GO TO 9100
      ELSE IF(NCPIN .LT. KIN) THEN
        IER = -6
        GO TO 9100
      END IF
      NDEG = KIN
      KOUT = NDEG + 1
      KDLT = KOUT - KIN
C
C  LOOP THROUGH INDEPENDENT VARIABLES .LT. IDOM, TO FIND
C  IKPTR = POINTER TO KNOT SET NO. IDOM IN CIN AND COUT,
C  AND NCPLO = PRODUCT(NCPJ: J .LT. IDOM).
C
      IKPTR = 3*NDOM + 3
      NCPLO = 1
      DO 100 J=1,IDOM-1
        KORDJ = CIN(2+J)
        NCPJ  = CIN(2+NDOM+J)
        NCPLO = NCPLO * NCPJ
        IKPTR = IKPTR + NCPJ + KORDJ
  100 CONTINUE
C
C  SCAN INPUT KNOTS IN VARIABLE NO.IDOM FOR DISTINCT KNOTS.
C  ADD 'KDLT' TO EACH MULTIPLICITY AND STORE NEW KNOT VECTOR IN COUT.
C  ALSO CHECK INPUT KNOTS ARE NON-DECREASING.
C
      NDK = 1
      MLT = 1
      ILPTR       = IKPTR
      COUT(ILPTR) = CIN(IKPTR)
      DO 200 I=1,NKTIN-1
        IF(CIN(IKPTR+I) .GT. CIN(IKPTR+I-1)) THEN
          NDK = NDK + 1
          MLT = 0
          DO 150 J=1,KDLT
            COUT(ILPTR+J)   = CIN(IKPTR+I-1)
  150     CONTINUE
          ILPTR       = ILPTR + KDLT + 1
          COUT(ILPTR) = CIN(IKPTR+I)
        ELSE IF(CIN(IKPTR+I) .LT. CIN(IKPTR+I-1)) THEN
          IER = -8
          GO TO 9100
        ELSE
          MLT   = MLT + 1
          IF(MLT .GT. KIN) THEN
            IER = -8
            GO TO 9100
          END IF
          ILPTR = ILPTR + 1
          COUT(ILPTR) = CIN(IKPTR+I)
        END IF
  200 CONTINUE
      DO 250 J=1,KDLT
        COUT(ILPTR+J)   = CIN(IKPTR+NKTIN-1)
  250     CONTINUE
          ILPTR       = ILPTR + KDLT
C
C  NOW NDK = NUMBER OF DISTINCT KNOTS IN VARIABLE NO.IDOM,
C      ILPTR POINTS TO LAST KNOT FOR VARIABLE NO.IDOM IN COUT.
C
      NCPOUT = NCPIN + KDLT * (NDK - 1)
      NKTOUT = NCPOUT + KOUT
C
C  LOOP THROUGH INDEPENDENT VARIABLES .GT. IDOM,
C  COUNTING UP TOTAL NUMBER OF KNOTS
C  AND NCPHI = PRODUCT(NCPJ: J .GT. IDOM).
C
      NCPHI  = 1
      ICPTR  = IKPTR + NKTIN
      DO 300 J=IDOM+1,NDOM
        KORDJ  = CIN(2+J)
        NCPJ   = CIN(2+NDOM+J)
        NCPHI  = NCPHI * NCPJ
        ICPTR  = ICPTR + NCPJ + KORDJ
  300 CONTINUE
      ICPTR2 = ICPTR + KDLT * NDK
C
C  NOW ICPTR  POINTS TO COEFFICIENTS IN CIN
C      ICPTR2 POINTS TO COEFFICIENTS IN COUT
C      NCPLO*NCPHI*NCPIN(NCPOUT) = TOTAL NUMBER OF COEFFICIENTS
C                                  PER DEPENDENT VARIABLE IN CIN(COUT)..
C
      NCNEED = (ICPTR2 - 1) + NRNG * NCPLO*NCPHI*NCPOUT
      IF(NCOUT .LT. NCNEED) THEN
        IER = -61
        GO TO 9100
      END IF
C
C  COPY CONTROL DATA AND OLD KNOTS INTO CNEW.
C  NOTE THAT KNOTS FOR VARIABLE NO.IDOM ARE ALREADY IN PLACE.
C
      DO 400 I=1,IKPTR-1
        COUT(I) = CIN(I)
  400 CONTINUE
      COUT(2+IDOM)      = KOUT
      COUT(2+NDOM+IDOM) = NCPOUT
      DO 500 I=IKPTR+NKTIN,ICPTR-1
        COUT(I+KDLT*NDK) = CIN(I)
  500 CONTINUE
C
C     TEST OF WORKING STORAGE LENGTH ***
      NEED  = 2 * KIN
      IF(NEED .GT. NWORK) THEN
        IER = -3
        GO TO 9200
      END IF
C
C
C  CALL DTUPD1 ITERATIVELY TO GET NEW COEFFICIENTS.
C
      INC1  = NCPLO
      INC2  = NCPLO
      NDIM1 = NCPIN
      NDIM2 = NCPOUT
      ICC   = -1
        DO 600 J=1,NCPLO
          CALL DTUPD1(NRNG*NCPHI,KIN,NDK,NKTIN,CIN(IKPTR),
     1                CIN(ICPTR-1+J),INC1,NDIM1,WORK(1),WORK(KIN+1),
     2                NKTOUT,COUT(IKPTR),COUT(ICPTR2-1+J),
     3                INC2,NDIM2)
  600   CONTINUE
  700 CONTINUE
C
C  NORMAL EXIT
C
      ICC = IABS(ICC)
      RETURN
C
C  ERROR EXITS.
C
 9100 CONTINUE
      MODE    = 1
      GO TO 9900
 9200 CONTINUE
      MODE    = 2
      GO TO 9900
 9300 CONTINUE
      MODE = 3
 9900 CONTINUE
      ICC     = 0
      COUT(1) = -1.0D0
      CALL DTERR(MODE,SUBNAM,IER,NEED)
      RETURN
C
      END
