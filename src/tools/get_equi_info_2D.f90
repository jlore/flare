!===============================================================================
! Write equilibrium information
!===============================================================================
subroutine get_equi_info_2D
  use iso_fortran_env
  use magnetic_axis
  use equilibrium, only: get_domain, find_hyperbolic_points, get_Psi, &
                         equilibrium_info, Psi_axis, Psi_sepx, i_equi, EQ_AMHD
  use boundary
  use parallel
  implicit none

  integer, parameter :: iu = 42


  character(len=120) :: fout, sboundary
  character(len=8)   :: cid
  real(real64)       :: Rbox(2), Zbox(2), r(3), Psi, Ip_int, Bpol, betaP, betaT
  integer            :: i, j, nR, nZ


  if (firstP) then
     write (6, *) 'Write equilibrium information'
     write (6, *)
  else
     return
  endif


  call get_domain (Rbox, Zbox)

  call find_hyperbolic_points()

  ! magnetic axis
  r(3) = 0.d0
  r = get_magnetic_axis(r(3))
  write (6, 9001) r(1:2)
  write (6, *)
  open  (iu, file='magnetic_axis.dat')
  write (iu, *) r(1:2)
  close (iu)


  ! write grid with sample locations
  nR = 128
  nZ = 128
  fout = 'equi_info.grid'
  open  (iu, file=fout)
  write (iu, 1000)
  write (iu, 1001) nR
  write (iu, 1002) nZ
  write (iu, 1003) 0.d0
  do i=0,nR-1
     r(1) = Rbox(1) + (Rbox(2)-Rbox(1)) * i / (nR-1)
     write (iu, 1004) r(1)
  enddo
  do j=0,nZ-1
     r(2) = Zbox(1) + (Zbox(2)-Zbox(1)) * j / (nZ-1)
     write (iu, 1004) r(2)
  enddo
  close (iu)


  ! write normalized poloidal magnetic flux
  fout = 'equi_info.data'
  r(3) = 0.d0
  open  (iu, file=fout)
  do j=0,nZ-1
  do i=0,nR-1
     r(1) = Rbox(1) + (Rbox(2)-Rbox(1)) * i / (nR-1)
     r(2) = Zbox(1) + (Zbox(2)-Zbox(1)) * j / (nZ-1)
     Psi = get_Psi(r)
     Psi = (Psi - Psi_axis) / (Psi_sepx - Psi_axis)
     write (iu, 1004) Psi
  enddo
  enddo
  close (iu)


  ! write boundary data
  sboundary = 'boundary=['
  do i=1,n_axi
     write (cid, '(i8)') i
     fout      = 'boundary_'//trim(adjustl(cid))//'.txt'
     sboundary = trim(sboundary)//"'"//trim(fout)//"'"
     if (i < n_axi) sboundary = trim(sboundary)//', '

     open  (iu, file=fout)
     do j=0,S_axi(i)%n_seg
        write (iu, *) S_axi(i)%x(j,1:2)
     enddo
     close (iu)
  enddo
  sboundary = trim(sboundary)//'], $'


  ! write plot script
  open  (iu, file='plot_equi_info.sh')
  write (iu, 2000)
  write (iu, 2006)
  write (iu, 2007)
  write (iu, 2008) sboundary
  write (iu, 2009)
  write (iu, 2010)
  close (iu)


  ! equilibrium type specific information
  if (associated(equilibrium_info)) call equilibrium_info()


  ! calculate plasma current from plasma surface integral
  call Ip_info (1.d-4, 400, Ip_int, Bpol)
  write (6, 9002) Ip_int

  ! calculate plasma beta
  if (i_equi == EQ_AMHD) then
  call beta_info(100, Bpol, betaP, betaT)
  write (6, 9003) betaT
  write (6, 9004) betaP
  endif

 9001 format (3x,'- Magnetic axis is at: ',2f10.3)
 9002 format (3x,'- Plasma current [MA] from surface integration: ', f10.5)
 9003 format (3x,'- Toroidal plasma beta:                         ', f10.5)
 9004 format (3x,'- Poloidal plasma beta:                         ', f10.5)
 1000 format ('# grid_id = 233     (regular RZ grid)')
 1001 format ('# R resolution:      n_R     =  ',i8)
 1002 format ('# Z resolution:      n_Z     =  ',i8)
 1003 format ('# phi position:      phi     =  ',f7.2)
 1004 format (e18.10)

 2000 format ('#!/bin/bash')
 2006 format ('idl << EOF')
 2007 format ("plot_data, 'equi_info.grid', 'equi_info.data', 0, zrange=[0,2], clevels=[0.9, 1.0, 1.1], $")
 2008 format (a120)
 2009 format ("ps_plot='equi_info.eps'")
 2010 format ('EOF')
end subroutine get_equi_info_2D
!===============================================================================



!===============================================================================
! calculate plasma current from plasma surface integral
!===============================================================================
subroutine Ip_info(delta_PsiN, n_sample, Ip, Bpolbar)
  use iso_fortran_env
  use equilibrium, only: get_cylindrical_coordinates, get_Bf_eq2D
  use flux_surface_2D
  use math
  use run_control, only: Debug
  implicit none

  real(real64), intent(in)  :: delta_PsiN
  integer,      intent(in)  :: n_sample
  real(real64), intent(out) :: Ip, Bpolbar

  type(t_flux_surface_2D)  :: F
  real(real64)       :: L, dl, Bpol, Bpolint, Bf(3), xi, r(3), y(3)
  integer            :: i, ierr


  ! get point just inside separatrix on inner equatorial plane
  y(1) = 180.d0
  y(2) = 1.d0 - delta_PsiN
  y(3) = 0.d0
  r    = get_cylindrical_coordinates(y, ierr)
  if (ierr > 0) write (6, *) 'warning: reference point at PsiN = ', y(2), ' exceeds required accuracy!'

  ! generate "last closed flux surface"
  call F%generate_closed(r(1:2), RIGHT_HANDED)
  if (Debug) call F%plot(filename='lcfs.plt')
  call F%setup_length_sampling()
  L       = F%length()
  write (6, 9010)
  write (6, 9011) L / 1.d2
  write (6, 9012) F%area() / 1.d4
  write (6, 9013) F%surface() / 1.d4
  write (6, 9014) F%volume() / 1.d6
  write (6, *)


  dl      = L / n_sample
  Bpolint = 0.d0
  do i=0,n_sample-1
     xi      = 1.d0 * i / n_sample
     call F%sample_at(xi, r(1:2))

     Bf      = get_Bf_eq2D(r)
     Bpol    = sqrt(Bf(1)**2 + Bf(2)**2)
     Bpolint = Bpolint + Bpol * dl
  enddo
  Bpolint = Bpolint * 1.d-4 * 1.d-2	! Gauss cm -> T m
  Ip      = Bpolint / (4.d-1 * pi)
  Bpolbar = Bpolint / (L/1.d2)

 9010 format(3x,'- Plasma boundary:')
 9011 format(8x,'poloidal cirumference [m]     = ', f10.4)
 9012 format(8x,'poloidal cross-section [m**2] = ', f10.4)
 9013 format(8x,'surface area [m**2]           = ', f10.4)
 9014 format(8x,'plasma volume [m**3]          = ', f10.4)
end subroutine Ip_info
!===============================================================================



!===============================================================================
! Calculate plasma beta
!===============================================================================
subroutine beta_info(n_R, Bpol, betaP, betaT)
  use iso_fortran_env
  use equilibrium, only: get_cylindrical_coordinates, get_pressure, Psi_axis, Psi_sepx, Bt
  use flux_surface_2D
  use math
  implicit none
  integer,      intent(in)  :: n_R
  real(real64), intent(in)  :: Bpol
  real(real64), intent(out) :: betaP, betaT

  type(t_flux_surface_2D)  :: F

  real(real64) :: y(3), r(3), area, Psi, dPsi, psi1, P, V, dV, delta_Psi
  integer :: i, ierr


  P         = 0.d0
  V         = 0.d0
  delta_Psi = 1.d0 / n_R
  do i=0,n_R-1
     Psi  = (i + 0.5d0) * delta_Psi
     ! find coordinates in real space for point i
     y(1) = 180.d0
     y(2) = Psi
     y(3) = 0.d0
     r    = get_cylindrical_coordinates(y, ierr)
     if (ierr > 0) write (6, *) 'warning: reference point at PsiN = ', y(2), ' exceeds required accuracy!'

     ! generate flux surface
     call F%generate_closed(r(1:2), RIGHT_HANDED)
     call F%setup_length_sampling()
     call F%surface_analysis(area, dPsi)


     dV = area / dPsi * delta_Psi
     psi1 = Psi_axis + Psi * (Psi_sepx - Psi_axis)
     P  = P + dV * get_pressure(psi1)
     V  = V + dV

     !write (98, *) Psi, V, F%volume()
     !write (99, *) Psi, get_pressure(psi1), psi1
     !write (97, *) Psi, area, F%volume(), dPsi
  enddo
  P     = P / V
  betaP = 2 * 4.d-7*pi * P / Bpol**2
  betaT = 2 * 4.d-7*pi * P / Bt**2
  !write (6, *) 'volume = ', V
  !write (6, *) Bt, Bpol

end subroutine beta_info
!===============================================================================
