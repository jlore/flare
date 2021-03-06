module run_control
  use parallel
  implicit none
  include '../config.h'

  integer, parameter :: &
     ZERO_TOLERANCE = 0, &
     INERVOUS   =  1, &
     IMODERATE  = 10, &
     IDONTPANIC = 42

  ! user defined variables
  character(len=120) :: &
     Machine        = ' ', &        ! select input directory (1st part)
     Configuration  = ' ', &        ! select input directory (2nd part)
     Run_Type       = ' ', &        ! select sub-program to execute
     Label          = '', &
     Output_File    = 'output.txt', &
     Grid_File      = 'grid.dat'

  real*8 :: &
     x_start(3)     = 0.d0, &       ! initial position for field line tracing
     Trace_Step     = 1.d0, &       ! step size for field line tracing
     Limit          = 2.d4, &       ! maximum distance for field line tracing (in one direction)
     R_start        = 0.d0, &       ! radial start- and
     R_end          = 0.d0, &       ! end position (e.g. for Poincare plots)
     Z_start        = 0.d0, &       ! vertical start- and
     Z_end          = 0.d0, &       ! end position (e.g. for Poincare plots)
     Phi_output     = 0.d0, &       ! Reference plane for Poincare plots
     Theta(2)       = 0.d0, &
     Psi(2)         = 0.d0, &
     offset         = 1.d-2


  integer :: &
     N_steps        = 0, &          ! Number of discrete steps
     N_points       = 0, &          ! Max. number of points for Poincare plots
     N_sym          = 1, &          ! Toroidal symmetry factor (for Poincare plots)
     N_mult         = 1, &          !
     N_theta        = 0, &          ! Resolution in poloidal direction
     N_psi          = 1, &          ! Resolution in radial direction
     N_phi          = 1, &          ! Resolution in toroidal direction
     N_R            = 1, &          ! Resolution in R direction
     N_Z            = 1, &          ! Resolution in Z direction
     Run_Level(2)   = 0, &
     Trace_Method   = 3, &          ! Method for field line tracing (see module fieldline)
     Trace_Coords   = 2, &          ! Coordinate system for field line tracing (see module fieldline)
     Input_Format   = 1, &
     Output_Format  = 1, &          ! See individual tools
     Spline_Order   = 5, &
     Panic_Level    = IMODERATE


  logical :: &
     Debug          = .false.



  ! internal variables
  character*120 :: Prefix, &
                   Bfield_input_file


  namelist /RunControl/ &
     Machine, Configuration, &
     Run_Type, Output_File, Label, Grid_File, Input_Format, Output_Format, Panic_Level, &
     x_start, Trace_Step, Trace_Method, Trace_Coords, N_steps, Limit, &
     R_start, R_end, Z_start, Z_end, Phi_output, N_points, N_sym, N_mult, &
     Theta, Psi, N_theta, N_psi, N_phi, N_R, N_Z, offset, &
     Spline_Order, Run_Level, &
     Debug

  contains
!=======================================================================


!=======================================================================
  subroutine load_run_control()
  use math

  integer, parameter :: iu = 23
  character*255      :: homedir


  ! load run control on first processor
  if (firstP) then
     open  (iu, file='run_input', err=5000)
     read  (iu, RunControl, end=5000)
     close (iu)

     if (Machine .ne. ' ') then
        write (6, *) 'Machine:                ', trim(Machine)
        write (6, *) 'Configuration:          ', trim(Configuration)
        call getenv("HOME", homedir)
        Prefix = trim(homedir)//'/'//base_dir//'/'//trim(Machine)//'/'// &
                 trim(Configuration)//'/'
     else
        Prefix = './'
     endif

     Bfield_input_file = trim(Prefix)//'bfield.conf'


     if (Trace_Coords == 3) then
        Trace_Step = Trace_Step / 180.d0 * pi
     endif
  endif


  ! broadcase data to other processors
  call wait_pe()
  call broadcast_char   (Run_Type   , 120)
  call broadcast_char   (Grid_File  , 120)
  call broadcast_char   (Output_File, 120)
  call broadcast_real   (x_start    ,   3)
  call broadcast_real_s (Trace_Step      )
  call broadcast_real_s (Limit           )
  call broadcast_real_s (R_start         )
  call broadcast_real_s (R_end           )
  call broadcast_real_s (Z_start         )
  call broadcast_real_s (Z_end           )
  call broadcast_real_s (Phi_output      )
  call broadcast_real   (Theta      ,   2)
  call broadcast_real   (Psi        ,   2)
  call broadcast_real_s (offset          )
  call broadcast_inte_s (N_steps         )
  call broadcast_inte_s (N_points        )
  call broadcast_inte_s (N_sym           )
  call broadcast_inte_s (N_mult          )
  call broadcast_inte_s (N_theta         )
  call broadcast_inte_s (N_psi           )
  call broadcast_inte_s (N_phi           )
  call broadcast_inte_s (N_R             )
  call broadcast_inte_s (N_Z             )
  call broadcast_inte_s (Trace_Method    )
  call broadcast_inte_s (Trace_Coords    )
  call broadcast_inte_s (Input_Format    )
  call broadcast_inte_s (Output_Format   )
  call broadcast_inte_s (Panic_Level     )
  call broadcast_logi   (Debug           )

  return
 5000 write  (6,5001)
 5001 format ('error reading control table from input file')
  stop
  end subroutine load_run_control
!=======================================================================



!=======================================================================
  subroutine run_control_main()

  integer :: i


  if (firstP) then
     write (6, 1000)
     write (6, 1000)
     write (6, *) 'Main program:'
     write (6, *)
  endif


  select case (Run_Type)
  case ('sample_bfield')
     call sample_bfield
  case ('trace_bline')
     call trace_bline
  case ('poincare_plot')
     call poincare_plot
  case ('connection_length')
     call connection_length
  case ('get_equi_info_2D')
     call get_equi_info_2D
  case ('generate_flux_surface_2D')
     call generate_flux_surface_2D
  case ('generate_flux_surface_3D')
     call generate_flux_surface_3D
  case ('plot_boundary')
     call plot_boundary
  case ('safety_factor')
     call safety_factor
  case ('transform_to_flux_coordinates')
     call transform_to_flux_coordinates
  case ('generate_mag_file')
     call generate_mag_file
  case ('generate_magnetic_axis')
     call generate_magnetic_axis
  case ('flux_surface_grid')
     call flux_surface_grid
  case ('field_line_loss')
     call field_line_loss
  case ('generate_separatrix')
     call generate_separatrix
  case ('footprint_grid')
     call footprint_grid
  case ('setup_distance_to_surface')
     call setup_distance_to_surface
  case ('evaluate_distance_to_surface')
     call evaluate_distance_to_surface
  case ('separatrix_manifolds')
     call separatrix_manifolds()
  case ('generate_flux_tube')
     call generate_flux_tube
  case ('FLR_analysis')
     call FLR_analysis
  case ('melnikov_function')
     call melnikov_function()
  case ('generate_field_aligned_grid')
     call generate_field_aligend_grid(Run_Level(1), Run_Level(2))
  case ('critical_point_analysis')
     call critical_point_analysis(Grid_File, Output_File)
  case ('export_gfile')
     call export_gfile()
  case default
!     if (Run_Type(1:27) == 'generate_field_aligned_grid') then
!        read (Run_Type(40:42), *) i
!        call generate_field_aligend_grid (i)
!     else
        call run_control_development(Run_Type)
!     endif
  end select

 1000 format (/ '========================================================================')
  end subroutine run_control_main
!=======================================================================

end module run_control
