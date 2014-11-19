!===============================================================================
! Equilibrium related functions and subroutines
!===============================================================================
module equilibrium
  use iso_fortran_env
  use curve2D
  use magnetic_axis
  implicit none


!...............................................................................
! user defined parameters (to be set via configuration file)                   .

  character*120 :: &
     Data_File        = ''
  character*12  :: &
     Data_Format      = ''
  character(len=256) :: Magnetic_Axis_File = ''

  real*8 :: &
     R_axis       = 0.d0, &        ! user defined position of magnetic axis
     Z_axis       = 0.d0, &
     R_sepx       = 0.d0, &        ! user defined position of separatrix
     Z_sepx       = 0.d0, &
     Bt, R0, &   ! reference toroidal magnetic field [T] and radial position [cm]
     Ip           = 0.d0           ! plasma current [A] (equilibrium will be re-scaled)


  logical :: &
     use_boundary     = .true., &
     Current_Fix      = .true.

  integer :: &
     Diagnostic_Level = 0

  namelist /Equilibrium_Input/ &
     Data_File, Data_Format, use_boundary, Current_Fix, Diagnostic_Level, &
     R_axis, Z_axis, R_sepx, Z_sepx, Bt, R0, Ip, &
     Magnetic_Axis_File
!...............................................................................



!...............................................................................
! public variables                                                             .

  ! Magnetic axis (in axisymmetric configuration)
  type t_Maxis
     real*8 :: R, Z
  end type t_Maxis
  type (t_Maxis) :: Maxis2D


  ! Direction of toroidal magnetic field (Bt) and plasma current (Ip)
  ! +1: positive direction, i.e. counter-clockwise
  ! -1: negative direction, i.e. clockwise
  !  0: no equilibrium defined
! temporarily moved to module magnetic axis
!  integer :: &
!     Bt_sign  = 0, &
!     Ip_sign  = 0


  ! equilibrium type
  integer :: i_equi = -1


  ! Position of magnetic axis, poloidal magnetic flux at separatrix and magnetic axis
  !real*8 :: R_axis, Z_axis, Psi_sepx, Psi_axis
  real*8 :: &
     Psi_sepx = 1.d0, &
     Psi_axis = 0.d0








!...............................................................................
! Interfaces for functions/subroutines from specific equilibrium types         .

  ! get equilibrium magnetic field in cylindrical coordinates
  procedure(default_get_Bf), pointer :: get_Bf_eq2D  => default_get_Bf

  ! get poloidal magnetic flux
  procedure(default_get_Psi), pointer :: get_Psi => default_get_Psi

  ! get derivative of poloidal magnetic flux
  procedure(default_get_DPsi), pointer :: get_DPsi => default_get_DPsi

!  ! return poloidal magnetic flux at magnetic axis
!  procedure(Psi_axis_interface), pointer :: Psi_axis

  ! Return boundaries [cm] of equilibrium domain
  procedure(default_get_domain), pointer :: get_domain => default_get_domain

  ! inquire boundary setup from equilibrium data
  interface
     function logical_inquiry() result(l)
     logical :: l
     end function logical_inquiry

     subroutine export_curve(S)
     import :: t_curve
     type(t_curve), intent(out) :: S
     end subroutine export_curve
  end interface
  procedure(logical_inquiry), pointer :: &
     equilibrium_provides_boundary => default_equilibrium_provides_boundary
  procedure(export_curve), pointer    :: export_boundary

  ! Broadcast data for parallel execution
  procedure(), pointer :: broadcast_equilibrium
!...............................................................................


  logical, save :: initialized = .false.
!, get_equi_domain
!


  integer, parameter :: &
     EQ_GEQDSK  = 1, &
     EQ_DIVAMHD = 2, &
     EQ_JET     = 3

  integer :: ipanic = 0

  contains
!=======================================================================



!=======================================================================
! Load equilibrium configuration
!=======================================================================
  subroutine load_equilibrium_config (iu, iconfig)
  use run_control, only: Prefix
  integer, intent(in)  :: iu
  integer, intent(out) :: iconfig

  real(real64)         :: r(3)


! 1. read user configuration
  rewind (iu)
  read   (iu, Equilibrium_Input, end=1000)
  iconfig = 1
  write (6, *)
  write (6, 1001)


! set default values
  export_boundary => null()


! 2. load equilibrium data (if provided) ...............................
  if (Data_File .ne. '') call load_equilibrium_data


! 3. setup user defined magnetic axis (if provided) ....................
  ! 3.1. axisymmetric configuration
  if (R_axis > 0.d0) then
     call setup_magnetic_axis_2D (R_axis, Z_axis)

     ! set pol. magn. flux on axis
     r(1) = R_axis
     r(2) = Z_axis
     r(3) = 0.d0
     Psi_axis = get_Psi(r)
  endif

  ! 3.2. non-axisymmetric configuration
  if (Magnetic_Axis_File .ne. '') then
     Data_File = trim(Prefix)//Magnetic_Axis_File
     call load_magnetic_axis_3D (Data_File)

     ! pol. magn. flux not supported for non-axisymmetric configurations
     Psi_axis = 0.d0
  endif


! 4. set dependent variables ...........................................
  ! pol. magn. flux at separatrix
  if (R_sepx > 0.d0) then
     r(1) = R_sepx
     r(2) = Z_sepx
     r(3) = 0.d0
     Psi_sepx = get_Psi(r)
  endif


  return
 1000 iconfig = 0
 1001 format ('   - Equilibrium configuration:')
  end subroutine load_equilibrium_config
!=======================================================================



!=======================================================================
  subroutine load_equilibrium_data
  use run_control, only: Prefix
  use geqdsk
  use divamhd

  integer, parameter :: iu_scan = 17

  character*80 :: s


  Data_File = trim(Prefix)//Data_File

! determine equilibrium type ...........................................
  ! check if Data_Format has been set
  if (Data_Format .ne. '') then
     select case(Data_Format)
     case ('geqdsk')
        i_equi = EQ_GEQDSK
     case ('divamhd')
        i_equi = EQ_DIVAMHD
     case default
        write (6, *) 'error: ', Data_Format, ' is not a valid equilibrium type!'
        stop
     end select

  ! otherwise guess equilibrium type
  else
     open  (iu_scan, file=Data_file)
     read  (iu_scan, '(a80)') s
     if (s(3:5) == 'TEQ'  .or.  s(3:6) == 'EFIT') then
        i_equi = EQ_GEQDSK
     elseif (s(5:11) == 'jm   :=') then
        i_equi = EQ_JET
     else
        read  (iu_scan, '(a80)') s
        if (s(4:9) == 'File: ') then
           i_equi = EQ_DIVAMHD
        else
           i_equi = -1
        endif
     endif
     close (iu_scan)
  endif
! ... determine equilibrium type (done) ................................



! load equilibrium data
  select case (i_equi)
  case (EQ_GEQDSK)
     call geqdsk_load (Data_File, use_boundary, Current_Fix, Diagnostic_Level, Psi_axis, Psi_sepx)
  case (EQ_DIVAMHD)
     call divamhd_load (Data_File, Ip, Bt, R0)
  case default
     write (6, *) 'error: cannot determine equilibrium type!'
     stop
  end select
  call setup_equilibrium()

  end subroutine load_equilibrium_data
!=======================================================================



!=======================================================================
! Setup procedure pointers
!=======================================================================
  subroutine setup_equilibrium()
  use geqdsk
  use divamhd

  ! select case equilibrium
  select case (i_equi)
  case (EQ_GEQDSK)
     get_Bf_eq2D                   => geqdsk_get_Bf
     get_Psi                       => geqdsk_get_Psi
     get_DPsi                      => geqdsk_get_DPsi
     get_domain                    => geqdsk_get_domain
     equilibrium_provides_boundary => geqdsk_provides_boundary
     export_boundary               => geqdsk_export_boundary
     broadcast_equilibrium         => geqdsk_broadcast
  case (EQ_DIVAMHD)
     get_Bf_eq2D                   => divamhd_get_Bf
     get_Psi                       => divamhd_get_Psi
     get_DPsi                      => divamhd_get_DPsi
     get_domain                    => divamhd_get_domain
     broadcast_equilibrium         => divamhd_broadcast
  end select

  end subroutine setup_equilibrium
!=======================================================================



!=======================================================================
! Broadcast equilibrium data
!=======================================================================
  subroutine broadcast_mod_equilibrium()
  use parallel
  use geqdsk


  if (nprs == 1) return

  call broadcast_real_s (Psi_axis)
  call broadcast_real_s (Psi_sepx)
  call broadcast_inte_s (i_equi)
  call broadcast_magnetic_axis
  call wait_pe()



  if (mype > 0) call setup_equilibrium()
  call broadcast_equilibrium()

  end subroutine broadcast_mod_equilibrium
!=======================================================================



!=======================================================================
! Sample magnetic field vector
!=======================================================================
  function default_get_Bf(r) result(Bf)
  real*8, intent(in)  :: r(3)
  real*8              :: Bf(3)

  Bf = 0.d0
  if (ipanic > 0) then
     write (6, *) 'error: magnetic field function not defined!'
     stop
  endif

  end function default_get_Bf
!=======================================================================



!=======================================================================
! Sample poloidal magnetic flux at r=(R,Z [cm], phi [rad])
!===============================================================================
  function default_get_Psi(r) result(Psi)
  real*8, intent(in)  :: r(3)
  real*8              :: Psi

  Psi = 0.d0
  if (ipanic > 0) then
     write (6, *) 'error: poloidal magnetic flux function not defined!'
     stop
  endif

  end function default_get_Psi
!=======================================================================



!=======================================================================
! Sample normalized poloidal magnetic flux at r=(R,Z [cm], phi [rad])
!===============================================================================
  function get_PsiN(r) result(PsiN)
  real*8, intent(in)  :: r(3)
  real*8              :: PsiN

  PsiN = (get_Psi(r) - Psi_axis) / (Psi_sepx - Psi_axis)

  end function get_PsiN
!=======================================================================



!=======================================================================
! Sample (nR,nZ)-th derivative of poloidal magnetic flux at r=(R,Z [cm])
!=======================================================================
  function default_get_DPsi (r, nR, nZ) result(DPsi)
  real*8, intent(in)  :: r(2)
  integer, intent(in) :: nR, nZ
  real*8              :: DPsi

  DPsi = 0.d0
  if (ipanic > 0) then
     write (6, *) 'error: derivative of poloidal magnetic flux function not defined!'
     stop
  endif

  end function default_get_DPsi
!=======================================================================
  function get_DPsiN(r, nR, nZ) result(DPsiN)
  real*8, intent(in)  :: r(3)
  integer, intent(in) :: nR, nZ
  real*8              :: DPsiN

  DPsiN = get_DPsi(r(1:2), nR, nZ) / (Psi_sepx - Psi_axis)

  end function get_DPsiN
!=======================================================================
  function get_ePsi(r) result(ePsi)
  real(real64), intent(in) :: r(3)
  real(real64)             :: ePsi(2)

  real(real64) :: D


  ePsi(1) = get_DPsiN(r, 1, 0)
  ePsi(2) = get_DPsiN(r, 0, 1)
  D       = sqrt(sum(ePsi**2))

  if (D > 0.d0) ePsi    = ePsi / D

  end function get_ePsi
!=======================================================================



!=======================================================================
! Return poloidal angle [rad] at r=(R,Z [cm], phi [rad])
!=======================================================================
  function get_poloidal_angle(r) result(theta)
  real*8, intent(in) :: r(3)
  real*8             :: theta, Maxis(3)

  Maxis = get_magnetic_axis(r(3))
  theta = atan2(r(2) - Maxis(2), r(1) - Maxis(1))

  end function get_poloidal_angle
!=======================================================================



!=======================================================================
! Get cylindrical coordinates (R[cm], Z[cm], Phi[rad]) for flux
! coordinates (Theta[deg], PsiN, Phi[deg])
!=======================================================================
  function get_cylindrical_coordinates(y, ierr, r0) result(r)
  use iso_fortran_env
  use math
  implicit none

  real(real64), intent(inout)        :: y(3)
  integer,      intent(out)          :: ierr
  real(real64), intent(in), optional :: r0(3)
  real(real64)                       :: r(3)

  integer, parameter :: imax = 160
  real(real64), parameter :: tolerance = 1.d-10
  real(real64), parameter :: damping   = 0.9d0

  real(real64) :: dl, dpsi_dR, dpsi_dZ, dpsi_dl
  real(real64) :: M(3), Theta, PsiN, dr(2), beta

  integer :: i


  ierr  = 0

  ! set start point for approximation
  if (present(r0)) then
     r = r0
  else
     ! start near magnetic axis
     r(3)  = y(3) / 180.d0*pi
     M     = get_magnetic_axis(r(3))
     dr(1) = cos(y(1)/180.d0*pi)
     dr(2) = sin(y(1)/180.d0*pi)
     dl    = 0.2d0 * length_scale()

     r(1:2)= M(1:2) + dl*dr
     PsiN  = get_PsiN(r)
  endif


  do i=1,imax
     dpsi_dR = get_DPsiN(r, 1, 0)
     dpsi_dZ = get_DPsiN(r, 0, 1)
     dr(1) = cos(y(1)/180.d0*pi)
     dr(2) = sin(y(1)/180.d0*pi)
     dpsi_dl = dpsi_dR*dr(1) + dpsi_dZ*dr(2)

     beta    = y(2) - PsiN
     dr      = dr * beta / dpsi_dl * damping

     r(1:2)  = r(1:2) + dr
     PsiN    = get_PsiN(r)
     Theta   = get_poloidal_angle(r) / pi*180.d0
     if (Theta < 0) Theta = Theta + 360.d0

     if (abs(beta) <= tolerance) exit
  enddo
  ! update input parameters to match output coordinates
  y(1) = Theta
  y(2) = PsiN

  if (abs(beta) > tolerance) then
     ierr = 1
  endif

  end function get_cylindrical_coordinates
!=======================================================================



!=======================================================================
! Return boundaries [cm] of equilibrium domain
!=======================================================================
  subroutine default_get_domain (Rbox, Zbox)
  real*8, intent(out) :: Rbox(2), Zbox(2)

  Rbox = 0.d0
  Zbox = 0.d0
  if (ipanic > 0) then
     write (6, *) 'error: equilibrium domain not defined!'
     stop
  endif

  end subroutine default_get_domain
!=======================================================================



!=======================================================================
! boundary provided by equilibrium
!=======================================================================
  function default_equilibrium_provides_boundary() result(l)
  logical :: l

  l = .false.
  end function default_equilibrium_provides_boundary
!=======================================================================
! export axisymmetric boundary provided by equilibrium
!=======================================================================
!  subroutine export_PFC (S)
!  type(t_curve), intent(out) :: S
!  end subroutine export_PFC
!=======================================================================







!=======================================================================
! Find the X-point of a magnetic configuration, provided an initial guess X
!
! This subroutine applies the Newton-method for the iterative approximation of
! a critical point
!=======================================================================
  function find_X (X0, verbose) result(X)
  use bspline
  implicit none

  real(real64), intent(in)      :: X0(2)
  real(real64)                  :: X(2)
  logical, intent(in), optional :: verbose


  real(real64), parameter :: &
      gamma_0 = 1.d0, &
      delta   = 1.d-8
  integer, parameter :: nmax = 2000


  real(real64) :: xn(2), dx(2), dfdx, dfdy, H(2,2), Hdisc, dxmod, Rbox(2), Zbox(2)
  logical :: screen_output
  integer :: n


  ! setup screen output
  screen_output = .false.
  if (present(verbose)) screen_output = .true.


  ! initialize
  call get_domain (Rbox, Zbox)
  xn = X0
  if (screen_output) write (6, *) 'Initial guess for X-point: ', xn
  n  = 0

  approximation_loop: do
     ! check boundaries
     if (xn(1).lt.Rbox(1) .or. xn(1).gt.Rbox(2) .or. &
         xn(2).lt.Zbox(1) .or. xn(2).gt.Zbox(2)) then
        X = -1.d0
        return
     endif

     ! calculate the gradient
     dfdx = get_DPsi(xn, 1, 0)
     dfdy = get_DPsi(xn, 0, 1)

     ! calculate elements of the Hessian matrix
     H(1,1) = get_DPsi(xn, 2, 0)
     H(1,2) = get_DPsi(xn, 1, 1)
     H(2,2) = get_DPsi(xn, 0, 2)
     H(2,1) = H(1,2)
     Hdisc  = H(1,1) * H(2,2) - H(1,2)*H(2,1)
     if (Hdisc.eq.0) then
        if (ipanic == 0) then
           return
        else
           write (6, *) 'zero discriminant of Hessian matrix'
           write (6, *) 'in subroutine find_X'
           stop
        endif
     endif

     ! calculate increment
     dx(1)  =   H(2,2)*dfdx - H(1,2)*dfdy
     dx(2)  = - H(2,1)*dfdx + H(1,1)*dfdy

     xn     = xn - gamma_0*dx/Hdisc
     dxmod  = sqrt(sum(dx**2))/dabs(Hdisc)
     n      = n + 1

     if (dxmod .lt. delta) exit approximation_loop

     if (n.gt.nmax) exit approximation_loop
  enddo approximation_loop

  X = xn
  return
  end function find_X
!=======================================================================
  function find_lX() result(X)
  real(real64) :: X(2)

  real(real64) :: Rbox(2), Zbox(2), X0(2)


  call get_domain (Rbox, Zbox)
  ! try to find lower X at relative coordinate (1/3, 1/6) from lower left corner
  X0(1) = Rbox(1) + 1.d0/3.d0 * (Rbox(2)-Rbox(1))
  X0(2) = Zbox(1) + 1.d0/6.d0 * (Zbox(2)-Zbox(1))
  X     = find_X(X0)

  end function find_lX
!=======================================================================
  function find_uX() result(X)
  real(real64) :: X(2)

  real(real64) :: Rbox(2), Zbox(2), X0(2)


  call get_domain (Rbox, Zbox)
  ! try to find upper X at relative coordinate (1/3, 5/6) from lower left corner
  X0(1) = Rbox(1) + 1.d0/3.d0 * (Rbox(2)-Rbox(1))
  X0(2) = Zbox(1) + 5.d0/6.d0 * (Zbox(2)-Zbox(1))
  X     = find_X(X0)

  end function find_uX
!=======================================================================



!=======================================================================
  function length_scale () result(L)
  real(real64) :: L

  real(real64) :: M(3)


  L = 1.d0
  M = get_magnetic_axis(0.d0)
  if (M(1) > 0.d0) L = M(1)

  end function length_scale
!=======================================================================












!=======================================================================
  function pol_flux(r) result(psi)
  real*8, intent(in) :: r(3)
  real*8             :: psi

  end function pol_flux
!=======================================================================


!=======================================================================
  subroutine Bf_pol_sub (n, s, y, f)
  integer, intent(in) :: n
  real*8, intent(in)  :: s, y(n)
  real*8, intent(out) :: f(n)

  ! n = 2, y(1) = R, y(2) = Z
  end subroutine Bf_pol_sub
!=======================================================================

end module equilibrium
