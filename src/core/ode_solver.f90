!===============================================================================
! Solves system of first order ODEs
!
! dy/ds = f(s, y) for y(s=0) = y0
!
! the right hand side f needs to be supplied:
!     subroutine f_sub (n, s, y, f)
!        integer, intent(in) :: n
!        real*8, intent(in)  :: s, y(n)
!        real*8, intent(out) :: f(n)
!     end subroutine f_sub
!===============================================================================

module ode_solver
  implicit none

  integer, parameter :: NM_Euler                 = 1
  integer, parameter :: NM_RungeKutta4           = 2
  integer, parameter :: NM_AdamsBashforth4       = 3
  integer, parameter :: NM_AdamsBashforthMoulton = 4
  integer, parameter :: NM_DLSODE                = 5

  type t_ODE
     ! dimension, i.e. number of first order ODEs
     integer                           :: n

     ! step size
     real*8                            :: ds

     ! current state
     real*8, dimension(:), allocatable :: yc
     real*8                            :: sc


     ! internal data ...............................
     ! for Adams-Bashforth
     real*8, dimension(:,:), allocatable :: ax, bx

     ! for DLSODE
     real*8, dimension(:), allocatable :: rwork
     integer, dimension(:), allocatable :: iwork

     real*8 :: t, tout, rtol, atol
     integer :: nrwork, niwork, mf, istate
     !..............................................


     ! function vector f
     procedure(f_ifce), pointer, nopass :: evaluate_f

     ! perform one integration step dt
     procedure(step_ifce), pointer :: next_step

     contains
     procedure :: init_ODE => initialize_ODE
  end type t_ODE


  ! interfaces for external function f and for integrator
  abstract interface
     subroutine f_ifce (n, s, y, f)
        integer, intent(in) :: n
        real*8, intent(in)  :: s, y(n)
        real*8, intent(out) :: f(n)
     end subroutine f_ifce

     function step_ifce (this)
        import :: t_ODE
        class(t_ODE), intent(inout) :: this
        real*8 :: step_ifce(this%n)
     end function step_ifce
  end interface


  contains
!-----------------------------------------------------------------------


!-----------------------------------------------------------------------
! initialize system of ordinary differential equations
!
! Input:
!   n		number of equations
!   xinit	initial value
!   ds		numerical step size
!   f		function to be integrated
!   isolver	method used for intergation
!-----------------------------------------------------------------------
  subroutine initialize_ODE (this, n, yinit, ds, f, isolver, silent_mode)
  class(t_ODE)             :: this
  integer, intent(in)      :: n
  real*8, intent(in)       :: yinit(n), ds
  external                 :: f
  integer, intent(in)      :: isolver
  logical, intent(in), optional :: silent_mode

  logical :: verbose

  verbose = .false.
  if (present(silent_mode)) then
     verbose = .not. silent_mode
  endif


  if (verbose) write (6, *) 'initializing system with ', n, 'first order ODEs...'
  this%n = n
  if (verbose) write (6, *) 'initial values are: ', yinit
  if (allocated(this%yc)) deallocate (this%yc)
  allocate (this%yc(n))
  this%ds = ds
  this%yc = yinit
  this%sc = 0.d0

  this%evaluate_f => f


  select case(isolver)
  case (NM_Euler)
     this%next_step       => Euler_method
  case (NM_RungeKutta4)
     this%next_step       => RK4_method
  case (NM_AdamsBashforth4)
     call init_AB4_method(this)
     this%next_step       => AB4_method
  case (NM_AdamsBashforthMoulton)
     call init_ABM_method(this)
     this%next_step       => ABM_method
  case (NM_DLSODE)
     call init_DLSODE(this)
     this%next_step       => DLSODE_couple
  case default
     write (6, *) 'integration method ', isolver, ' is not supported!'
     stop
  end select

  end subroutine initialize_ODE
!=======================================================================



!=======================================================================
! explicit Euler method
!=======================================================================
  function Euler_method (this)
  class(t_ODE), intent(inout) :: this
  real*8 :: Euler_method(this%n)

  real*8 :: f(this%n), dy(this%n)

  call this%evaluate_f(this%n, this%sc, this%yc, f)
  dy = f * this%ds

  this%sc      = this%sc + this%ds
  this%yc      = this%yc + dy
  Euler_method = this%yc

  end function Euler_method
!=======================================================================



!=======================================================================
! 4th order Runge-Kutta method
!=======================================================================
  function RK4_method (this)
  class(t_ODE), intent(inout) :: this
  real*8 :: RK4_method(this%n)

  real*8 :: y0(this%n), dy0(this%n), y1(this%n), dy1(this%n), &
            y2(this%n), dy2(this%n), y3(this%n), dy3(this%n), &
            f(this%n), s

  ! step 1
  y0 = this%yc; s = this%sc
  call this%evaluate_f(this%n, s, y0, f)
  dy0 = f * this%ds

  ! step 2
  y1 = y0 + 0.5d0 * dy0; s = s + 0.5d0 * this%ds
  call this%evaluate_f(this%n, s, y1, f)
  dy1 = f * this%ds

  ! step 3
  y2 = y0 + 0.5d0 * dy1
  call this%evaluate_f(this%n, s, y2, f)
  dy2 = f * this%ds

  ! step 4
  y3 = y0 + dy2; s = s + 0.5d0 * this%ds
  call this%evaluate_f(this%n, s, y3, f)
  dy3 = f * this%ds

  ! collect
  this%yc    = y0 + (dy0 + 2.d0*dy1 + 2.d0*dy2 + dy3) / 6.d0
  this%sc    = s
  RK4_method = this%yc

  end function RK4_method
!=======================================================================



!=======================================================================
! 4-step Adams-Bashforth method
!=======================================================================
  subroutine init_AB4_method(this)
  class(t_ODE), intent(inout) :: this

  real*8  :: y(this%n), y0(this%n), dy(this%n,5), f(this%n), s0
  real*8  :: t1(this%n), t3(this%n), t4(this%n)
  integer :: ik


  if (allocated(this%ax)) deallocate (this%ax)
  allocate (this%ax(this%n,6))

  y0      = this%yc
  s0      = this%sc
  call this%evaluate_f(this%n, this%sc, this%yc, f)
  dy(:,5) = f
  
  this%ds = -this%ds
  do ik=4,1,-1
     y = RK4_method(this)
     call this%evaluate_f(this%n, this%sc, this%yc, f)
     dy(:,ik) = f
  enddo
  this%ds = -this%ds
  this%yc = y0
  this%sc = s0

  t4    = dy(:,4) - dy(:,3)
  t3    = dy(:,3) - dy(:,2)
  t1    = t4 - t3

  this%ax(:,1) =                dy(:,5)
  this%ax(:,2) = this%ax(:,1) - dy(:,4)
  this%ax(:,3) = this%ax(:,2) - t4
  this%ax(:,4) = this%ax(:,3) - t1
  this%ax(:,5) = this%ax(:,4) - t1 + t3 - dy(:,2) + dy(:,1)

  end subroutine init_AB4_method
!=======================================================================
  function AB4_method (this)
  class(t_ODE), intent(inout) :: this
  real*8 :: AB4_method(this%n)

  real*8, parameter :: &
     c1 = 0.5d0, &
     c2 = 0.416666666666666666666666666667d0, &
     c3 = 0.375d0, &
     c4 = 0.348611111111111111111111111111d0

  integer :: i
  real*8  :: dy(this%n), f(this%n), s


  s       = this%sc
  do i=5,1,-1
     this%ax(:,i+1) = this%ax(:,i)
  enddo

  this%yc = this%yc + this%ds * &
     (this%ax(:,2) + c1*this%ax(:,3) + c2*this%ax(:,4) + c3*this%ax(:,5) + c4*this%ax(:,6))
  this%sc = s + this%ds

  call this%evaluate_f(this%n, s, this%yc, f)
  this%ax(:,1) = f

  do i=2,6
     this%ax(:,i) = this%ax(:,i-1) - this%ax(:,i)
  enddo

  AB4_method = this%yc

  end function AB4_method
!=======================================================================



!=======================================================================
! 5-step Adams-Moulten method (corrector) + 4-step Adams-Bashforth method (predictor)
!=======================================================================
  subroutine init_ABM_method (this)
  class(t_ODE), intent(inout) :: this

  call init_AB4_method (this)
  if (allocated(this%bx)) deallocate (this%bx)
  allocate (this%bx(this%n,6))

  end subroutine init_ABM_method
!=======================================================================
  function ABM_method (this)
  class(t_ODE), intent(inout) :: this
  real*8 :: ABM_method(this%n)

  real*8, parameter :: &
     c1 = -0.5d0, &
     c2 = -1.d0/12.d0, &
     c3 = -1.d0/24.d0, &
     c4 = -19.d0/720.d0, &
     c5 = -3.d0/160.d0

  real*8  :: y(this%n), y0(this%n), f(this%n)
  integer :: i

  ! predictor step
  y0 = this%yc
  y  = AB4_method(this)

  ! corrector step
  this%yc = y0 + this%ds * ( &
      this%ax(:,1) + c1*this%ax(:,2) + c2*this%ax(:,3) + c3*this%ax(:,4) + c4*this%ax(:,5) &
      + c5*this%ax(:,6)    )
  ! update coefficients
  call this%evaluate_f(this%n, this%sc, this%yc, f)
  this%bx(:,1) = f
  do i=2,6
     this%bx(:,i) = this%bx(:,i-1) - this%ax(:,i-1) + this%ax(:,i)
  enddo
  this%ax = this%bx

  ABM_method = this%yc
  end function ABM_method
!=======================================================================



!=======================================================================
! DLSODE (Livermore Solver for Ordinary Differential Equations)
!=======================================================================
  subroutine JAC_DLSODE (neq, t, y, ml, mu, pd, nrowpd)
  integer, intent(in)           :: neq, ml, mu, nrowpd
  double precision, intent(in)  :: t, y(neq)
  double precision, intent(out) :: pd(nrowpd,neq)

  ! version for full Jacobian (ml and mu are ignored)
  ! nrowpd = neq
  ! PD(i,j) = df(i)/dy(j)
  pd = 0.d0

  end subroutine JAC_DLSODE
!=======================================================================
  subroutine init_DLSODE (this)
  class(t_ODE), intent(inout) :: this

  integer :: neq

  this%mf = 10
  this%istate = 1

  this%rtol = 1.d-9
  this%atol = 1.d-9

  if (allocated(this%rwork)) deallocate(this%rwork)
  neq = 3
  if (this%mf.eq.10) this%nrwork = 20 + 16*neq
  if (this%mf.eq.21) this%nrwork = 20 +  9*neq + neq**2
  allocate (this%rwork(this%nrwork))

  if (allocated(this%iwork)) deallocate(this%iwork)
  if (this%mf.eq.10) this%niwork = 20
  if (this%mf.eq.21) this%niwork = 20 + neq
  allocate (this%iwork(this%niwork))

  end subroutine init_DLSODE
!=======================================================================
  function DLSODE_couple(this)
  class(t_ODE), intent(inout) :: this
  real*8 :: DLSODE_couple(this%n)


  call DLSODE (this%evaluate_f, 3, this%yc, this%sc, this%sc+this%ds, &
               1, this%rtol, this%atol, 1, this%istate, 0, this%rwork, &
               this%nrwork, this%iwork, this%niwork, JAC_DLSODE, this%mf)

  ! check istate
  if (this%istate.ne.2) then
     write (6, *) 'istate = ', this%istate
     stop
  endif

  DLSODE_couple = this%yc
  end function DLSODE_couple
!=======================================================================


end module ode_solver
