pgfortran -Mcuda=cc20,cc30,cc35,cc50,cc60 -fast -Mpreprocess -DDIPSLIP -acc -Mbackslash -ofd3d_pt_GPU_TSN dynamicsolver.f90 fd3d_deriv.f90 fd3d_init.f90 fd3d_theo.f90 waveforms.f90 inversion.f90 filters.for mod_pt.f90 randomdynmod.f90 PGAmisf.f90
#pgfortran -Mcuda=cc20,cc30,cc35,cc50,cc60 -fast -Mpreprocess -acc -Mbackslash -ofd3d_pt_GPU_TSN_SS dynamicsolver.f90 fd3d_deriv.f90 fd3d_init.f90 fd3d_theo.f90 waveforms.f90 inversion.f90 filters.for mod_pt.f90 randomdynmod.f90 PGAmisf.f90