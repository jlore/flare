!===============================================================================
! Generate grid for magnetic footprint calculation
!
! Input (taken from run control file):
!    Grid_File          filename for grid to be generated
!
!    surf_id            select boundary surface on which the grid is generated
!                       NOT IMPLEMENTED YET (set to 1)
!
!    R_start, R_end     Reference markers on boundary surface

!    N_sym              Toroidal extend for grid on axisymmetric surface: 360 deg / N_sym
!
!    Phi_output         Reference marker (toroidal direction) on surface
!                       For axisymmetric surfaces: lower coordinate for toroidal domain
!
!    offset             Radial offset (on left hand side) from boundary surface
!
!    N_theta, N_phi     Polidal and toroidal resolution
!
!    Output_Format = IJ
!        I = 0          standard output
!        I > 1          add direction of normal vector for axisymmetric surfaces
!        J              Plotting coordinate:
!                       0: length along surface contour segment in RZ-plane
!                       1: R-coordinate
!                       2: Z-coordinate
!                       3: relative length along surface contour segment in RZ-plane
!                       4: length along FULL surface contour in RZ-plane
!                       5: relative length along FULL surface contour in RZ-plane
!===============================================================================
subroutine footprint_grid
  use iso_fortran_env
  use run_control, only: Grid_File, Output_File, Output_Format, N_theta, N_phi, offset, &
                         R_start, R_end, Phi_Output, N_sym
  use parallel
  implicit none

  integer, parameter :: iu = 32, iu2 = 33

  ! user input for grid generation
  integer :: &
     slice_phi = -1

  namelist /Grid_Input/ slice_phi



  if (firstP) then
     write (6, *) 'Generate footprint grid, output in: ', adjustl(trim(Output_File)), &
                  ', ', adjustl(trim(Grid_File))
     write (6, *)
  else
     return
  endif

  open  (iu, file='run_input')
  read  (iu, Grid_Input, end=1000)
 1000 close (iu)

  call footprint_grid_axi(1, R_start, R_end, offset)
  !call footprint_grid_Q(1)
  contains
!=======================================================================
  subroutine footprint_grid_axi (iele, R_start, R_end, offset)
  use curve2D
  use boundary
  use run_control, only: Debug

  integer, intent(in)      :: iele
  real(real64), intent(in) :: R_start, R_end, offset

  integer, parameter :: iu = 99

  type(t_curve) :: C, Ctmp1, Ctmp2
  real(real64)  :: t, t1, x(2), x1(2), xn(2), L, L0, L1, alphan, phii
  integer :: i, j


  ! check input
  if (R_start >= R_end) then
     write (6, *) 'error: R_start < R_end required for footprint grid!'
     stop
  elseif (R_end > 1.d0) then
     write (6, *) 'error: R_end must not exceed 1!'
     stop
  elseif (R_start < 0.d0) then
     write (6, *) 'error: R_start must not be smaller than 0!'
     stop
  endif
  if (iele < 1  .or.  iele > n_axi) then
     write (6, *) 'error: 1 <= iele <= n_axi required in footprint_grid!'
     stop
  endif


  ! split of relevant segments
  call S_axi(iele)%setup_length_sampling()
  call S_axi(iele)%split3(R_start, R_end, Ctmp1, C, Ctmp2)
  if (Debug) then
     call C%plot(filename='footprint_base.plt')
  endif


  ! shift footprint base off of surface
  call C%left_hand_shift(offset)


  call C%setup_length_sampling()
  L0 = C%length()
  L1 = S_axi(iele)%length()

  open  (iu, file=Grid_File)
  write (iu, 2000)
  write (iu, 2001) N_theta
  write (iu, 2002) N_phi

  ! 1. write coordinates along boundary profile
  do j=0,N_theta-1
     t = 1.d0 * j / (N_theta-1)
     call C%sample_at (t, x, x1)

     ! select diagnostic coordinate used for plotting (3rd column)
     select case (mod(Output_Format,10))
     case (0)	! length along surface in RZ-plane
        L = t * L0
     case (1)
        L = x(1) ! R-coordinate
     case (2)
        L = x(2) ! Z-coordinate
     case (3)	! relative length along surface profile in RZ-plane
        L = t
     case (4)	! full surface contour (absolute length)
        t1 = R_start + t * (R_end - R_start)
        L  = t1 * L1
     case (5)	! full surface contour (relative length)
        t1 = R_start + t * (R_end - R_start)
        L  = t1
     end select

     ! default grid
     if (Output_Format.lt.10) then
        write (iu, 3003) x, L
     ! extended grid with normal vector
     else
        ! right handed normal vector
        xn(1)  = - x1(2)
        xn(2)  =   x1(1)
        alphan = atan2(xn(2), xn(1))

        write (iu, 3004) x, L, alphan
     endif
  enddo

  ! 2. write coordinates in toroidal direction
  do i=0,N_phi-1
     phii = Phi_output + 360.d0 / N_sym * i / (N_phi-1)
     write (iu, 3002) phii
  enddo
  close (iu)

 2000 format ('# grid_id = 223     (toroidal RZ grid)')
 2001 format ('# R, Z resolution:   n_RZ    =  ',i10)
 2002 format ('# phi resolution:    n_phi   =  ',i10)
 3002 format (1e18.10)
 3003 format (2e18.10,2x,f12.7)
 3004 format (2e18.10,2x,f8.3,e18.10)
  end subroutine footprint_grid_axi
!=======================================================================
  subroutine footprint_grid_Q (iele)
  use boundary
  use mesh_spacing
  use math
  use equilibrium
  use quad_ele
  use grid
  use curve2D
  integer, intent(in) :: iele

  type(t_grid)     :: G_sample, G_plot
  type(t_quad_ele) :: S
  type(t_curve)    :: C
  real(real64) :: tau, xi, phi, theta, r(3), d(2)
  integer      :: i, iA, iB, j, n, ig


  if (iele < 1  .or.  iele > n_quad) then
     write (6, *) 'error: surface element ', iele, ' does not exist!'
     stop
  endif
  write (6, 1000) iele
 1000 format (3x,'- for quadrilateral surface ', i2)
  select case (Output_Format)
  case(ANGLE)
     write (6, 1001)
  case(DISTANCE)
     write (6, 1002)
  case default
     write (6, *) 'error: undefined output format ', Output_Format
     stop
  end select
 1001 format (3x,'- Using poloidal angle as reference coordinate')
 1002 format (3x,'- Using relative position in poloidal direction as reference coordinate')



  ! select slice
  if (slice_phi >= 0) then
     if (slice_phi > n_phi) then
        write (6, *) 'error: cannot extract slice ', slice_phi, '/', n_phi
        stop
     endif

     iA = slice_phi
     iB = slice_phi
  else
     iA = 0
     iB = n_phi
  endif


  ! copy surface (to be modified locally)
  call S%new(S_quad(iele)%n_phi, S_quad(iele)%n_RZ, S_quad(iele)%n_sym)
  S%phi = S_quad(iele)%phi
  S%R   = S_quad(iele)%R
  S%Z   = S_quad(iele)%Z


  ! shrink surface (because starting points for field line tracing must not lay on the boundary surface)
!  do i=0,S%n_phi
!     r(3) = S%phi(i)
!     r    = get_magnetic_axis(r(3))
!     do j=0,S%n_RZ
!        d(1)     = S%R(i,j) - r(1)
!        d(2)     = S%Z(i,j) - r(2)
!
!        S%R(i,j) = r(1) + (1.d0 - 1.d-3) * d(1)
!        S%Z(i,j) = r(2) + (1.d0 - 1.d-3) * d(2)
!     enddo
!  enddo
  !call S%left_hand_shift(1.d-3)


  n = (iB-iA+1) * (n_theta+1)
  ! output file for cylindrical coordinates
  !open  (iu, file=Grid_File)
  !write (iu, 1000)
  !write (iu, 1001) (n_phi+1) * (n_theta+1)
  call G_sample%new(CYLINDRICAL, UNSTRUCTURED, 0, n)

  ! output file for local coordinates
  !open  (iu2, file=Output_File)
  !write (iu2, 2000)
  !write (iu2, 2001) n_phi+1
  !write (iu2, 2002) n_theta+1
  call G_plot%new(LOCAL, UNSTRUCTURED, 3, n)

  call S%setup_coefficients()
  ig = 0
  do i=iA,iB
     tau = Equidistant%node(i, n_phi)
     phi = S_quad(iele)%sample_phi(tau)
     C   = S_quad(iele)%slice(phi)

     call C%left_hand_shift(offset)
     call C%setup_length_sampling()

     do j=0,n_theta
        ig = ig + 1
        xi = Equidistant%node(j, n_theta)

        r(3) = phi
        call C%sample_at(xi, r(1:2))
!        r  = S%sample(tau, xi)
        G_sample%x(ig,:) = r
        !write (iu, *) r

!        phi   = r(3) / pi * 180.d0
        theta = get_poloidal_angle(r) / pi * 180.d0
        if (theta < 0) theta = theta + 360.d0
        !write (iu2, *) phi, theta
        G_plot%x(ig,1) = phi / pi * 180.d0
        select case (Output_Format)
        case(ANGLE)
           G_plot%x(ig,2) = theta
        case(DISTANCE)
           G_plot%x(ig,2) = xi
        end select
     enddo

     call C%destroy()
  enddo
  !close (iu)
  !close (iu2)

  call G_sample%store(filename=Grid_File)
  call G_plot%store(filename=Output_File, header='local coordinates: Phi[deg], Theta[deg]')

! 1000 format ('# grid_id = 9       (cylindrical coordinates: R[cm], Z[cm], Phi[rad])')
! 1001 format ('# grid resolution:   n_RZphi =  ',i10)
! 2000 format ('# grid_id = 20      (local coordinates: Phi[deg], Theta[deg]')
! 2001 format ('# Toroidal angle     n_phi   =  ',i10)
! 2002 format ('# Poloidal angle     n_theta =  ',i10)
  end subroutine footprint_grid_Q
!=======================================================================
end subroutine footprint_grid
