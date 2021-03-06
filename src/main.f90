program main
  use iso_fortran_env
  use parallel
  use run_control
  use bfield
  use equilibrium
  use boundary
  implicit none

  real(real64) :: t1, t2, t3

  ! Initialize parallel execution (using MPI)
  call initial_parallel()
  if (firstP) then
     write (6, 1000)
     write (6, *) 'Running FLARE ('//trim(TAG)//')'
     if (nprs.gt.1) then
        write (6, *) 'on ', nprs, ' processors'
     endif
     write (6, *)
  endif


  call cpu_time(t1)
  call load_run_control()

  call setup_bfield_configuration()

  call setup_boundary()

  call cpu_time(t2)
  call run_control_main()
  call cpu_time(t3)
  if (firstP) then
     write (6, *)
     write (6, 1001) t2-t1
     write (6, 1002) t3-t2
     write (6, *)
  endif

  call finished_bfield()
  call finished_parallel()
 1000 format ('========================================================================')
 1001 format (1x,'Time taken for initialization: ',f10.3,' seconds')
 1002 format (1x,'Time taken for computation:    ',f10.3,' seconds')
end program main
