!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   module string_justify
!
!  This module contains utilities for left- or right-justifying character data
!  representing string, integer, or real values.  The utilities have generic
!  interfaces to allow the same call for all data types, and this requires that
!  they appear in a module.
!
!  The utilities are prompted by the formats of NASTRAN files, which appear to
!  this author to be astonishingly restrictive (but that is another story).
!
!  Integer and real value precision depend on use of compiler switches -i8 and
!  -r8 (or equivalent).  For this author, integers are 4-byte and reals are
!  compiled as 8-byte/double precision, but we avoid explicit declarations to
!  allow for 4- or 8-byte variables (but not both) with the same source code.
!
!  NOTES:  o Flawed results may be obtained if n is less than the length of the
!            appropriate buffer.  For instance, if n = 8 but an integer to be
!            justified is 123456789, it will appear as 12345678 (left) or
!            23456789 (right).  Use appropriately.
!          o The NASTRAN small field format allows no more than 8 characters
!            in a field, which is hopeless for E format.  Therefore, if n <= 8,
!            reals are written in F format with as much precision as the sign
!            and decimal point location allow.  E.g., -100.12345 will appear as
!            -100.123 (truncated), while 0.01 will appear as .0100000.
!            If n > 8, E format will be used to the extent possible.  E.g.,
!            if n = 12, -0.1234567899 will appear truncated as -1.23456E-01.
!
!  03/03/2015  D.A.Saunders  Initial implementation, for writing NASTRAN files.
!  02/04/2016    "     "     Fixed a couple of typos (comments only).
!
!  Author:  David Saunders, ERC, Inc./NASA Ames Research Center, Moffett Field.
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

   implicit none  ! Applies to all procedures

   private

   integer,        parameter :: maxebuf = 24  ! Up to 17 digits + sign + E+eee
   integer,        parameter :: maxfbuf = 17  ! For .000000001 to 999999999.
   integer,        parameter :: maxibuf = 12  ! -2^15 = -2147483648 (11 chars.)
   real,           parameter :: zero    = 0.
   character (1),  parameter :: blank   = ' '
   character (9),  parameter :: eform   = '(es24.16)'
   character (7),  parameter :: fform   = '(f17.9)'
   character (5),  parameter :: iform   = '(i12)'

   integer                   :: k, l, m
   character (maxebuf)       :: ebuf
   character (maxfbuf)       :: fbuf
   character (maxibuf)       :: ibuf

!  Public procedures:

   public :: left_justify   ! Left-justify an input value of any type, as a
                            ! character string of the indicated maximum width
   public :: right_justify  ! Right-justify likewise.

!  Interfaces to generic utilities:

   interface left_justify
      module procedure &
         left_justify_c, left_justify_i, left_justify_r    ! char, integer, real
   end interface left_justify

   interface right_justify
      module procedure &
         right_justify_c, right_justify_i, right_justify_r  ! Likewise
   end interface right_justify

   contains

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine left_justify_c (n, value, result)

!     Left justify the character string in the value argument as a string
!     in the result argument of maximum length n, padded with blanks or
!     truncated on the right if necessary.
!
!     Do NOT pass the same variable as both value and result.
!
!     No attempt is made to suppress embedded blanks: only leading ones.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result 
      character (*), intent (in)  :: value   ! Character string to left justify
      character (n), intent (out) :: result  ! Left-justified character string

!     Execution:

      l = len_trim (value)

      do m = 1, l  ! Until any leading blanks are suppressed
         if (value(m:m) /= blank) exit
      end do

      result = value(m:l)  ! Fortran right pads with blanks, or truncates

      end subroutine left_justify_c

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine left_justify_i (n, value, result)

!     Left justify the character form of the integer value argument as a string
!     in the result argument of maximum length n, padded with blanks or
!     truncated on the right if necessary (no length checking).
!
!     Strategy:  Use an internal write to a buffer more than long enough for
!     any likely value, then left-justify the result.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result
      integer,       intent (in)  :: value   ! Integer to left justify
      character (n), intent (out) :: result  ! Left-justified character string

!     Execution:

      ibuf = blank
      write (ibuf, iform) value

      do m = 1, maxibuf  ! Until any leading blanks are suppressed
         if (ibuf(m:m) /= blank) exit
      end do

      result = ibuf(m:maxibuf)  ! Fortran right pads with blanks, or truncates

      end subroutine left_justify_i

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine left_justify_r (n, value, result)

!     Left justify the character form of the real value argument as a string
!     in the result argument of maximum length n, padded with blanks or
!     truncated on the right if necessary (no length checking).
!
!     Strategy:  Use an internal write to a buffer more than long enough for
!     any likely value, then left-justify the result.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result
      real,          intent (in)  :: value   ! Integer to left justify
      character (n), intent (out) :: result  ! Left-justified character string

!     Execution:

      if (n <= 10) then  ! Biased towards NASTRAN's small field format (size 8)
         write (fbuf, fform) value  ! E format has too few significant digits
         do m = 1, maxfbuf  ! Until any leading blanks are suppressed
            if (fbuf(m:m) /= blank) exit
         end do
         if (fbuf(m:m) == '0') then
            m = m + 1  ! Change 0.01234567[8] to .012345678
         else if (fbuf(m:m+1) == '-0') then
            fbuf(m:m+1) = ' -'
            m = m + 1
         end if
         l = m + n - 1  ! <= maxfbuf since the .9 of f17.9 uses 10 characters
         result(1:n) = fbuf(m:l)  ! This is effectively right justified as well
      else
         ebuf = blank
         write (ebuf, eform) value
         do m = 1, maxebuf  ! Until any leading blanks are suppressed
            if (ebuf(m:m) /= blank) exit
         end do
         if (n <= maxebuf) then
            l = m + n - 5  ! Allow for E+00
            result(1:n-4) = ebuf(m:m+l)
            result(n-3:n) = ebuf(maxebuf-3:maxebuf)  ! Also right-justified
         else
            if (value >= zero) then  ! ebuf has a blank in the sign position
               result = ebuf(2:)  ! Pads to the right with blanks
            else
               result = ebuf      ! Likewise
            end if
         end if
      end if

      end subroutine left_justify_r

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine right_justify_c (n, value, result)

!     Right justify the character string in the value argument as a string
!     in the result argument of maximum length n, prepadded with blanks or
!     truncated on the left if necessary.
!
!     Do NOT pass the same variable as both value and result.
!
!     No attempt is made to suppress embedded blanks: only trailing ones.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result
      character (*), intent (in)  :: value   ! Character string to right justify
      character (n), intent (out) :: result  ! Right-justified character string

!     Execution:

      l = len_trim (value)    ! Last  character to transfer
      m = max (l - n + 1, 1)  ! First character to transfer
      k = n + m - l           ! Because n - k = l - m
      result      = blank     ! In case k > 1
      result(k:n) = value(m:l)

      end subroutine right_justify_c

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine right_justify_i (n, value, result)

!     Right justify the character form of the integer value argument as a string
!     in the result argument of maximum length n, prepadded with blanks or
!     truncated on the left if necessary (no length checking).
!
!     Strategy:  Use an internal write to a buffer more than long enough for
!     any likely value, then transfer the part of the result that fits.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result
      integer,       intent (in)  :: value   ! Integer to right justify
      character (n), intent (out) :: result  ! Right-justified character string

!     Execution:

      ibuf = blank
      write (ibuf, iform) value
      do m = 1, maxibuf  ! Until any leading blanks are suppressed
         if (ibuf(m:m) /= blank) exit
      end do
      if (n <= maxibuf) then
         l = min (m + n -1, maxibuf)
         k = n - (l - m)
         if (k > 1) result (1:k-1) = blank
         result(k:n) = ibuf(m:l)
      else
         m = n - maxibuf
         result(1:m)   = blank
         result(m+1:n) = ibuf
      end if

      end subroutine right_justify_i

!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

      subroutine right_justify_r (n, value, result)

!     Right justify the character form of the real value argument as a string
!     in the result argument of maximum length n, prepadded with blanks or
!     truncated on the left if necessary (no length checking).
!
!     Strategy:  Use an internal write to a buffer more than long enough for
!     any likely value, then transfer the part of the result that fits.
!
!     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

!     Arguments:

      integer,       intent (in)  :: n       ! Width of output argument result
      real,          intent (in)  :: value   ! Real number to right justify
      character (n), intent (out) :: result  ! Right-justified character string

!     Execution:

      result = blank
      if (n <= 10) then  ! Biased towards NASTRAN's small field format (size 8)
         write (fbuf, fform) value  ! E format has too few significant digits
         do m = 1, maxfbuf  ! Until any leading blanks are suppressed
            if (fbuf(m:m) /= blank) exit
         end do
         if (fbuf(m:m) == '0') then
            m = m + 1  ! Change 0.01234567[8] to .012345678
         else if (fbuf(m:m+1) == '-0') then
            fbuf(m:m+1) = ' -'
            m = m + 1
         end if
         l = m + n - 1  ! <= maxfbuf since the .9 of f17.9 uses 10 characters
         result(1:n) = fbuf(m:l)  ! This is effectively right justified as well
      else
         ebuf = blank
         write (ebuf, eform) value
         do m = 1, maxebuf  ! Until any leading blanks are suppressed
            if (ebuf(m:m) /= blank) exit
         end do
         if (n <= maxebuf) then
            l = m + n - 5  ! Allow for E+00
            result(1:n-4) = ebuf(m:m+l)
            result(n-3:n) = ebuf(maxebuf-3:maxebuf)  ! Also left-justified
         else
            m = n - maxebuf
            result(1:m)   = blank
            result(m+1:n) = ebuf
         end if
      end if

      end subroutine right_justify_r

   end module string_justify
