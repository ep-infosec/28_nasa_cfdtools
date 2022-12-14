      DOUBLE PRECISION FUNCTION DTMCON(I)
C ******************************************
C *                                        *
C *  COPYRIGHT  1987  THE BOEING COMPANY   *
C *                                        *
C *  ALL  RIGHTS  RESERVED                 *
C *                                        *
C ******************************************
C
C MACHINE CONSTANTS FOR PORTABLE CODE SUPPORT ON:
C     IRIS4D
C
C CODE GENERATED BY PROGRAM DMCON1
C
C INPUT  - I (IN 1..16) IS THE INDEX OF THE DESIRED CONSTANT
C OUTPUT - DTMCON IS THE DESIRED CONSTANT
C ERRORS - IF I IS OUT OF RANGE, DTMCON(1) IS RETURNED
 
      INTEGER  I,J,Q(2,16)
      DOUBLE PRECISION  A(16)
      EQUIVALENCE (A(1),Q(1,1))
 
C INDEX:VALUE TABLE
C     1:DCLOBR      7:DRADIX     12:DPI
C     2:DRANGE      8:DDIGIT     13:DEXPE
C     3:DOVFLO      9:DEOVFL     14:DEULER
C     4:DUNFLO     10:DEUNFL     15:DRADEG
C     5:DRELSP     11:DMXINT     16:DDEGRA
C     6:DRELPR
 
      DATA (Q(J, 1),J=1,2)/ 2147483647,         -1/
      DATA (Q(J, 2),J=1,2)/ 2144337920,          0/
      DATA (Q(J, 3),J=1,2)/ 2146435071,         -1/
      DATA (Q(J, 4),J=1,2)/    1048576,          0/
      DATA (Q(J, 5),J=1,2)/ 1018167296,          0/
      DATA (Q(J, 6),J=1,2)/ 1017118720,          1/
      DATA (Q(J, 7),J=1,2)/ 1073741824,          0/
      DATA (Q(J, 8),J=1,2)/ 1078624256,          0/
      DATA (Q(J, 9),J=1,2)/ 1082533888,          0/
      DATA (Q(J,10),J=1,2)/-1064951808,          0/
      DATA (Q(J,11),J=1,2)/ 1105199103,   -4194304/
      DATA (Q(J,12),J=1,2)/ 1074340347, 1413754136/
      DATA (Q(J,13),J=1,2)/ 1074118410,-1961601175/
      DATA (Q(J,14),J=1,2)/ 1071806604,  -59787751/
      DATA (Q(J,15),J=1,2)/ 1066524486,-1571644103/
      DATA (Q(J,16),J=1,2)/ 1078765020,  442745336/
 
      J = I
      IF ( J .LE. 0  .OR.  J .GT. 16 ) J = 1
      DTMCON = A(J)
 
      END
