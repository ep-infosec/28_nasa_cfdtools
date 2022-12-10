      SUBROUTINE D2FEBI (CMEM, IMEM, DMEM, IDE, JBLO, JBHI, IER)

C     PURPOSE:
C        Fetch Bounds of Entity's integer space.  All memory in
C        the integer space up to JBHI is locked.
C
C     DYNAMIC MEMORY INPUT-OUTPUT:
C        CMEM     Dynamically managed character data
C        IMEM     Dynamically managed integer data
C        DMEM     Dynamically managed double precision data
C
C     INPUT:
C        IDE      Pointer to entity to fetch
C
C     OUTPUT:
C        JBLO     Lower bound of the entity's integer space
C        JBHI     Upper bound of the entity's integer space
C        IER      Error flag.  If negative, the bounds are set to 0.
C                 -1 =  Dynamic memory is corrupt or uninitialized.
C                 -2 =  Null pointer (IDE = 0)
C                 -3 =  Garbage value in pointer (points outside valid
C                       range in IMEM)
C                 -4 =  Either a deleted entity or a garbage value in
C                       pointer
C                 -5 =  Pointer refers to a deleted entity
C                 -6 =  LENI = 0
C
C     CALLS:
C        D0PTR
C
C     HISTORY:
C        27Feb92  D. Parsons  Created.
C        13Apr92  D. Parsons  Add check of dynamic memory.
C        21Jun93  D. Parsons  Add IER = -6
C
C     ------

C     Long name alias:
C        ENTRY D2_FETCH_IMEM_BOUNDS (CMEM, IMEM, DMEM, IDE, JBLO,
C    +         JBHI, IER)

      CHARACTER         CMEM*(*)
      INTEGER           IMEM(*), IDE
      DOUBLE PRECISION  DMEM(*)

      INTEGER           IHDR, ITYP, LENI, JBLO, JBHI, IER

      CHARACTER*6 SUBNAM
      DATA SUBNAM /'D2FEBI'/

C     ------

C     Call the general pointer-check utility routine

      CALL D0PTR (CMEM, IMEM, DMEM, IDE, 0, 0, IHDR, ITYP, IER)
      IF (IER .NE. 0) GOTO 9000

      JBLO = IMEM(IHDR+2)
      LENI = ABS(IMEM(IHDR+5))
      JBHI = JBLO + LENI - 1

      IF (LENI .LE. 0) THEN
         IER = -6
         GOTO 9000
      ENDIF
      
C     Lock all integer memory up to JBHI

C     ...Set "next unlocked location in IMEM to JBHI+1
C     ...Set "highest locked header location" to IHDR

      IF (IMEM(8) .LE. JBHI) THEN
         IMEM(8) = JBHI+1
         IMEM(11) = IHDR
      ENDIF

C     ...Set Length of integer memory to negative

      IMEM(IHDR+5) = -LENI

C     ...Set "lowest location to check" to above this entity's space

      IMEM(14) = MIN(IMEM(14),JBLO)

      GOTO 9999

C     Error return

 9000 CONTINUE

      JBLO = 0
      JBHI = 0
      CALL DTERR (1, SUBNAM, IER, 0)

 9999 CONTINUE

      RETURN
      END
