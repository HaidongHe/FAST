!**********************************************************************************************************************************
! The FAST_Prog.f90, FAST_IO.f90, and FAST_Mods.f90 make up the FAST glue code in the FAST Modularization Framework.
!..................................................................................................................................
! LICENSING
! Copyright (C) 2013-2014  National Renewable Energy Laboratory
!
!    This file is part of FAST.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!**********************************************************************************************************************************
! File last committed: $Date$
! (File) Revision #: $Rev$
! URL: $HeadURL$
!**********************************************************************************************************************************
PROGRAM FAST
! This program models 2- or 3-bladed turbines of a standard configuration.
!
! noted compilation switches:
!   SOLVE_OPTION_1_BEFORE_2 (uses a different order for solving input-output relationships)
!   OUTPUT_ADDEDMASS        (outputs a file called "<RootName>.AddedMass" that contains HydroDyn's added-mass matrix.
!   OUTPUT_JACOBIAN
!   FPE_TRAP_ENABLED        (use with gfortran when checking for floating point exceptions)
!   OUTPUT_INPUTMESHES
!.................................................................................................


   USE FAST_IO_Subs   ! all of the ModuleName_types modules are inherited from FAST_IO_Subs
   
   USE AeroDyn
   USE ElastoDyn
   USE FEAMooring
   USE HydroDyn
   USE IceDyn
   USE IceFloe
   USE MAP
   USE ServoDyn
   USE SubDyn
                    
IMPLICIT  NONE
   
   ! Local variables:

   ! Data for the glue code:
TYPE(FAST_ParameterType)              :: p_FAST                                  ! Parameters for the glue code (bjj: made global for now)
TYPE(FAST_OutputType)                 :: y_FAST                                  ! Output variables for the glue code

TYPE(FAST_ModuleMapType)              :: MeshMapData                             ! Data for mapping between modules


   ! Data for the ElastoDyn module:
TYPE(ED_InitInputType)                :: InitInData_ED                           ! Initialization input data
TYPE(ED_InitOutputType)               :: InitOutData_ED                          ! Initialization output data
TYPE(ElastoDyn_Data)                  :: ED

   ! Data for the ServoDyn module:
TYPE(SrvD_InitInputType)              :: InitInData_SrvD                         ! Initialization input data
TYPE(SrvD_InitOutputType)             :: InitOutData_SrvD                        ! Initialization output data
TYPE(SrvD_OutputType)                 :: y_SrvD_prev                             ! System outputs at previous time step (required for SrvD Input-Output solve)
TYPE(ServoDyn_Data)                   :: SrvD

   ! Data for the AeroDyn module:
TYPE(AD_InitInputType)                :: InitInData_AD                           ! Initialization input data
TYPE(AD_InitOutputType)               :: InitOutData_AD                          ! Initialization output data
TYPE(AeroDyn_Data)                    :: AD
   
   ! Data for InflowWind module:
REAL(ReKi)                            :: IfW_WriteOutput(3)                      ! Temporary hack for getting wind speeds from InflowWind

   ! Data for the HydroDyn module:
TYPE(HydroDyn_InitInputType)          :: InitInData_HD                           ! Initialization input data
TYPE(HydroDyn_InitOutputType)         :: InitOutData_HD                          ! Initialization output data
TYPE(HydroDyn_Data)                   :: HD

   ! Data for the SubDyn module:
TYPE(SD_InitInputType)                :: InitInData_SD                           ! Initialization input data
TYPE(SD_InitOutputType)               :: InitOutData_SD                          ! Initialization output data
TYPE(SubDyn_Data)                     :: SD

   ! Data for the MAP (Mooring Analysis Program) module:
TYPE(MAP_InitInputType)               :: InitInData_MAP                          ! Initialization input data
TYPE(MAP_InitOutputType)              :: InitOutData_MAP                         ! Initialization output data
TYPE(MAP_Data)                        :: MAPp


   ! Data for the FEAMooring module:
TYPE(FEAM_InitInputType)              :: InitInData_FEAM                         ! Initialization input data
TYPE(FEAM_InitOutputType)             :: InitOutData_FEAM                        ! Initialization output data
TYPE(FEAMooring_Data)                 :: FEAM

   ! Data for the IceFloe module:
TYPE(IceFloe_InitInputType)           :: InitInData_IceF                         ! Initialization input data
TYPE(IceFloe_InitOutputType)          :: InitOutData_IceF                        ! Initialization output data
TYPE(IceFloe_Data)                    :: IceF

   ! Data for the IceDyn module:
INTEGER, PARAMETER                    :: IceD_MaxLegs = 4;                       ! because I don't know how many legs there are before calling IceD_Init and I don't want to copy the data because of sibling mesh issues, I'm going to allocate IceD based on this number
TYPE(IceD_InitInputType)              :: InitInData_IceD                         ! Initialization input data
TYPE(IceD_InitOutputType)             :: InitOutData_IceD                        ! Initialization output data (each instance will have the same output channels)
                                                                                  
TYPE(IceDyn_Data)                     :: IceD                                    ! All the IceDyn data used in time-step loop
REAL(DbKi)                            :: dt_IceD                                 ! tmp dt variable to ensure IceDyn doesn't specify different dt values for different legs (IceDyn instances)

   ! Other/Misc variables
REAL(DbKi)                            :: TiLstPrn                                ! The simulation time of the last print
REAL(DbKi)                            :: t_global                                ! Current simulation time (for global/FAST simulation)
REAL(DbKi)                            :: t_global_next                           ! next simulation time (t_global + p_FAST%dt)
REAL(DbKi)                            :: t_module                                ! Current simulation time for module 
REAL(DbKi), PARAMETER                 :: t_initial = 0.0_DbKi                    ! Initial time
REAL(DbKi)                            :: NextJacCalcTime                         ! Time between calculating Jacobians in the HD-ED and SD-ED simulations

REAL(ReKi)                            :: PrevClockTime                           ! Clock time at start of simulation in seconds
REAL                                  :: UsrTime1                                ! User CPU time for simulation initialization
REAL                                  :: UsrTime2                                ! User CPU time for simulation (without intialization)
REAL                                  :: UsrTimeDiff                             ! Difference in CPU time from start to finish of program execution


INTEGER(IntKi)                        :: I,J                                     ! generic loop counter
INTEGER(IntKi)                        :: IceDim                                  ! dimension we're pre-allocating for number of IceDyn legs/instances
INTEGER                               :: StrtTime (8)                            ! Start time of simulation (including intialization)
INTEGER                               :: SimStrtTime (8)                         ! Start time of simulation (after initialization)
INTEGER(IntKi)                        :: n_TMax_m1                               ! The time step of TMax - dt (the end time of the simulation)
INTEGER(IntKi)                        :: n_t_global                              ! simulation time step, loop counter for global (FAST) simulation
INTEGER(IntKi)                        :: n_t_module                              ! simulation time step, loop counter for individual modules 
INTEGER(IntKi)                        :: j_pc                                    ! predictor-corrector loop counter 
INTEGER(IntKi)                        :: j_ss                                    ! substep loop counter 
INTEGER(IntKi)                        :: Step                                    ! Current simulation time step
INTEGER(IntKi)                        :: ErrStat                                 ! Error status
CHARACTER(1024)                       :: ErrMsg                                  ! Error message

LOGICAL                               :: calcJacobian                            ! Should we calculate Jacobians in Option 1?

!#ifdef CHECK_SOLVE_OPTIONS
!!integer,parameter:: debug_unit = 52    
!integer,parameter:: input_unit = 53  
!INTEGER::I_TMP
!character(50) :: tmpstr
!#endif


   !...............................................................................................................................
   ! initialization
   !...............................................................................................................................

   y_FAST%UnSum = -1                                                    ! set the summary file unit to -1 to indicate it's not open
   y_FAST%UnOu  = -1                                                    ! set the text output file unit to -1 to indicate it's not open
   y_FAST%UnGra = -1                                                    ! set the binary graphics output file unit to -1 to indicate it's not open
      
   y_FAST%n_Out = 0                                                     ! set the number of ouptut channels to 0 to indicate there's nothing to write to the binary file
   p_FAST%ModuleInitialized = .FALSE.                                   ! (array initialization) no modules are initialized 
   
      ! Get the current time
   CALL DATE_AND_TIME ( Values=StrtTime )                               ! Let's time the whole simulation
   CALL CPU_TIME ( UsrTime1 )                                           ! Initial time (this zeros the start time when used as a MATLAB function)
   Step            = 0                                                  ! The first step counter

   AbortErrLev     = ErrID_Fatal                                        ! Until we read otherwise from the FAST input file, we abort only on FATAL errors
   t_global        = t_initial - 20.                                    ! initialize this to a number < t_initial for error message in ProgAbort
   calcJacobian    = .TRUE.                                             ! we need to calculate the Jacobian
   NextJacCalcTime = t_global                                           ! We want to calculate the Jacobian on the first step
   
   
      ! ... Initialize NWTC Library (open console, set pi constants) ...
   CALL NWTC_Init( ProgNameIN=FAST_ver%Name, EchoLibVer=.FALSE. )       ! sets the pi constants, open console for output, etc...


      ! ... Open and read input files, initialize global parameters. ...
   CALL FAST_Init( p_FAST, y_FAST, ErrStat, ErrMsg )
      CALL CheckError( ErrStat, 'Message from FAST_Init: '//NewLine//ErrMsg )
         
   p_FAST%dt_module = p_FAST%dt ! initialize time steps for each module
                                 
   ! ........................
   ! initialize ElastoDyn (must be done first)
   ! ........................
   
   ALLOCATE( ED%Input( p_FAST%InterpOrder+1 ), ED%InputTimes( p_FAST%InterpOrder+1 ), ED%Output( p_FAST%InterpOrder+1 ),STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating ED%Input, ED%Output, and ED%InputTimes.") 
   
   InitInData_ED%InputFile     = p_FAST%EDFile
   InitInData_ED%ADInputFile   = p_FAST%AeroFile
   InitInData_ED%RootName      = p_FAST%OutFileRoot
   InitInData_ED%CompElast     = p_FAST%CompElast == Module_ED

   CALL ED_Init( InitInData_ED, ED%Input(1), ED%p, ED%x, ED%xd, ED%z, ED%OtherSt, ED%Output(1), p_FAST%dt_module( MODULE_ED ), InitOutData_ED, ErrStat, ErrMsg )
   p_FAST%ModuleInitialized(Module_ED) = .TRUE.
      CALL CheckError( ErrStat, 'Message from ED_Init: '//NewLine//ErrMsg )

   CALL SetModuleSubstepTime(Module_ED, p_FAST, y_FAST, ErrStat, ErrMsg)
      CALL CheckError(ErrStat, ErrMsg)
      
      ! bjj: added this check per jmj; perhaps it would be better in ElastoDyn, but I'll leave it here for now:
   IF ( p_FAST%TurbineType == Type_Offshore_Floating ) THEN
      IF ( ED%p%TowerBsHt < 0.0_ReKi .AND. .NOT. EqualRealNos( ED%p%TowerBsHt, 0.0_ReKi ) ) THEN
         CALL CheckError(ErrID_Fatal, "ElastoDyn TowerBsHt must not be negative for floating offshore systems.") 
      END IF      
   END IF
   
      
   ! ........................
   ! initialize ServoDyn 
   ! ........................
   ALLOCATE( SrvD%Input( p_FAST%InterpOrder+1 ), SrvD%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating SrvD%Input and SrvD%InputTimes.") 
   
   IF ( p_FAST%CompServo == Module_SrvD ) THEN
      InitInData_SrvD%InputFile     = p_FAST%ServoFile
      InitInData_SrvD%RootName      = p_FAST%OutFileRoot
      InitInData_SrvD%NumBl         = InitOutData_ED%NumBl
      CALL AllocAry(InitInData_SrvD%BlPitchInit, InitOutData_ED%NumBl, 'BlPitchInit', ErrStat, ErrMsg)
         CALL CheckError( ErrStat, ErrMsg )

      InitInData_SrvD%BlPitchInit   = InitOutData_ED%BlPitch
      CALL SrvD_Init( InitInData_SrvD, SrvD%Input(1), SrvD%p, SrvD%x, SrvD%xd, SrvD%z, SrvD%OtherSt, SrvD%y, p_FAST%dt_module( MODULE_SrvD ), InitOutData_SrvD, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_SrvD) = .TRUE.
         CALL CheckError( ErrStat, 'Message from SrvD_Init: '//NewLine//ErrMsg )

      !IF ( InitOutData_SrvD%CouplingScheme == ExplicitLoose ) THEN ...  bjj: abort if we're doing anything else!

      CALL SetModuleSubstepTime(Module_SrvD, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)

      !! initialize y%ElecPwr and y%GenTq because they are one timestep different (used as input for the next step)
      !!bjj: perhaps this will require some better thought so that these two fields of y_SrvD_prev don't get set here in the glue code
      !CALL SrvD_CopyOutput( SrvD%y, y_SrvD_prev, MESH_NEWCOPY, ErrStat, ErrMsg)               
      !   
                      
   END IF


   ! ........................
   ! initialize AeroDyn 
   ! ........................
   ALLOCATE( AD%Input( p_FAST%InterpOrder+1 ), AD%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating AD%Input and AD%InputTimes.")    
   
   IF ( p_FAST%CompAero == Module_AD ) THEN
      CALL AD_SetInitInput(InitInData_AD, InitOutData_ED, ED%Output(1), p_FAST, ErrStat, ErrMsg)            ! set the values in InitInData_AD
         CALL CheckError( ErrStat, 'Message from AD_SetInitInput: '//NewLine//ErrMsg )
            
      CALL AD_Init( InitInData_AD, AD%Input(1), AD%p, AD%x, AD%xd, AD%z, AD%OtherSt, AD%y, p_FAST%dt_module( MODULE_AD ), InitOutData_AD, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_AD) = .TRUE.
         CALL CheckError( ErrStat, 'Message from AD_Init: '//NewLine//ErrMsg )
            
      CALL SetModuleSubstepTime(Module_AD, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
      
         ! bjj: this really shouldn't be in the FAST glue code, but I'm going to put this check here so people don't use an invalid model 
         !    and send me emails to debug numerical issues in their results.
      IF ( AD%p%TwrProps%PJM_Version .AND. p_FAST%TurbineType == Type_Offshore_Floating ) THEN
         CALL CheckError( ErrID_Fatal, 'AeroDyn tower influence model "NEWTOWER" is invalid for models of floating offshore turbines.' )
      END IF         

      
   ELSE
   !   ED%p%AirDens = 0
      IfW_WriteOutput = 0.0
   END IF


   ! ........................
   ! initialize HydroDyn 
   ! ........................
   ALLOCATE( HD%Input( p_FAST%InterpOrder+1 ), HD%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating HD%Input and HD%InputTimes.") 

   IF ( p_FAST%CompHydro == Module_HD ) THEN

      InitInData_HD%Gravity       = InitOutData_ED%Gravity
      InitInData_HD%UseInputFile  = .TRUE.
      InitInData_HD%InputFile     = p_FAST%HydroFile
      InitInData_HD%OutRootName   = p_FAST%OutFileRoot
      InitInData_HD%TMax          = p_FAST%TMax
      InitInData_HD%hasIce        = p_FAST%CompIce /= Module_None
      
         ! if wave field needs an offset, modify these values (added at request of SOWFA developers):
      InitInData_HD%PtfmLocationX = 0.0_ReKi  
      InitInData_HD%PtfmLocationY = 0.0_ReKi
      
      CALL HydroDyn_Init( InitInData_HD, HD%Input(1), HD%p,  HD%x, HD%xd, HD%z, HD%OtherSt, HD%y, p_FAST%dt_module( MODULE_HD ), InitOutData_HD, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_HD) = .TRUE.
         CALL CheckError( ErrStat, 'Message from HydroDyn_Init: '//NewLine//ErrMsg )

      CALL SetModuleSubstepTime(Module_HD, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
      
!call wrscr1( 'FAST/Morison/LumpedMesh:')      
!call meshprintinfo( CU, HD%Input(1)%morison%LumpedMesh )          
      
      
   END IF   ! CompHydro

   ! ........................
   ! initialize SubDyn 
   ! ........................
   ALLOCATE( SD%Input( p_FAST%InterpOrder+1 ), SD%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating SD%Input and SD%InputTimes.") 

   IF ( p_FAST%CompSub == Module_SD ) THEN
          
      IF ( p_FAST%CompHydro == Module_HD ) THEN
         InitInData_SD%WtrDpth = InitOutData_HD%WtrDpth
      ELSE
         InitInData_SD%WtrDpth = 0.0_ReKi
      END IF
            
      InitInData_SD%g             = InitOutData_ED%Gravity     
      !InitInData_SD%UseInputFile = .TRUE. 
      InitInData_SD%SDInputFile   = p_FAST%SubFile
      InitInData_SD%RootName      = p_FAST%OutFileRoot
      InitInData_SD%TP_RefPoint   = ED%Output(1)%PlatformPtMesh%Position(:,1)  ! bjj: not sure what this is supposed to be 
      InitInData_SD%SubRotateZ    = 0.0                                        ! bjj: not sure what this is supposed to be 
      
            
      CALL SD_Init( InitInData_SD, SD%Input(1), SD%p,  SD%x, SD%xd, SD%z, SD%OtherSt, SD%y, p_FAST%dt_module( MODULE_SD ), InitOutData_SD, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_SD) = .TRUE.
         CALL CheckError( ErrStat, 'Message from SD_Init: '//NewLine//ErrMsg )

      CALL SetModuleSubstepTime(Module_SD, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
                        
   END IF

   ! ------------------------------
   ! initialize CompMooring modules 
   ! ------------------------------
   ALLOCATE( MAPp%Input( p_FAST%InterpOrder+1 ), MAPp%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating MAPp%Input and MAPp%InputTimes.") 
   ALLOCATE( FEAM%Input( p_FAST%InterpOrder+1 ), FEAM%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating FEAM%Input and FEAM%InputTimes.") 
   
   ! ........................
   ! initialize MAP 
   ! ........................
   IF (p_FAST%CompMooring == Module_MAP) THEN
      !bjj: until we modify this, MAP requires HydroDyn to be used. (perhaps we could send air density from AeroDyn or something...)
      
      CALL WrScr(NewLine) !bjj: I'm printing two blank lines here because MAP seems to be writing over the last line on the screen.
      
      InitInData_MAP%filename          =  p_FAST%MooringFile        ! This needs to be set according to what is in the FAST input file. 
      InitInData_MAP%rootname          =  p_FAST%OutFileRoot        ! Output file name 
      InitInData_MAP%gravity           =  InitOutData_ED%Gravity    ! This need to be according to g used in ElastoDyn
      InitInData_MAP%sea_density       =  InitOutData_HD%WtrDens    ! This needs to be set according to seawater density in HydroDyn
      InitInData_MAP%depth             =  InitOutData_HD%WtrDpth    ! This need to be set according to the water depth in HydroDyn
      
      InitInData_MAP%coupled_to_FAST   = .TRUE.      
      
      CALL MAP_Init( InitInData_MAP, MAPp%Input(1), MAPp%p,  MAPp%x, MAPp%xd, MAPp%z, MAPp%OtherSt, MAPp%y, p_FAST%dt_module( MODULE_MAP ), InitOutData_MAP, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_MAP) = .TRUE.
         CALL CheckError( ErrStat, 'Message from MAP_Init: '//NewLine//ErrMsg )

      CALL SetModuleSubstepTime(Module_MAP, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
                   
   ! ........................
   ! initialize FEAM 
   ! ........................
   ELSEIF (p_FAST%CompMooring == Module_FEAM) THEN
            
      InitInData_FEAM%InputFile   = p_FAST%MooringFile         ! This needs to be set according to what is in the FAST input file. 
      InitInData_FEAM%RootName    = p_FAST%OutFileRoot
      
!BJJ: FIX THIS!!!!      
      InitInData_FEAM%PtfmInit    = 0  ! initial position of the platform... hmmmm
      
! bjj: (Why isn't this using gravity? IT'S hardcoded in FEAM.f90)      
!      InitInData_FEAM%gravity     =  InitOutData_ED%Gravity    ! This need to be according to g used in ElastoDyn 
!      InitInData_FEAM%sea_density =  InitOutData_HD%WtrDens    ! This needs to be set according to seawater density in HydroDyn
!      InitInData_FEAM%depth       =  InitOutData_HD%WtrDpth    ! This need to be set according to the water depth in HydroDyn
            
      CALL FEAM_Init( InitInData_FEAM, FEAM%Input(1), FEAM%p,  FEAM%x, FEAM%xd, FEAM%z, FEAM%OtherSt, FEAM%y, p_FAST%dt_module( MODULE_FEAM ), InitOutData_FEAM, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_FEAM) = .TRUE.
         CALL CheckError( ErrStat, 'Message from FEAM_Init: '//NewLine//ErrMsg )

      CALL SetModuleSubstepTime(Module_FEAM, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
      
   END IF

   ! ------------------------------
   ! initialize CompIce modules 
   ! ------------------------------
   ALLOCATE( IceF%Input( p_FAST%InterpOrder+1 ), IceF%InputTimes( p_FAST%InterpOrder+1 ), STAT = ErrStat )
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating IceF%Input and IceF%InputTimes.") 

      ! We need this to be allocated (else we have issues passing nonallocated arrays and using the first index of Input(),
      !   but we don't need the space of IceD_MaxLegs if we're not using it. 
   IF ( p_FAST%CompIce /= Module_IceD ) THEN   
      IceDim = 1
   ELSE
      IceDim = IceD_MaxLegs
   END IF
      
      ! because there may be multiple instances of IceDyn, we'll allocate arrays for that here
      ! we could allocate these after 
   ALLOCATE( IceD%Input( p_FAST%InterpOrder+1, IceDim ), IceD%InputTimes( p_FAST%InterpOrder+1, IceDim ), STAT = ErrStat )
         IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating IceD%Input and IceD%InputTimes")
        
     ALLOCATE( IceD%x(           IceDim), &
               IceD%xd(          IceDim), &
               IceD%z(           IceDim), &
               IceD%OtherSt(     IceDim), &
               IceD%p(           IceDim), &
               IceD%u(           IceDim), &
               IceD%y(           IceDim), &
               IceD%x_pred(      IceDim), &
               IceD%xd_pred(     IceDim), &
               IceD%z_pred(      IceDim), &
               IceD%OtherSt_old( IceDim), &
                                             STAT = ErrStat )                                                  
      IF (ErrStat /= 0) CALL CheckError(ErrID_Fatal,"Error allocating IceD state, input, and output data.")
      
         
         
   ! ........................
   ! initialize IceFloe 
   ! ........................
   IF ( p_FAST%CompIce == Module_IceF ) THEN
                      
      InitInData_IceF%InputFile     = p_FAST%IceFile
      InitInData_IceF%RootName      = p_FAST%OutFileRoot     
      InitInData_IceF%simLength     = p_FAST%TMax  !bjj: IceFloe stores this as single-precision (ReKi) TMax is DbKi
      InitInData_IceF%MSL2SWL       = InitOutData_HD%MSL2SWL
      InitInData_IceF%gravity       = InitOutData_ED%Gravity
      
      CALL IceFloe_Init( InitInData_IceF, IceF%Input(1), IceF%p,  IceF%x, IceF%xd, IceF%z, IceF%OtherSt, IceF%y, p_FAST%dt_module( MODULE_IceF ), InitOutData_IceF, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_IceF) = .TRUE.
         CALL CheckError( ErrStat, 'Message from IceF_Init: '//NewLine//ErrMsg )

      CALL SetModuleSubstepTime(Module_IceF, p_FAST, y_FAST, ErrStat, ErrMsg)
         CALL CheckError(ErrStat, ErrMsg)
                        
   ! ........................
   ! initialize IceDyn 
   ! ........................
   ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN  
      
      InitInData_IceD%InputFile     = p_FAST%IceFile
      InitInData_IceD%RootName      = p_FAST%OutFileRoot     
      InitInData_IceD%MSL2SWL       = InitOutData_HD%MSL2SWL      
      InitInData_IceD%WtrDens       = InitOutData_HD%WtrDens    
      InitInData_IceD%gravity       = InitOutData_ED%Gravity
      InitInData_IceD%TMax          = p_FAST%TMax
      InitInData_IceD%LegNum        = 1
      
      CALL IceD_Init( InitInData_IceD, IceD%Input(1,1), IceD%p(1),  IceD%x(1), IceD%xd(1), IceD%z(1), IceD%OtherSt(1), IceD%y(1), p_FAST%dt_module( MODULE_IceD ), InitOutData_IceD, ErrStat, ErrMsg )
      p_FAST%ModuleInitialized(Module_IceD) = .TRUE.
         CALL CheckError( ErrStat, 'Message from IceD_Init: '//NewLine//ErrMsg )

         CALL SetModuleSubstepTime(Module_IceD, p_FAST, y_FAST, ErrStat, ErrMsg)
            CALL CheckError(ErrStat, ErrMsg)         
         
         ! now initialize IceD for additional legs (if necessary)
      dt_IceD           = p_FAST%dt_module( MODULE_IceD )
      p_FAST%numIceLegs = InitOutData_IceD%numLegs     
      
      IF (p_FAST%numIceLegs > IceD_MaxLegs) THEN
         CALL CheckError( ErrID_Fatal, 'IceDyn-FAST coupling is supported for up to '//TRIM(Num2LStr(IceD_MaxLegs))//' legs, but '//TRIM(Num2LStr(p_FAST%numIceLegs))//' legs were specified.' )
      END IF
                  

      DO i=2,p_FAST%numIceLegs  ! basically, we just need IceDyn to set up its meshes for inputs/outputs and possibly initial values for states
         InitInData_IceD%LegNum = i
         
         CALL IceD_Init( InitInData_IceD, IceD%Input(1,i), IceD%p(i),  IceD%x(i), IceD%xd(i), IceD%z(i), IceD%OtherSt(i), IceD%y(i), dt_IceD, InitOutData_IceD, ErrStat, ErrMsg )
         
         !bjj: we're going to force this to have the same timestep because I don't want to have to deal with n IceD modules with n timesteps.
         IF (.NOT. EqualRealNos( p_FAST%dt_module( MODULE_IceD ),dt_IceD )) THEN
            CALL CheckError( ErrID_Fatal, "All instances of IceDyn (one per support-structure leg) must be the same" )
         END IF
      END DO
            
   END IF   
   

   ! ........................
   ! Set up output for glue code (must be done after all modules are initialized so we have their WriteOutput information)
   ! ........................

   CALL FAST_InitOutput( p_FAST, y_FAST, InitOutData_ED, InitOutData_SrvD, InitOutData_AD, InitOutData_HD, &
                         InitOutData_SD, InitOutData_MAP, InitOutData_FEAM, InitOutData_IceF, InitOutData_IceD, ErrStat, ErrMsg )
      CALL CheckError( ErrStat, 'Message from FAST_InitOutput: '//NewLine//ErrMsg )


   ! -------------------------------------------------------------------------
   ! Initialize mesh-mapping data
   ! -------------------------------------------------------------------------

   CALL InitModuleMappings(p_FAST, ED, AD, HD, SD, SrvD, MAPp, FEAM, IceF, IceD, MeshMapData, ErrStat, ErrMsg)

   ! -------------------------------------------------------------------------
   ! Write initialization data to FAST summary file:
   ! -------------------------------------------------------------------------
   
   CALL FAST_WrSum( p_FAST, y_FAST, MeshMapData, ErrStat, ErrMsg )
      CALL CheckError( ErrStat, 'Message from FAST_WrSum: '//NewLine//ErrMsg )
   
   
   !...............................................................................................................................
   ! Destroy initializion data
   ! Note that we're ignoring any errors here (we'll print them when we try to destroy at program exit)
   !...............................................................................................................................

   CALL ED_DestroyInitInput(  InitInData_ED,  ErrStat, ErrMsg )
   CALL ED_DestroyInitOutput( InitOutData_ED, ErrStat, ErrMsg )

   CALL AD_DestroyInitInput(  InitInData_AD,  ErrStat, ErrMsg )
   CALL AD_DestroyInitOutput( InitOutData_AD, ErrStat, ErrMsg )
   
   CALL SrvD_DestroyInitInput(  InitInData_SrvD,  ErrStat, ErrMsg )
   CALL SrvD_DestroyInitOutput( InitOutData_SrvD, ErrStat, ErrMsg )

   CALL HydroDyn_DestroyInitInput(  InitInData_HD,  ErrStat, ErrMsg )
   CALL HydroDyn_DestroyInitOutput( InitOutData_HD, ErrStat, ErrMsg )

   CALL SD_DestroyInitInput(  InitInData_SD,  ErrStat, ErrMsg )
   CALL SD_DestroyInitOutput( InitOutData_SD, ErrStat, ErrMsg )
      
   CALL MAP_DestroyInitInput(  InitInData_MAP,  ErrStat, ErrMsg )
   CALL MAP_DestroyInitOutput( InitOutData_MAP, ErrStat, ErrMsg )
   
   CALL FEAM_DestroyInitInput(  InitInData_FEAM,  ErrStat, ErrMsg )
   CALL FEAM_DestroyInitOutput( InitOutData_FEAM, ErrStat, ErrMsg )

   CALL IceFloe_DestroyInitInput(  InitInData_IceF,  ErrStat, ErrMsg )
   CALL IceFloe_DestroyInitOutput( InitOutData_IceF, ErrStat, ErrMsg )
   
   CALL IceD_DestroyInitInput(  InitInData_IceD,  ErrStat, ErrMsg )
   CALL IceD_DestroyInitOutput( InitOutData_IceD, ErrStat, ErrMsg )
   
   !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   ! loose coupling
   !+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   !CALL WrScr1 ( '' )

   
   !...............................................................................................................................
   ! Initialization: (calculate outputs based on states at t=t_initial as well as guesses of inputs and constraint states)
   !...............................................................................................................................
   
   t_global   = t_initial
   n_t_global = -1  ! initialize here because CalcOutputs_And_SolveForInputs uses it
   j_PC       = -1
   Step       = 0
   n_TMax_m1  = CEILING( ( (p_FAST%TMax - t_initial) / p_FAST%DT ) ) - 1 ! We're going to go from step 0 to n_TMax (thus the -1 here)
     
  
   CALL SimStatus_FirstTime( TiLstPrn, PrevClockTime, SimStrtTime, UsrTime2, t_global, p_FAST%TMax )

   ! Solve input-output relations; this section of code corresponds to Eq. (35) in Gasmi et al. (2013)
   ! This code will be specific to the underlying modules
   
#ifdef SOLVE_OPTION_1_BEFORE_2
! used for Option 1 before Option 2:

   IF ( p_FAST%CompSub == Module_SD .OR. p_FAST%CompHydro == Module_HD ) THEN
   ! Because SubDyn needs a better initial guess from ElastoDyn, we'll add an additional call to ED_CalcOutput to get them:
   ! (we'll do the same for HydroDyn, though I'm not sure it's as critical)
   
      CALL ED_CalcOutput( t_global, ED%Input(1), ED%p, ED%x, ED%xd, ED%z, ED%OtherSt, ED%Output(1), ErrStat, ErrMsg )
         CALL CheckError( ErrStat, 'Message from ED_CalcOutput: '//NewLine//ErrMsg  )    
      
      CALL Transfer_ED_to_HD_SD_Mooring( p_FAST, ED%Output(1), HD%Input(1), SD%Input(1), MAPp%Input(1), FEAM%Input(1), MeshMapData, ErrStat, ErrMsg )         
         CALL CheckError( ErrStat, ErrMsg  )    
               
   END IF   
#endif   

   CALL CalcOutputs_And_SolveForInputs(  t_global &
                        , ED%x  , ED%xd  , ED%z   &
                        , SrvD%x, SrvD%xd, SrvD%z &
                        , HD%x  , HD%xd  , HD%z   &
                        , SD%x  , SD%xd  , SD%z   &
                        , MAPp%x , MAPp%xd , MAPp%z  &
                        , AD%x  , AD%xd  , AD%z   &
                        , FEAM%x, FEAM%xd, FEAM%z &
                        , IceF%x, IceF%xd, IceF%z &
                        , IceD%x, IceD%xd, IceD%z &
                        )           
   
#ifdef OUTPUT_INPUTMESHES
   CALL WriteInputMeshesToFile( ED%Input(1), SD%Input(1), HD%Input(1), MAPp%Input(1), AD%Input(1), TRIM(p_FAST%OutFileRoot)//'.InputMeshes.bin', ErrStat, ErrMsg) 
#else
      IF (p_FAST%WrGraphics) THEN
         CALL WriteInputMeshesToFile( ED%Input(1), SD%Input(1), HD%Input(1), MAPp%Input(1), AD%Input(1), TRIM(p_FAST%OutFileRoot)//'.InputMeshes.bin', ErrStat, ErrMsg) 
      END IF 
#endif

      !----------------------------------------------------------------------------------------
      ! Check to see if we should output data this time step:
      !----------------------------------------------------------------------------------------

      CALL WriteOutputToFile()   
   
   !...............
   ! Copy values of these initial guesses for interpolation/extrapolation and 
   ! initialize predicted states for j_pc loop (use MESH_NEWCOPY here so we can use MESH_UPDATE copy later)
   !...............
         
   ! Initialize Input-Output arrays for interpolation/extrapolation:

   ! We fill ED%InputTimes with negative times, but the ED%Input values are identical for each of those times; this allows
   ! us to use, e.g., quadratic interpolation that effectively acts as a zeroth-order extrapolation and first-order extrapolation
   ! for the first and second time steps.  (The interpolation order in the ExtrapInput routines are determined as
   ! order = SIZE(ED%Input)

   DO j = 1, p_FAST%InterpOrder + 1
      ED%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
      !ED_OutputTimes(j) = t_initial - (j - 1) * dt
   END DO

   DO j = 2, p_FAST%InterpOrder + 1
      CALL ED_CopyInput (ED%Input(1),  ED%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from ED_CopyInput (ED%Input): '//NewLine//ErrMsg )
      
      CALL ED_CopyOutput (ED%Output(1), ED%Output(j), MESH_NEWCOPY, Errstat, ErrMsg) !BJJ: THIS IS REALLY ONLY NECESSARY FOR ED-HD COUPLING AT THE MOMENT
         CALL CheckError( ErrStat, 'Message from ED_CopyOutput (ED%Output): '//NewLine//ErrMsg )
   END DO
   CALL ED_CopyInput (ED%Input(1),  ED%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
      CALL CheckError( ErrStat, 'Message from ED_CopyInput (ED%u): '//NewLine//ErrMsg )
   CALL ED_CopyOutput (ED%Output(1), ED%y, MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
      CALL CheckError( ErrStat, 'Message from ED_CopyOutput (ED%y): '//NewLine//ErrMsg )   
   
      
      ! Initialize predicted states for j_pc loop:
   CALL ED_CopyContState   ( ED%x,  ED%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
      CALL CheckError( ErrStat, 'Message from ED_CopyContState (init): '//NewLine//ErrMsg )
   CALL ED_CopyDiscState   (ED%xd, ED%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
      CALL CheckError( ErrStat, 'Message from ED_CopyDiscState (init): '//NewLine//ErrMsg )
   CALL ED_CopyConstrState ( ED%z,  ED%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
      CALL CheckError( ErrStat, 'Message from ED_CopyConstrState (init): '//NewLine//ErrMsg )   
   IF ( p_FAST%n_substeps( MODULE_ED ) > 1 ) THEN
      CALL ED_CopyOtherState( ED%OtherSt, ED%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from ED_CopyOtherState (init): '//NewLine//ErrMsg )   
   END IF   
      
      
   IF ( p_FAST%CompServo == Module_SrvD ) THEN      
      ! Initialize Input-Output arrays for interpolation/extrapolation:
         
      DO j = 1, p_FAST%InterpOrder + 1
         SrvD%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !SrvD_OutputTimes(j) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL SrvD_CopyInput (SrvD%Input(1),  SrvD%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from SrvD_CopyInput (SrvD%Input): '//NewLine//ErrMsg )
      END DO
      CALL SrvD_CopyInput (SrvD%Input(1),  SrvD%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from SrvD_CopyInput (SrvD%u): '//NewLine//ErrMsg )
   
         ! Initialize predicted states for j_pc loop:
      CALL SrvD_CopyContState   ( SrvD%x,  SrvD%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from SrvD_CopyContState (init): '//NewLine//ErrMsg )
      CALL SrvD_CopyDiscState   (SrvD%xd, SrvD%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from SrvD_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL SrvD_CopyConstrState ( SrvD%z,  SrvD%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from SrvD_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_SrvD ) > 1 ) THEN
         CALL SrvD_CopyOtherState( SrvD%OtherSt, SrvD%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from SrvD_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF    
         
   END IF ! CompServo
   
   
   IF ( p_FAST%CompAero == Module_AD ) THEN      
         ! Copy values for interpolation/extrapolation:

      DO j = 1, p_FAST%InterpOrder + 1
         AD%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !AD_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL AD_CopyInput (AD%Input(1),  AD%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from AD_CopyInput: '//NewLine//ErrMsg )
      END DO
      CALL AD_CopyInput (AD%Input(1),  AD%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from AD_CopyInput: '//NewLine//ErrMsg )


         ! Initialize predicted states for j_pc loop:
      CALL AD_CopyContState   ( AD%x,  AD%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from AD_CopyContState (init): '//NewLine//ErrMsg )
      CALL AD_CopyDiscState   (AD%xd, AD%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from AD_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL AD_CopyConstrState ( AD%z,  AD%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from AD_CopyConstrState (init): '//NewLine//ErrMsg )      
      IF ( p_FAST%n_substeps( MODULE_AD ) > 1 ) THEN
         CALL AD_CopyOtherState( AD%OtherSt, AD%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from AD_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF         

   END IF ! CompAero == Module_AD 
   
   
   IF ( p_FAST%CompHydro == Module_HD ) THEN      
         ! Copy values for interpolation/extrapolation:
      DO j = 1, p_FAST%InterpOrder + 1
         HD%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !HD_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL HydroDyn_CopyInput (HD%Input(1),  HD%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from HydroDyn_CopyInput: '//NewLine//ErrMsg )
      END DO
      CALL HydroDyn_CopyInput (HD%Input(1),  HD%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from HydroDyn_CopyInput: '//NewLine//ErrMsg )


         ! Initialize predicted states for j_pc loop:
      CALL HydroDyn_CopyContState   ( HD%x,  HD%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from HydroDyn_CopyContState (init): '//NewLine//ErrMsg )
      CALL HydroDyn_CopyDiscState   (HD%xd, HD%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from HydroDyn_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL HydroDyn_CopyConstrState ( HD%z,  HD%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from HydroDyn_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_HD ) > 1 ) THEN
         CALL HydroDyn_CopyOtherState( HD%OtherSt, HD%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from HydroDyn_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF          
      
   END IF !CompHydro
         
   
   IF  (p_FAST%CompSub == Module_SD ) THEN      

         ! Copy values for interpolation/extrapolation:
      DO j = 1, p_FAST%InterpOrder + 1
         SD%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !SD_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL SD_CopyInput (SD%Input(1),  SD%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from SD_CopyInput (SD%Input): '//NewLine//ErrMsg )
      END DO
      CALL SD_CopyInput (SD%Input(1),  SD%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from SD_CopyInput (SD%u): '//NewLine//ErrMsg )      
                               
         
         ! Initialize predicted states for j_pc loop:
      CALL SD_CopyContState   ( SD%x,  SD%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from SD_CopyContState (init): '//NewLine//ErrMsg )
      CALL SD_CopyDiscState   (SD%xd, SD%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from SD_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL SD_CopyConstrState ( SD%z,  SD%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from SD_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_SD ) > 1 ) THEN
         CALL SD_CopyOtherState( SD%OtherSt_old, SD%OtherSt, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from SD_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF       
   END IF ! CompSub         
      
   
   IF (p_FAST%CompMooring == Module_MAP) THEN      
         ! Copy values for interpolation/extrapolation:

      DO j = 1, p_FAST%InterpOrder + 1
         MAPp%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !MAP_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL MAP_CopyInput (MAPp%Input(1),  MAPp%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from MAP_CopyInput (MAPp%Input): '//NewLine//ErrMsg )
      END DO
      CALL MAP_CopyInput (MAPp%Input(1),  MAPp%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from MAP_CopyInput (MAPp%u): '//NewLine//ErrMsg )
               
         ! Initialize predicted states for j_pc loop:
      CALL MAP_CopyContState   ( MAPp%x,  MAPp%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from MAP_CopyContState (init): '//NewLine//ErrMsg )
      CALL MAP_CopyDiscState   (MAPp%xd, MAPp%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from MAP_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL MAP_CopyConstrState ( MAPp%z,  MAPp%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from MAP_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_MAP ) > 1 ) THEN
         CALL MAP_CopyOtherState( MAPp%OtherSt, MAPp%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from MAP_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF  
      
   ELSEIF (p_FAST%CompMooring == Module_FEAM) THEN      
         ! Copy values for interpolation/extrapolation:

      DO j = 1, p_FAST%InterpOrder + 1
         FEAM%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !FEAM_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL FEAM_CopyInput (FEAM%Input(1),  FEAM%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from FEAM_CopyInput (FEAM%Input): '//NewLine//ErrMsg )
      END DO
      CALL FEAM_CopyInput (FEAM%Input(1),  FEAM%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from FEAM_CopyInput (MAPp%u): '//NewLine//ErrMsg )
               
         ! Initialize predicted states for j_pc loop:
      CALL FEAM_CopyContState   ( FEAM%x,  FEAM%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from FEAM_CopyContState (init): '//NewLine//ErrMsg )
      CALL FEAM_CopyDiscState   (FEAM%xd, FEAM%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from FEAM_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL FEAM_CopyConstrState ( FEAM%z,  FEAM%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from FEAM_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_FEAM ) > 1 ) THEN
         CALL FEAM_CopyOtherState( FEAM%OtherSt, FEAM%OtherSt_old, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from FEAM_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF           
   END IF ! CompMooring
                 
   
   IF  (p_FAST%CompIce == Module_IceF ) THEN      

         ! Copy values for interpolation/extrapolation:
      DO j = 1, p_FAST%InterpOrder + 1
         IceF%InputTimes(j) = t_initial - (j - 1) * p_FAST%dt
         !IceF_OutputTimes(i) = t_initial - (j - 1) * dt
      END DO

      DO j = 2, p_FAST%InterpOrder + 1
         CALL IceFloe_CopyInput (IceF%Input(1),  IceF%Input(j),  MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from IceFloe_CopyInput (IceF%Input): '//NewLine//ErrMsg )
      END DO
      CALL IceFloe_CopyInput (IceF%Input(1),  IceF%u,  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
         CALL CheckError( ErrStat, 'Message from IceFloe_CopyInput (IceF%u): '//NewLine//ErrMsg )      
                               
         
         ! Initialize predicted states for j_pc loop:
      CALL IceFloe_CopyContState   ( IceF%x,  IceF%x_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from IceFloe_CopyContState (init): '//NewLine//ErrMsg )
      CALL IceFloe_CopyDiscState   (IceF%xd, IceF%xd_pred, MESH_NEWCOPY, Errstat, ErrMsg)  
         CALL CheckError( ErrStat, 'Message from IceFloe_CopyDiscState (init): '//NewLine//ErrMsg )
      CALL IceFloe_CopyConstrState ( IceF%z,  IceF%z_pred, MESH_NEWCOPY, Errstat, ErrMsg)
         CALL CheckError( ErrStat, 'Message from IceFloe_CopyConstrState (init): '//NewLine//ErrMsg )
      IF ( p_FAST%n_substeps( MODULE_IceF ) > 1 ) THEN
         CALL IceFloe_CopyOtherState( IceF%OtherSt_old, IceF%OtherSt, MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from IceFloe_CopyOtherState (init): '//NewLine//ErrMsg )   
      END IF       
      
   ELSEIF  (p_FAST%CompIce == Module_IceD ) THEN      

      DO i = 1,p_FAST%numIceLegs
         
            ! Copy values for interpolation/extrapolation:
         DO j = 1, p_FAST%InterpOrder + 1
            IceD%InputTimes(j,i) = t_initial - (j - 1) * p_FAST%dt
            !IceD%OutputTimes(j,i) = t_initial - (j - 1) * dt
         END DO

         DO j = 2, p_FAST%InterpOrder + 1
            CALL IceD_CopyInput (IceD%Input(1,i),  IceD%Input(j,i),  MESH_NEWCOPY, Errstat, ErrMsg)
               CALL CheckError( ErrStat, 'Message from IceD_CopyInput (IceD%Input): '//NewLine//ErrMsg )
         END DO
         CALL IceD_CopyInput (IceD%Input(1,i),  IceD%u(i),  MESH_NEWCOPY, Errstat, ErrMsg) ! do this to initialize meshes/allocatable arrays for output of ExtrapInterp routine
            CALL CheckError( ErrStat, 'Message from IceD_CopyInput (IceD%u): '//NewLine//ErrMsg )      
                               
         
            ! Initialize predicted states for j_pc loop:
         CALL IceD_CopyContState   ( IceD%x(i),  IceD%x_pred(i), MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from IceD_CopyContState (init): '//NewLine//ErrMsg )
         CALL IceD_CopyDiscState   (IceD%xd(i), IceD%xd_pred(i), MESH_NEWCOPY, Errstat, ErrMsg)  
            CALL CheckError( ErrStat, 'Message from IceD_CopyDiscState (init): '//NewLine//ErrMsg )
         CALL IceD_CopyConstrState ( IceD%z(i),  IceD%z_pred(i), MESH_NEWCOPY, Errstat, ErrMsg)
            CALL CheckError( ErrStat, 'Message from IceD_CopyConstrState (init): '//NewLine//ErrMsg )
         IF ( p_FAST%n_substeps( MODULE_IceD ) > 1 ) THEN
            CALL IceD_CopyOtherState( IceD%OtherSt_old(i), IceD%OtherSt(i), MESH_NEWCOPY, Errstat, ErrMsg)
               CALL CheckError( ErrStat, 'Message from IceD_CopyOtherState (init): '//NewLine//ErrMsg )   
         END IF       
         
      END DO ! numIceLegs
      
   END IF ! CompIce            
   
   
      ! ServoDyn: copy current outputs to store as previous outputs for next step
      ! note that this is a violation of the framework as this is basically a state, but it's only used for the
      ! GH-Bladed DLL, which itself violates the framework....
   CALL SrvD_CopyOutput ( SrvD%y, y_SrvD_prev, MESH_UPDATECOPY, Errstat, ErrMsg)
           
   !...............................................................................................................................
   ! Time Stepping:
   !...............................................................................................................................         
   
   DO n_t_global = 0, n_TMax_m1
      ! this takes data from n_t_global and gets values at n_t_global + 1
  
      t_global_next = t_initial + (n_t_global+1)*p_FAST%DT  ! = t_global + p_FAST%dt
                       
         ! determine if the Jacobian should be calculated this time
      IF ( calcJacobian ) THEN ! this was true (possibly at initialization), so we'll advance the time for the next calculation of the Jacobian
         NextJacCalcTime = t_global + p_FAST%DT_UJac         
      END IF
      
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Step 1.a: Extrapolate Inputs (gives predicted values at t+dt
      ! 
      ! a) Extrapolate inputs (and outputs -- bjj: output extrapolation not necessary, yet) 
      !    to t + dt (i.e., t_global_next); will only be used by modules with an implicit dependence on input data.
      ! b) Shift "window" of the ModName_Input and ModName_Output
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    
      ! ElastoDyn
      CALL ED_Input_ExtrapInterp(ED%Input, ED%InputTimes, ED%u, t_global_next, ErrStat, ErrMsg)
         CALL CheckError(ErrStat,'Message from ED_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
  
      CALL ED_Output_ExtrapInterp(ED%Output, ED%InputTimes, ED%y, t_global_next, ErrStat, ErrMsg) !this extrapolated value is used in the ED-HD coupling
         CALL CheckError(ErrStat,'Message from ED_Output_ExtrapInterp (FAST): '//NewLine//ErrMsg )
         
         
      DO j = p_FAST%InterpOrder, 1, -1
         CALL ED_CopyInput (ED%Input(j),  ED%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL ED_CopyOutput (ED%Output(j),  ED%Output(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         ED%InputTimes(j+1) = ED%InputTimes(j)
         !ED_OutputTimes(j+1) = ED_OutputTimes(j)
      END DO
  
      CALL ED_CopyInput (ED%u,  ED%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
      CALL ED_CopyOutput (ED%y,  ED%Output(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
      ED%InputTimes(1)  = t_global_next
      !ED_OutputTimes(1) = t_global_next 
  
      
      ! AeroDyn
      IF ( p_FAST%CompAero == Module_AD ) THEN
         
         CALL AD_Input_ExtrapInterp(AD%Input, AD%InputTimes, AD%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from AD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         !CALL AD_Output_ExtrapInterp(AD_Output, AD_OutputTimes, AD%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from AD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of AD%Input and AD_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL AD_CopyInput (AD%Input(j),  AD%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL AD_CopyOutput(AD_Output(j), AD_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            AD%InputTimes(j+1)  = AD%InputTimes(j)
           !AD_OutputTimes(j+1) = AD_OutputTimes(j)
         END DO
  
         CALL AD_CopyInput (AD%u,  AD%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
        !CALL AD_CopyOutput(AD%y,  AD_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         AD%InputTimes(1)  = t_global_next          
        !AD_OutputTimes(1) = t_global_next 
            
      END IF  ! CompAero      
      
      
      ! ServoDyn
      IF ( p_FAST%CompServo == Module_SrvD ) THEN
         
         CALL SrvD_Input_ExtrapInterp(SrvD%Input, SrvD%InputTimes, SrvD%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from SrvD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         !CALL SrvD_Output_ExtrapInterp(SrvD_Output, SrvD_OutputTimes, SrvD%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from SrvD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of SrvD%Input and SrvD_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL SrvD_CopyInput (SrvD%Input(j),  SrvD%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL SrvD_CopyOutput(SrvD_Output(j), SrvD_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            SrvD%InputTimes(j+1)  = SrvD%InputTimes(j)
           !SrvD_OutputTimes(j+1) = SrvD_OutputTimes(j)
         END DO
  
         CALL SrvD_CopyInput (SrvD%u,  SrvD%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
        !CALL SrvD_CopyOutput(SrvD%y,  SrvD_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         SrvD%InputTimes(1)  = t_global_next          
        !SrvD_OutputTimes(1) = t_global_next 
            
      END IF  ! ServoDyn       
      
      ! HydroDyn
      IF ( p_FAST%CompHydro == Module_HD ) THEN

         CALL HydroDyn_Input_ExtrapInterp(HD%Input, HD%InputTimes, HD%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from HD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         !CALL HydroDyn_Output_ExtrapInterp(HD_Output, HD_OutputTimes, HD%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from HD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         ! Shift "window" of HD%Input and HD_Output
            
         DO j = p_FAST%InterpOrder, 1, -1

            CALL HydroDyn_CopyInput (HD%Input(j),  HD%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
            !CALL HydroDyn_CopyOutput(HD_Output(j), HD_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            HD%InputTimes(j+1) = HD%InputTimes(j)
            !HD_OutputTimes(j+1)= HD_OutputTimes(j)
         END DO

         CALL HydroDyn_CopyInput (HD%u,  HD%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         !CALL HydroDyn_CopyOutput(HD%y,  HD_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         HD%InputTimes(1) = t_global_next          
         !HD_OutputTimes(1) = t_global_next
            
      END IF  ! HydroDyn

      
      ! SubDyn
      IF ( p_FAST%CompSub == Module_SD ) THEN

         CALL SD_Input_ExtrapInterp(SD%Input, SD%InputTimes, SD%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from SD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
                        
         !CALL SD_Output_ExtrapInterp(SD_Output, SD_OutputTimes, SD%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from SD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of SD%Input and SD_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL SD_CopyInput (SD%Input(j),  SD%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL SD_CopyOutput(SD_Output(j), SD_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            SD%InputTimes(j+1) = SD%InputTimes(j)
            !SD_OutputTimes(j+1) = SD_OutputTimes(j)
         END DO
  
         CALL SD_CopyInput (SD%u,  SD%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         !CALL SD_CopyOutput(SD%y,  SD_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         SD%InputTimes(1) = t_global_next          
         !SD_OutputTimes(1) = t_global_next 
            
      END IF  ! SubDyn
      
      
      ! Mooring (MAP or FEAM)
      ! MAP
      IF ( p_FAST%CompMooring == Module_MAP ) THEN
         
         CALL MAP_Input_ExtrapInterp(MAPp%Input, MAPp%InputTimes, MAPp%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from MAP_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         !CALL MAP_Output_ExtrapInterp(MAP_Output, MAP_OutputTimes, MAPp%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from MAP_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of MAPp%Input and MAP_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL MAP_CopyInput (MAPp%Input(j),  MAPp%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL MAP_CopyOutput(MAP_Output(j), MAP_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            MAPp%InputTimes(j+1) = MAPp%InputTimes(j)
            !MAP_OutputTimes(j+1) = MAP_OutputTimes(j)
         END DO
  
         CALL MAP_CopyInput (MAPp%u,  MAPp%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         !CALL MAP_CopyOutput(MAPp%y,  MAP_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         MAPp%InputTimes(1) = t_global_next          
         !MAP_OutputTimes(1) = t_global_next 
            
      ! FEAM
      ELSEIF ( p_FAST%CompMooring == Module_FEAM ) THEN
         
         CALL FEAM_Input_ExtrapInterp(FEAM%Input, FEAM%InputTimes, FEAM%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from FEAM_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
         !CALL FEAM_Output_ExtrapInterp(FEAM_Output, FEAM_OutputTimes, FEAM%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from FEAM_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of FEAM%Input and FEAM_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL FEAM_CopyInput (FEAM%Input(j),  FEAM%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL FEAM_CopyOutput(FEAM_Output(j), FEAM_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            FEAM%InputTimes( j+1) = FEAM%InputTimes( j)
           !FEAM_OutputTimes(j+1) = FEAM_OutputTimes(j)
         END DO
  
         CALL FEAM_CopyInput (FEAM%u,  FEAM%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
        !CALL FEAM_CopyOutput(FEAM%y,  FEAM_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         FEAM%InputTimes(1)  = t_global_next          
        !FEAM_OutputTimes(1) = t_global_next 
         
      END IF  ! MAP/FEAM
           
            
      ! Ice (IceFloe or IceDyn)
      ! IceFloe
      IF ( p_FAST%CompIce == Module_IceF ) THEN
         
         CALL IceFloe_Input_ExtrapInterp(IceF%Input, IceF%InputTimes, IceF%u, t_global_next, ErrStat, ErrMsg)
            CALL CheckError(ErrStat,'Message from IceFloe_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
                        
         !CALL IceFloe_Output_ExtrapInterp(IceF_Output, IceF_OutputTimes, IceF%y, t_global_next, ErrStat, ErrMsg)
         !   CALL CheckError(ErrStat,'Message from IceFloe_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
         ! Shift "window" of IceF%Input and IceF_Output
  
         DO j = p_FAST%InterpOrder, 1, -1
            CALL IceFloe_CopyInput (IceF%Input(j),  IceF%Input(j+1),  MESH_UPDATECOPY, Errstat, ErrMsg)
           !CALL IceFloe_CopyOutput(IceF_Output(j), IceF_Output(j+1), MESH_UPDATECOPY, Errstat, ErrMsg)
            IceF%InputTimes(j+1) = IceF%InputTimes(j)
            !IceF_OutputTimes(j+1) = IceF_OutputTimes(j)
         END DO
  
         CALL IceFloe_CopyInput (IceF%u,  IceF%Input(1),  MESH_UPDATECOPY, Errstat, ErrMsg)
         !CALL IceFloe_CopyOutput(IceF%y,  IceF_Output(1), MESH_UPDATECOPY, Errstat, ErrMsg)
         IceF%InputTimes(1) = t_global_next          
         !IceF_OutputTimes(1) = t_global_next 
            
      ! IceDyn
      ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN
         
         DO i = 1,p_FAST%numIceLegs
         
            CALL IceD_Input_ExtrapInterp(IceD%Input(:,i), IceD%InputTimes(:,i), IceD%u(i), t_global_next, ErrStat, ErrMsg)
               CALL CheckError(ErrStat,'Message from IceD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
                        
            !CALL IceD_Output_ExtrapInterp(IceD%Output(:,i), IceD%OutputTimes(:,i), IceD%y(i), t_global_next, ErrStat, ErrMsg)
            !   CALL CheckError(ErrStat,'Message from IceD_Input_ExtrapInterp (FAST): '//NewLine//ErrMsg )
            
            
            ! Shift "window" of IceD%Input and IceD%Output
  
            DO j = p_FAST%InterpOrder, 1, -1
               CALL IceD_CopyInput (IceD%Input(j,i),  IceD%Input(j+1,i),  MESH_UPDATECOPY, Errstat, ErrMsg)
              !CALL IceD_CopyOutput(IceD%Output(j,i), IceD%Output(j+1,i), MESH_UPDATECOPY, Errstat, ErrMsg)
               IceD%InputTimes(j+1,i) = IceD%InputTimes(j,i)
               !IceD%OutputTimes(j+1,i) = IceD%OutputTimes(j,i)
            END DO
  
            CALL IceD_CopyInput (IceD%u(i),  IceD%Input(1,i),  MESH_UPDATECOPY, Errstat, ErrMsg)
            !CALL IceD_CopyOutput(IceD%y(i),  IceD%Output(1,i), MESH_UPDATECOPY, Errstat, ErrMsg)
            IceD%InputTimes(1,i) = t_global_next          
            !IceD%OutputTimes(1,i) = t_global_next 
            
         END DO ! numIceLegs
         
      
      END IF  ! IceFloe/IceDyn
      
      ! predictor-corrector loop:
      DO j_pc = 0, p_FAST%NumCrctn
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Step 1.b: Advance states (yield state and constraint values at t_global_next)
      !
      ! x, xd, and z contain val0ues at t_global;
      ! values at t_global_next are stored in the *_pred variables.
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

         !----------------------------------------------------------------------------------------
         ! copy the states at step t_global and get prediction for step t_global_next
         ! (note that we need to copy the states because UpdateStates updates the values
         ! and we need to have the old values [at t_global] for the next j_pc step)
         !----------------------------------------------------------------------------------------
         ! ElastoDyn: get predicted states
         CALL ED_CopyContState   ( ED%x,  ED%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL ED_CopyDiscState   (ED%xd, ED%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL ED_CopyConstrState ( ED%z,  ED%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)

         IF ( p_FAST%n_substeps( MODULE_ED ) > 1 ) THEN
            CALL ED_CopyOtherState( ED%OtherSt, ED%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
         END IF

         DO j_ss = 1, p_FAST%n_substeps( MODULE_ED )
            n_t_module = n_t_global*p_FAST%n_substeps( MODULE_ED ) + j_ss - 1
            t_module   = n_t_module*p_FAST%dt_module( MODULE_ED )
            
            CALL ED_UpdateStates( t_module, n_t_module, ED%Input, ED%InputTimes, ED%p, ED%x_pred, ED%xd_pred, ED%z_pred, ED%OtherSt, ErrStat, ErrMsg )
               CALL CheckError( ErrStat, 'Message from ED_UpdateStates: '//NewLine//ErrMsg )
               
         END DO !j_ss

         
         ! AeroDyn: get predicted states
         IF ( p_FAST%CompAero == Module_AD ) THEN
            CALL AD_CopyContState   ( AD%x,  AD%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL AD_CopyDiscState   (AD%xd, AD%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL AD_CopyConstrState ( AD%z,  AD%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            
            IF ( p_FAST%n_substeps( Module_AD ) > 1 ) THEN
               CALL AD_CopyOtherState( AD%OtherSt, AD%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            DO j_ss = 1, p_FAST%n_substeps( MODULE_AD )
               n_t_module = n_t_global*p_FAST%n_substeps( MODULE_AD ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( MODULE_AD )
            
               CALL AD_UpdateStates( t_module, n_t_module, AD%Input, AD%InputTimes, AD%p, AD%x_pred, AD%xd_pred, AD%z_pred, AD%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from AD_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
         END IF            

                        
         ! ServoDyn: get predicted states
         IF ( p_FAST%CompServo == Module_SrvD ) THEN
            CALL SrvD_CopyContState   ( SrvD%x,  SrvD%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL SrvD_CopyDiscState   (SrvD%xd, SrvD%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL SrvD_CopyConstrState ( SrvD%z,  SrvD%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            
            IF ( p_FAST%n_substeps( Module_SrvD ) > 1 ) THEN
               CALL SrvD_CopyOtherState( SrvD%OtherSt, SrvD%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
         
            DO j_ss = 1, p_FAST%n_substeps( MODULE_AD )
               n_t_module = n_t_global*p_FAST%n_substeps( MODULE_AD ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( MODULE_AD )
               
               CALL SrvD_UpdateStates( t_module, n_t_module, SrvD%Input, SrvD%InputTimes, SrvD%p, SrvD%x_pred, SrvD%xd_pred, SrvD%z_pred, SrvD%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from SrvD_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
         END IF            
            

         ! HydroDyn: get predicted states
         IF ( p_FAST%CompHydro == Module_HD ) THEN
            CALL HydroDyn_CopyContState   ( HD%x,  HD%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL HydroDyn_CopyDiscState   (HD%xd, HD%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL HydroDyn_CopyConstrState ( HD%z,  HD%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            
            IF ( p_FAST%n_substeps( Module_HD ) > 1 ) THEN
               CALL HydroDyn_CopyOtherState( HD%OtherSt, HD%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
         
            DO j_ss = 1, p_FAST%n_substeps( Module_HD )
               n_t_module = n_t_global*p_FAST%n_substeps( Module_HD ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( Module_HD )
               
               CALL HydroDyn_UpdateStates( t_module, n_t_module, HD%Input, HD%InputTimes, HD%p, HD%x_pred, HD%xd_pred, HD%z_pred, HD%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from HydroDyn_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
            
         END IF
            
         
         ! SubDyn: get predicted states
         IF ( p_FAST%CompSub == Module_SD ) THEN
            CALL SD_CopyContState   ( SD%x,  SD%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL SD_CopyDiscState   (SD%xd, SD%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL SD_CopyConstrState ( SD%z,  SD%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)

            IF ( p_FAST%n_substeps( Module_SD ) > 1 ) THEN
               CALL SD_CopyOtherState( SD%OtherSt, SD%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            DO j_ss = 1, p_FAST%n_substeps( Module_SD )
               n_t_module = n_t_global*p_FAST%n_substeps( Module_SD ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( Module_SD )
               
               CALL SD_UpdateStates( t_module, n_t_module, SD%Input, SD%InputTimes, SD%p, SD%x_pred, SD%xd_pred, SD%z_pred, SD%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from SD_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
         END IF
            
            
         ! MAP/FEAM: get predicted states
         IF (p_FAST%CompMooring == Module_MAP) THEN
            CALL MAP_CopyContState   ( MAPp%x,  MAPp%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL MAP_CopyDiscState   (MAPp%xd, MAPp%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL MAP_CopyConstrState ( MAPp%z,  MAPp%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)

            IF ( p_FAST%n_substeps( Module_MAP ) > 1 ) THEN
               CALL MAP_CopyOtherState( MAPp%OtherSt, MAPp%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
         
            DO j_ss = 1, p_FAST%n_substeps( Module_MAP )
               n_t_module = n_t_global*p_FAST%n_substeps( Module_MAP ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( Module_MAP )
               
               CALL MAP_UpdateStates( t_module, n_t_module, MAPp%Input, MAPp%InputTimes, MAPp%p, MAPp%x_pred, MAPp%xd_pred, MAPp%z_pred, MAPp%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from MAP_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
               
         ELSEIF (p_FAST%CompMooring == Module_FEAM) THEN
            CALL FEAM_CopyContState   ( FEAM%x,  FEAM%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL FEAM_CopyDiscState   (FEAM%xd, FEAM%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL FEAM_CopyConstrState ( FEAM%z,  FEAM%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
         
            IF ( p_FAST%n_substeps( Module_FEAM ) > 1 ) THEN
               CALL FEAM_CopyOtherState( FEAM%OtherSt, FEAM%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            DO j_ss = 1, p_FAST%n_substeps( Module_FEAM )
               n_t_module = n_t_global*p_FAST%n_substeps( Module_FEAM ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( Module_FEAM )
               
               CALL FEAM_UpdateStates( t_module, n_t_module, FEAM%Input, FEAM%InputTimes, FEAM%p, FEAM%x_pred, FEAM%xd_pred, FEAM%z_pred, FEAM%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from FEAM_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
               
         END IF
             
         
         ! IceFloe/IceDyn: get predicted states
         IF ( p_FAST%CompIce == Module_IceF ) THEN
            CALL IceFloe_CopyContState   ( IceF%x,  IceF%x_pred, MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL IceFloe_CopyDiscState   (IceF%xd, IceF%xd_pred, MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL IceFloe_CopyConstrState ( IceF%z,  IceF%z_pred, MESH_UPDATECOPY, Errstat, ErrMsg)

            IF ( p_FAST%n_substeps( Module_IceF ) > 1 ) THEN
               CALL IceFloe_CopyOtherState( IceF%OtherSt, IceF%OtherSt_old, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            DO j_ss = 1, p_FAST%n_substeps( Module_IceF )
               n_t_module = n_t_global*p_FAST%n_substeps( Module_IceF ) + j_ss - 1
               t_module   = n_t_module*p_FAST%dt_module( Module_IceF )
               
               CALL IceFloe_UpdateStates( t_module, n_t_module, IceF%Input, IceF%InputTimes, IceF%p, IceF%x_pred, IceF%xd_pred, IceF%z_pred, IceF%OtherSt, ErrStat, ErrMsg )
                  CALL CheckError( ErrStat, 'Message from IceFloe_UpdateStates: '//NewLine//ErrMsg )
            END DO !j_ss
         ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN
            
            DO i=1,p_FAST%numIceLegs
            
               CALL IceD_CopyContState   (IceD%x( i),IceD%x_pred( i), MESH_UPDATECOPY, Errstat, ErrMsg)
               CALL IceD_CopyDiscState   (IceD%xd(i),IceD%xd_pred(i), MESH_UPDATECOPY, Errstat, ErrMsg)  
               CALL IceD_CopyConstrState (IceD%z( i),IceD%z_pred( i), MESH_UPDATECOPY, Errstat, ErrMsg)

               IF ( p_FAST%n_substeps( Module_IceD ) > 1 ) THEN
                  CALL IceD_CopyOtherState( IceD%OtherSt(i), IceD%OtherSt_old(I), MESH_UPDATECOPY, Errstat, ErrMsg)
               END IF
            
               DO j_ss = 1, p_FAST%n_substeps( Module_IceD )
                  n_t_module = n_t_global*p_FAST%n_substeps( Module_IceD ) + j_ss - 1
                  t_module   = n_t_module*p_FAST%dt_module( Module_IceD )
               
                  CALL IceD_UpdateStates( t_module, n_t_module, IceD%Input(:,i), IceD%InputTimes(:,i), IceD%p(i), IceD%x_pred(i), IceD%xd_pred(i), IceD%z_pred(i), IceD%OtherSt(i), ErrStat, ErrMsg )
                     CALL CheckError( ErrStat, 'Message from IceD_UpdateStates: '//NewLine//ErrMsg )
               END DO !j_ss
            END DO
         
         END IF
         
         
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Step 1.c: Input-Output Solve      
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

            CALL CalcOutputs_And_SolveForInputs( t_global_next &
                      , ED%x_pred  , ED%xd_pred  , ED%z_pred   &
                      , SrvD%x_pred, SrvD%xd_pred, SrvD%z_pred &
                      , HD%x_pred  , HD%xd_pred  , HD%z_pred   &
                      , SD%x_pred  , SD%xd_pred  , SD%z_pred   &
                      , MAPp%x_pred , MAPp%xd_pred , MAPp%z_pred  &
                      , AD%x_pred  , AD%xd_pred  , AD%z_pred   &
                      , FEAM%x_pred, FEAM%xd_pred, FEAM%z_pred &
                      , IceF%x_pred, IceF%xd_pred, IceF%z_pred &
                      , IceD%x_pred, IceD%xd_pred, IceD%z_pred &
                      )           

      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Step 2: Correct (continue in loop) 
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
         IF ( j_pc /= p_FAST%NumCrctn)  THEN          ! Don't copy these on the last loop iteration...
                  
            IF ( p_FAST%n_substeps( Module_ED ) > 1 ) THEN
               CALL ED_CopyOtherState( ED%OtherSt_old, ED%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            IF ( p_FAST%n_substeps( Module_AD ) > 1 ) THEN
               CALL AD_CopyOtherState( AD%OtherSt_old, AD%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            IF ( p_FAST%n_substeps( Module_SrvD ) > 1 ) THEN
               CALL SrvD_CopyOtherState( SrvD%OtherSt_old, SrvD%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            IF ( p_FAST%n_substeps( Module_HD ) > 1 ) THEN
               CALL HydroDyn_CopyOtherState( HD%OtherSt_old, HD%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
            
            IF ( p_FAST%n_substeps( Module_SD ) > 1 ) THEN
               CALL SD_CopyOtherState( SD%OtherSt_old, SD%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF

            IF ( p_FAST%n_substeps( Module_MAP ) > 1 ) THEN
               CALL MAP_CopyOtherState( MAPp%OtherSt_old, MAPp%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            ELSEIF ( p_FAST%n_substeps( Module_FEAM ) > 1 ) THEN
               CALL FEAM_CopyOtherState( FEAM%OtherSt_old, FEAM%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            END IF
         
            IF ( p_FAST%n_substeps( Module_IceF ) > 1 ) THEN
               CALL IceFloe_CopyOtherState( IceF%OtherSt_old, IceF%OtherSt, MESH_UPDATECOPY, Errstat, ErrMsg)
            ELSEIF ( p_FAST%n_substeps( Module_IceD ) > 1 ) THEN
               DO i=1,p_FAST%numIceLegs
                  CALL IceD_CopyOtherState( IceD%OtherSt_old(i), IceD%OtherSt(i), MESH_UPDATECOPY, Errstat, ErrMsg)
               END DO
            END IF
            
         END IF
                              
      enddo ! j_pc
      
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Step 3: Save all final variables (advance to next time)
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      
      !----------------------------------------------------------------------------------------
      ! copy the final predicted states from step t_global_next to actual states for that step
      !----------------------------------------------------------------------------------------
      
      ! ElastoDyn: copy final predictions to actual states
      CALL ED_CopyContState   ( ED%x_pred,  ED%x, MESH_UPDATECOPY, Errstat, ErrMsg)
      CALL ED_CopyDiscState   (ED%xd_pred, ED%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
      CALL ED_CopyConstrState ( ED%z_pred,  ED%z, MESH_UPDATECOPY, Errstat, ErrMsg)      
      
      
      ! AeroDyn: copy final predictions to actual states; copy current outputs to next 
      IF ( p_FAST%CompAero == Module_AD ) THEN
         CALL AD_CopyContState   ( AD%x_pred,  AD%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL AD_CopyDiscState   (AD%xd_pred, AD%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL AD_CopyConstrState ( AD%z_pred,  AD%z, MESH_UPDATECOPY, Errstat, ErrMsg)      
      END IF
            
      
      ! ServoDyn: copy final predictions to actual states; copy current outputs to next 
      IF ( p_FAST%CompServo == Module_SrvD ) THEN
         CALL SrvD_CopyContState   ( SrvD%x_pred,  SrvD%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL SrvD_CopyDiscState   (SrvD%xd_pred, SrvD%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL SrvD_CopyConstrState ( SrvD%z_pred,  SrvD%z, MESH_UPDATECOPY, Errstat, ErrMsg)      
      END IF
      
      
      ! HydroDyn: copy final predictions to actual states
      IF ( p_FAST%CompHydro == Module_HD ) THEN         
         CALL HydroDyn_CopyContState   ( HD%x_pred,  HD%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL HydroDyn_CopyDiscState   (HD%xd_pred, HD%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL HydroDyn_CopyConstrState ( HD%z_pred,  HD%z, MESH_UPDATECOPY, Errstat, ErrMsg)
      END IF
            
            
      ! SubDyn: copy final predictions to actual states
      IF ( p_FAST%CompSub == Module_SD ) THEN
         CALL SD_CopyContState   ( SD%x_pred,  SD%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL SD_CopyDiscState   (SD%xd_pred, SD%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL SD_CopyConstrState ( SD%z_pred,  SD%z, MESH_UPDATECOPY, Errstat, ErrMsg)
      END IF
         
      
      ! MAP: copy final predictions to actual states
      IF (p_FAST%CompMooring == Module_MAP) THEN
         CALL MAP_CopyContState   ( MAPp%x_pred,  MAPp%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL MAP_CopyDiscState   (MAPp%xd_pred, MAPp%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL MAP_CopyConstrState ( MAPp%z_pred,  MAPp%z, MESH_UPDATECOPY, Errstat, ErrMsg)
      ELSEIF (p_FAST%CompMooring == Module_FEAM) THEN
         CALL FEAM_CopyContState   ( FEAM%x_pred,  FEAM%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL FEAM_CopyDiscState   (FEAM%xd_pred, FEAM%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL FEAM_CopyConstrState ( FEAM%z_pred,  FEAM%z, MESH_UPDATECOPY, Errstat, ErrMsg)
      END IF
             
            ! IceFloe: copy final predictions to actual states
      IF ( p_FAST%CompIce == Module_IceF ) THEN
         CALL IceFloe_CopyContState   ( IceF%x_pred,  IceF%x, MESH_UPDATECOPY, Errstat, ErrMsg)
         CALL IceFloe_CopyDiscState   (IceF%xd_pred, IceF%xd, MESH_UPDATECOPY, Errstat, ErrMsg)  
         CALL IceFloe_CopyConstrState ( IceF%z_pred,  IceF%z, MESH_UPDATECOPY, Errstat, ErrMsg)
      ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN
         DO i=1,p_FAST%numIceLegs
            CALL IceD_CopyContState   (IceD%x_pred( i), IceD%x( i), MESH_UPDATECOPY, Errstat, ErrMsg)
            CALL IceD_CopyDiscState   (IceD%xd_pred(i), IceD%xd(i), MESH_UPDATECOPY, Errstat, ErrMsg)  
            CALL IceD_CopyConstrState (IceD%z_pred( i), IceD%z( i), MESH_UPDATECOPY, Errstat, ErrMsg)
         END DO
      END IF

            
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! We've advanced everything to the next time step: 
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++                       
      
      ! update the global time 
  
      t_global = t_global_next 
      
      
      !----------------------------------------------------------------------------------------
      ! Check to see if we should output data this time step:
      !----------------------------------------------------------------------------------------

      CALL WriteOutputToFile()
      
      !----------------------------------------------------------------------------------------
      ! Display simulation status every SttsTime-seconds (i.e., n_SttsTime steps):
      !----------------------------------------------------------------------------------------   
      
      IF ( MOD( n_t_global + 1, p_FAST%n_SttsTime ) == 0 ) THEN

         CALL SimStatus( TiLstPrn, PrevClockTime, t_global, p_FAST%TMax )

      ENDIF
      
            
  END DO ! n_t_global
  
  
   !...............................................................................................................................
   !  Write simulation times and stop
   !...............................................................................................................................
   n_t_global =  n_TMax_m1 + 1               ! set this for the message in ProgAbort, if necessary
   CALL ExitThisProgram( Error=.FALSE. )


CONTAINS
   !...............................................................................................................................
   SUBROUTINE WriteOutputToFile()
   ! This routine determines if it's time to write to the output files, and calls the routine to write to the files
   ! with the output data. It should be called after all the output solves for a given time have been completed.
   !...............................................................................................................................
      REAL(DbKi)                      :: OutTime                                 ! Used to determine if output should be generated at this simulation time
      
      IF ( t_global >= p_FAST%TStart )  THEN

            !bjj FIX THIS algorithm!!! this assumes dt_out is an integer multiple of dt; we will probably have to do some interpolation to get these outputs at the times we want them....
            !bjj: perhaps we should do this with integer math on n_t_global now...
         OutTime = NINT( t_global / p_FAST%DT_out ) * p_FAST%DT_out
         IF ( EqualRealNos( t_global, OutTime ) )  THEN

               ! Generate glue-code output file

               CALL WrOutputLine( t_global, p_FAST, y_FAST, IfW_WriteOutput, ED%Output(1)%WriteOutput, SrvD%y%WriteOutput, HD%y%WriteOutput, &
                              SD%y%WriteOutput, MAPp%y%WriteOutput, FEAM%y%WriteOutput, IceF%y%WriteOutput, IceD%y, ErrStat, ErrMsg )
               CALL CheckError( ErrStat, ErrMsg )
                              
         END IF

      ENDIF
      
      IF (p_FAST%WrGraphics) THEN
         CALL WriteMotionMeshesToFile(t_global, ED%Output(1), SD%Input(1), SD%y, HD%Input(1), MAPp%Input(1), y_FAST%UnGra, ErrStat, ErrMsg, TRIM(p_FAST%OutFileRoot)//'.gra') 
      END IF
            
   END SUBROUTINE WriteOutputToFile      
   !...............................................................................................................................
   SUBROUTINE CalcOutputs_And_SolveForInputs( this_time &
                                            , x_ED_this  , xd_ED_this  , z_ED_this   &
                                            , x_SrvD_this, xd_SrvD_this, z_SrvD_this &
                                            , x_HD_this  , xd_HD_this  , z_HD_this   &
                                            , x_SD_this  , xd_SD_this  , z_SD_this   &
                                            , x_MAP_this , xd_MAP_this , z_MAP_this  &
                                            , x_AD_this  , xd_AD_this  , z_AD_this   &
                                            , x_FEAM_this, xd_FEAM_this, z_FEAM_this &
                                            , x_IceF_this, xd_IceF_this, z_IceF_this &
                                            , x_IceD_this, xd_IceD_this, z_IceD_this &
                                            )
   ! This subroutine solves the input-output relations for all of the modules. It is a subroutine because it gets done twice--
   ! once at the start of the n_t_global loop and once in the j_pc loop, using different states.
   ! *** Note that modules that do not have direct feedthrough should be called first. ***
   ! also note that this routine uses variables from the main routine (not declared as arguments)
   !...............................................................................................................................
      REAL(DbKi)                        , intent(in   ) :: this_time                          ! The current simulation time (actual or time of prediction)
      !ElastoDyn:                                     
      TYPE(ED_ContinuousStateType)      , intent(in   ) :: x_ED_this                          ! These continuous states (either actual or predicted)
      TYPE(ED_DiscreteStateType)        , intent(in   ) :: xd_ED_this                         ! These discrete states (either actual or predicted)
      TYPE(ED_ConstraintStateType)      , intent(in   ) :: z_ED_this                          ! These constraint states (either actual or predicted)
      !ServoDyn:                                      
      TYPE(SrvD_ContinuousStateType)    , intent(in   ) :: x_SrvD_this                        ! These continuous states (either actual or predicted)
      TYPE(SrvD_DiscreteStateType)      , intent(in   ) :: xd_SrvD_this                       ! These discrete states (either actual or predicted)
      TYPE(SrvD_ConstraintStateType)    , intent(in   ) :: z_SrvD_this                        ! These constraint states (either actual or predicted)
      !HydroDyn:                                      
      TYPE(HydroDyn_ContinuousStateType), intent(in   ) :: x_HD_this                          ! These continuous states (either actual or predicted)
      TYPE(HydroDyn_DiscreteStateType)  , intent(in   ) :: xd_HD_this                         ! These discrete states (either actual or predicted)
      TYPE(HydroDyn_ConstraintStateType), intent(in   ) :: z_HD_this                          ! These constraint states (either actual or predicted)
      !SubDyn:                                        
      TYPE(SD_ContinuousStateType)      , intent(in   ) :: x_SD_this                          ! These continuous states (either actual or predicted)
      TYPE(SD_DiscreteStateType)        , intent(in   ) :: xd_SD_this                         ! These discrete states (either actual or predicted)
      TYPE(SD_ConstraintStateType)      , intent(in   ) :: z_SD_this                          ! These constraint states (either actual or predicted)
      !MAP: (because of some copying in the Fortran-C interoperability, these are intent INOUT) 
      TYPE(MAP_ContinuousStateType)     , intent(inout) :: x_MAP_this                         ! These continuous states (either actual or predicted) 
      TYPE(MAP_DiscreteStateType)       , intent(inout) :: xd_MAP_this                        ! These discrete states (either actual or predicted)
      TYPE(MAP_ConstraintStateType)     , intent(inout) :: z_MAP_this                         ! These constraint states (either actual or predicted)
      !AD:                                
      TYPE(AD_ContinuousStateType)      , intent(in   ) :: x_AD_this                          ! These continuous states (either actual or predicted)
      TYPE(AD_DiscreteStateType)        , intent(in   ) :: xd_AD_this                         ! These discrete states (either actual or predicted)
      TYPE(AD_ConstraintStateType)      , intent(in   ) :: z_AD_this                          ! These constraint states (either actual or predicted)
      !FEAM:                                
      TYPE(FEAM_ContinuousStateType)    , intent(in   ) :: x_FEAM_this                        ! These continuous states (either actual or predicted)
      TYPE(FEAM_DiscreteStateType)      , intent(in   ) :: xd_FEAM_this                       ! These discrete states (either actual or predicted)
      TYPE(FEAM_ConstraintStateType)    , intent(in   ) :: z_FEAM_this                        ! These constraint states (either actual or predicted)
      !IceFloe:                                
      TYPE(IceFloe_ContinuousStateType) , intent(in   ) :: x_IceF_this                        ! These continuous states (either actual or predicted)
      TYPE(IceFloe_DiscreteStateType)   , intent(in   ) :: xd_IceF_this                       ! These discrete states (either actual or predicted)
      TYPE(IceFloe_ConstraintStateType) , intent(in   ) :: z_IceF_this                        ! These constraint states (either actual or predicted)
      !IceDyn:                                
      TYPE(IceD_ContinuousStateType)    , intent(in   ) :: x_IceD_this(:)                     ! These continuous states (either actual or predicted)
      TYPE(IceD_DiscreteStateType)      , intent(in   ) :: xd_IceD_this(:)                    ! These discrete states (either actual or predicted)
      TYPE(IceD_ConstraintStateType)    , intent(in   ) :: z_IceD_this(:)                     ! These constraint states (either actual or predicted)
                  
         ! Local variable:
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Option 1: solve for consistent inputs and outputs, which is required when Y has direct feedthrough in 
      !           modules coupled together
      ! If you are doing this option at the beginning as well as the end (after option 2), you must initialize the values of
      ! MAPp%y,
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

      IF ( EqualRealNos( this_time, NextJacCalcTime ) .OR. NextJacCalcTime < this_time )  THEN
         calcJacobian = .TRUE.
      ELSE         
         calcJacobian = .FALSE.
      END IF
      
#ifdef SOLVE_OPTION_1_BEFORE_2      

      ! This is OPTION 1 before OPTION 2
      
      ! For cases with HydroDyn and/or SubDyn, it calls ED_CalcOuts (a time-sink) 2 times per step/correction (plus the 6 calls when calculating the Jacobian).
      ! For cases without HydroDyn or SubDyn, it calls ED_CalcOuts 1 time per step/correction.
      
      CALL SolveOption1(this_time &
                        , x_ED_this  , xd_ED_this  , z_ED_this   &
                        , x_HD_this  , xd_HD_this  , z_HD_this   &
                        , x_SD_this  , xd_SD_this  , z_SD_this   &
                        , x_MAP_this , xd_MAP_this , z_MAP_this  &
                        , x_FEAM_this, xd_FEAM_this, z_FEAM_this &
                        , x_IceF_this, xd_IceF_this, z_IceF_this &
                        , x_IceD_this, xd_IceD_this, z_IceD_this &
                        )
      CALL SolveOption2(this_time &
                        , x_SrvD_this, xd_SrvD_this, z_SrvD_this &
                        , x_AD_this  , xd_AD_this  , z_AD_this   &
                        )
                  
#else

      ! This is OPTION 2 before OPTION 1
      
      ! For cases with HydroDyn and/or SubDyn, it calls ED_CalcOuts (a time-sink) 3 times per step/correction (plus the 6 calls when calculating the Jacobian).
      ! In cases without HydroDyn or SubDyn, it is the same as Option 1 before 2 (with 1 call to ED_CalcOuts either way).
      
      ! Option 1 before 2 usually requires a correction step, whereas Option 2 before Option 1 often does not. Thus we are using this option, calling ED_CalcOuts 
      ! 3 times (option 2 before 1 with no correction step) instead of 4 times (option1 before 2 with one correction step). 
      ! Note that this analyisis may change if/when AeroDyn (and ServoDyn?) generate different outputs on correction steps. (Currently, AeroDyn returns old
      ! values until time advances.)

      CALL ED_CalcOutput( this_time, ED%Input(1), ED%p, x_ED_this, xd_ED_this, z_ED_this, ED%OtherSt, ED%Output(1), ErrStat, ErrMsg )
         CALL CheckError( ErrStat, 'Message from ED_CalcOutput: '//NewLine//ErrMsg  )  
         
      CALL SolveOption2(this_time &
                        , x_SrvD_this, xd_SrvD_this, z_SrvD_this &
                        , x_AD_this  , xd_AD_this  , z_AD_this   &
                        )
      
         ! transfer ED outputs to other modules used in option 1:
      CALL Transfer_ED_to_HD_SD_Mooring( p_FAST, ED%Output(1), HD%Input(1), SD%Input(1), MAPp%Input(1), FEAM%Input(1), MeshMapData, ErrStat, ErrMsg )         
         CALL CheckError( ErrStat, ErrMsg  )    
                    
!call wrscr1( 'FAST/init/Morison/LumpedMesh:')      
!call meshprintinfo( CU, HD%Input(1)%morison%LumpedMesh )          
              
      CALL SolveOption1(this_time &
                        , x_ED_this  , xd_ED_this  , z_ED_this   &
                        , x_HD_this  , xd_HD_this  , z_HD_this   &
                        , x_SD_this  , xd_SD_this  , z_SD_this   &
                        , x_MAP_this , xd_MAP_this , z_MAP_this  &
                        , x_FEAM_this, xd_FEAM_this, z_FEAM_this &
                        , x_IceF_this, xd_IceF_this, z_IceF_this &
                        , x_IceD_this, xd_IceD_this, z_IceD_this &
                        )

      !   ! use the ElastoDyn outputs from option1 to update the inputs for AeroDyn and ServoDyn
      ! bjj: if they ever have states to update, we should do these tramsfers!!!!
      !IF ( p_FAST%CompAero == Module_AD ) THEN
      !   CALL AD_InputSolve( AD%Input(1), ED%Output(1), MeshMapData, ErrStat, ErrMsg )
      !      CALL CheckError( ErrStat, 'Message from AD_InputSolve: '//NewLine//ErrMsg  )
      !END IF      
      !
      !IF ( p_FAST%CompServo == Module_SrvD  ) THEN         
      !   CALL SrvD_InputSolve( p_FAST, SrvD%Input(1), ED%Output(1), IfW_WriteOutput )    ! At initialization, we don't have a previous value, so we'll use the guess inputs instead. note that this violates the framework.... (done for the Bladed DLL)
      !END IF         
                     
#endif
                                                                                                      
      !.....................................................................
      ! Reset each mesh's RemapFlag (after calling all InputSolve routines):
      !.....................................................................              
         
      CALL ResetRemapFlags(p_FAST, ED, AD, HD, SD, SrvD, MAPp, FEAM, IceF, IceD)         
         
                        
   END SUBROUTINE CalcOutputs_And_SolveForInputs  
   !...............................................................................................................................
   SUBROUTINE SolveOption1(this_time &
                           , x_ED_this  , xd_ED_this  , z_ED_this   &
                           , x_HD_this  , xd_HD_this  , z_HD_this   &
                           , x_SD_this  , xd_SD_this  , z_SD_this   &
                           , x_MAP_this , xd_MAP_this , z_MAP_this  &
                           , x_FEAM_this, xd_FEAM_this, z_FEAM_this &
                           , x_IceF_this, xd_IceF_this, z_IceF_this &
                           , x_IceD_this, xd_IceD_this, z_IceD_this &
                           )
   ! This routine implements the "option 1" solve for all inputs with direct links to HD, SD, MAP, and the ED platform reference 
   ! point
   !...............................................................................................................................
      REAL(DbKi)                        , intent(in   ) :: this_time                          ! The current simulation time (actual or time of prediction)
      !ElastoDyn:                                     
      TYPE(ED_ContinuousStateType)      , intent(in   ) :: x_ED_this                          ! These continuous states (either actual or predicted)
      TYPE(ED_DiscreteStateType)        , intent(in   ) :: xd_ED_this                         ! These discrete states (either actual or predicted)
      TYPE(ED_ConstraintStateType)      , intent(in   ) :: z_ED_this                          ! These constraint states (either actual or predicted)
      !HydroDyn:                                      
      TYPE(HydroDyn_ContinuousStateType), intent(in   ) :: x_HD_this                          ! These continuous states (either actual or predicted)
      TYPE(HydroDyn_DiscreteStateType)  , intent(in   ) :: xd_HD_this                         ! These discrete states (either actual or predicted)
      TYPE(HydroDyn_ConstraintStateType), intent(in   ) :: z_HD_this                          ! These constraint states (either actual or predicted)
      !SubDyn:                                        
      TYPE(SD_ContinuousStateType)      , intent(in   ) :: x_SD_this                          ! These continuous states (either actual or predicted)
      TYPE(SD_DiscreteStateType)        , intent(in   ) :: xd_SD_this                         ! These discrete states (either actual or predicted)
      TYPE(SD_ConstraintStateType)      , intent(in   ) :: z_SD_this                          ! These constraint states (either actual or predicted)
      !MAP: (because of some copying in the Fortran-C interoperability, these are intent INOUT) 
      TYPE(MAP_ContinuousStateType)     , intent(inout) :: x_MAP_this                         ! These continuous states (either actual or predicted) 
      TYPE(MAP_DiscreteStateType)       , intent(inout) :: xd_MAP_this                        ! These discrete states (either actual or predicted)
      TYPE(MAP_ConstraintStateType)     , intent(inout) :: z_MAP_this                         ! These constraint states (either actual or predicted)
      !FEAM:                                
      TYPE(FEAM_ContinuousStateType)    , intent(in   ) :: x_FEAM_this                        ! These continuous states (either actual or predicted)
      TYPE(FEAM_DiscreteStateType)      , intent(in   ) :: xd_FEAM_this                       ! These discrete states (either actual or predicted)
      TYPE(FEAM_ConstraintStateType)    , intent(in   ) :: z_FEAM_this                        ! These constraint states (either actual or predicted)
      !IceFloe:                                
      TYPE(IceFloe_ContinuousStateType) , intent(in   ) :: x_IceF_this                        ! These continuous states (either actual or predicted)
      TYPE(IceFloe_DiscreteStateType)   , intent(in   ) :: xd_IceF_this                       ! These discrete states (either actual or predicted)
      TYPE(IceFloe_ConstraintStateType) , intent(in   ) :: z_IceF_this                        ! These constraint states (either actual or predicted)
      !IceDyn:                                
      TYPE(IceD_ContinuousStateType)    , intent(in   ) :: x_IceD_this(:)                     ! These continuous states (either actual or predicted)
      TYPE(IceD_DiscreteStateType)      , intent(in   ) :: xd_IceD_this(:)                    ! These discrete states (either actual or predicted)
      TYPE(IceD_ConstraintStateType)    , intent(in   ) :: z_IceD_this(:)                     ! These constraint states (either actual or predicted)
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Option 1: solve for consistent inputs and outputs, which is required when Y has direct feedthrough in 
      !           modules coupled together
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                     
      ! Because MAP, FEAM, and IceFloe do not contain acceleration inputs, we do this outside the DO loop in the ED{_SD}_HD_InputOutput solves.       
      IF ( p_FAST%CompMooring == Module_MAP ) THEN
                  
         CALL MAP_CalcOutput( this_time, MAPp%Input(1), MAPp%p, x_MAP_this, xd_MAP_this, z_MAP_this, MAPp%OtherSt, MAPp%y, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from MAP_CalcOutput: '//NewLine//ErrMsg  )
                        
      ELSEIF ( p_FAST%CompMooring == Module_FEAM ) THEN
         
         CALL FEAM_CalcOutput( this_time, FEAM%Input(1), FEAM%p, x_FEAM_this, xd_FEAM_this, z_FEAM_this, FEAM%OtherSt, FEAM%y, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from FEAM_CalcOutput: '//NewLine//ErrMsg  )
                        
      END IF
      
      IF ( p_FAST%CompIce == Module_IceF ) THEN
                  
         CALL IceFloe_CalcOutput( this_time, IceF%Input(1), IceF%p, x_IceF_this, xd_IceF_this, z_IceF_this, IceF%OtherSt, IceF%y, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from IceFloe_CalcOutput: '//NewLine//ErrMsg  )
      
      ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN
         
         DO i=1,p_FAST%numIceLegs                  
            CALL IceD_CalcOutput( this_time, IceD%Input(1,i), IceD%p(i), x_IceD_this(i), xd_IceD_this(i), z_IceD_this(i), IceD%OtherSt(i), IceD%y(i), ErrStat, ErrMsg )
               CALL CheckError( ErrStat, 'Message from IceD_CalcOutput: '//NewLine//ErrMsg  )
         END DO
         
      END IF
      
      !
      !   ! User Platform Loading
      !IF ( p_FAST%CompUserPtfmLd ) THEN !bjj: array below won't work... routine needs to be converted to UsrPtfm_CalcOutput()
      !!
      !!   CALL UserPtfmLd ( ED%x%QT(1:6), ED%x%QDT(1:6), t, p_FAST%DirRoot, y_UsrPtfm%AddedMass, (/ y_UsrPtfm%Force,y_UsrPtfm%Moment /) )
      !!   CALL UserPtfmLd ( ED%Output(1)%PlatformPtMesh, t, p_FAST%DirRoot, y_UsrPtfm%AddedMass, ED%u%PlatformPtMesh )
      !!
      !!      ! Ensure that the platform added mass matrix returned by UserPtfmLd, PtfmAM, is symmetric; Abort if necessary:
      !!   IF ( .NOT. IsSymmetric( y_UsrPtfm%AddedMass ) ) THEN
      !!      CALL CheckError ( ErrID_Fatal, ' The user-defined platform added mass matrix is unsymmetric.'// &
      !!                        '  Make sure AddedMass returned by UserPtfmLd() is symmetric.'        )
      !!   END IF
      !!
      !END IF
      
      
      IF ( p_FAST%CompSub == Module_SD ) THEN !.OR. p_FAST%CompHydro == Module_HD ) THEN
                                 
         CALL ED_SD_HD_InputOutputSolve(  this_time, p_FAST, calcJacobian &
                                       , ED%Input(1), ED%p, x_ED_this, xd_ED_this, z_ED_this, ED%OtherSt, ED%Output(1) &
                                       , SD%Input(1), SD%p, x_SD_this, xd_SD_this, z_SD_this, SD%OtherSt, SD%y & 
                                       , HD%Input(1), HD%p, x_HD_this, xd_HD_this, z_HD_this, HD%OtherSt, HD%y & 
                                       , MAPp%Input(1),    MAPp%y  &
                                       , FEAM%Input(1),   FEAM%y &   
                                       , IceF%Input(1),   IceF%y &
                                       , IceD%Input(1,:), IceD%y &    ! bjj: I don't really want to make temp copies of input types. perhaps we should pass the whole Input() structure?...
                                       , MeshMapData , ErrStat, ErrMsg )         
            CALL CheckError( ErrStat, ErrMsg  )                                                   
                        
               
      ELSEIF ( p_FAST%CompHydro == Module_HD ) THEN
                                                    
         CALL ED_HD_InputOutputSolve(  this_time, p_FAST, calcJacobian &
                                       , ED%Input(1), ED%p, x_ED_this, xd_ED_this, z_ED_this, ED%OtherSt, ED%Output(1) &
                                       , HD%Input(1), HD%p, x_HD_this, xd_HD_this, z_HD_this, HD%OtherSt, HD%y & 
                                       , MAPp%Input(1), MAPp%y, FEAM%Input(1), FEAM%y &          
                                       , MeshMapData , ErrStat, ErrMsg )         
            CALL CheckError( ErrStat, ErrMsg  )
                                                                  
#ifdef SOLVE_OPTION_1_BEFORE_2      
      ELSE 
         
         CALL ED_CalcOutput( this_time, ED%Input(1), ED%p, x_ED_this, xd_ED_this, z_ED_this, ED%OtherSt, ED%Output(1), ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from ED_CalcOutput: '//NewLine//ErrMsg  )    
#endif         
      END IF ! HD and/or SD coupled to ElastoDyn
                         
   !..................
   ! Set mooring line and ice inputs (which don't have acceleration fields)
   !..................
   
      IF ( p_FAST%CompMooring == Module_MAP ) THEN
         
         ! note: MAP_InputSolve must be called before setting ED loads inputs (so that motions are known for loads [moment] mapping)      
         CALL MAP_InputSolve( MAPp%Input(1), ED%Output(1), MeshMapData, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from MAP_InputSolve: '//NewLine//ErrMsg  )
                                 
      ELSEIF ( p_FAST%CompMooring == Module_FEAM ) THEN
         
         ! note: FEAM_InputSolve must be called before setting ED loads inputs (so that motions are known for loads [moment] mapping)      
         CALL FEAM_InputSolve( FEAM%Input(1), ED%Output(1), MeshMapData, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from FEAM_InputSolve: '//NewLine//ErrMsg  )
                        
      END IF        
      
      IF ( p_FAST%CompIce == Module_IceF ) THEN
         
         CALL IceFloe_InputSolve(  IceF%Input(1), SD%y, MeshMapData, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from IceFloe_InputSolve: '//NewLine//ErrMsg  )
                                 
      ELSEIF ( p_FAST%CompIce == Module_IceD ) THEN
         
         DO i=1,p_FAST%numIceLegs
            
            CALL IceD_InputSolve(  IceD%Input(1,i), SD%y, MeshMapData, i, ErrStat, ErrMsg )
               CALL CheckError( ErrStat, 'Message from IceD_InputSolve: '//NewLine//ErrMsg  )
               
         END DO
         
      END IF        
      
#ifdef DEBUG_MESH_TRANSFER_ICE
         CALL WrScr('********************************************************')
         CALL WrScr('****   IceF to SD point-to-point                   *****')
         CALL WrScr('********************************************************')
         CALL WriteMappingTransferToFile(SD%Input(1)%LMesh, SD%y%Y2Mesh, IceF%Input(1)%iceMesh, IceF%y%iceMesh,&
               MeshMapData%SD_P_2_IceF_P, MeshMapData%IceF_P_2_SD_P, &
               'SD_y2_IceF_Meshes_t'//TRIM(Num2LStr(0))//'.PI.bin' )

         
         CALL WriteMappingTransferToFile(SD%Input(1)%LMesh, SD%y%Y2Mesh, HD%Input(1)%Morison%LumpedMesh, HD%y%Morison%LumpedMesh,&
               MeshMapData%SD_P_2_HD_M_P, MeshMapData%HD_M_P_2_SD_P, &
               'SD_y2_HD_M_L_Meshes_t'//TRIM(Num2LStr(0))//'.PHL.bin' )
         
         CALL WriteMappingTransferToFile(SD%Input(1)%LMesh, SD%y%Y2Mesh, HD%Input(1)%Morison%DistribMesh, HD%y%Morison%DistribMesh,&
               MeshMapData%SD_P_2_HD_M_L, MeshMapData%HD_M_L_2_SD_P, &
               'SD_y2_HD_M_D_Meshes_t'//TRIM(Num2LStr(0))//'.PHD.bin' )
         
         
         !print *
         !pause         
#endif         
                  
   END SUBROUTINE SolveOption1
   !...............................................................................................................................
   SUBROUTINE SolveOption2(this_time &
                           , x_SrvD_this, xd_SrvD_this, z_SrvD_this &
                           , x_AD_this  , xd_AD_this  , z_AD_this   &
                           )
   ! This routine implements the "option 2" solve for all inputs without direct links to HD, SD, MAP, or the ED platform reference 
   ! point
   !...............................................................................................................................
      REAL(DbKi)                        , intent(in   ) :: this_time                          ! The current simulation time (actual or time of prediction)
      !ServoDyn:                                      
      TYPE(SrvD_ContinuousStateType)    , intent(in   ) :: x_SrvD_this                        ! These continuous states (either actual or predicted)
      TYPE(SrvD_DiscreteStateType)      , intent(in   ) :: xd_SrvD_this                       ! These discrete states (either actual or predicted)
      TYPE(SrvD_ConstraintStateType)    , intent(in   ) :: z_SrvD_this                        ! These constraint states (either actual or predicted)
      !AD:                                
      TYPE(AD_ContinuousStateType)      , intent(in   ) :: x_AD_this                          ! These continuous states (either actual or predicted)
      TYPE(AD_DiscreteStateType)        , intent(in   ) :: xd_AD_this                         ! These discrete states (either actual or predicted)
      TYPE(AD_ConstraintStateType)      , intent(in   ) :: z_AD_this                          ! These constraint states (either actual or predicted)
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
      ! Option 2: Solve for inputs based only on the current outputs. This is much faster than option 1 when the coupled modules
      !           do not have direct feedthrough.
      !++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            
      IF ( p_FAST%CompAero == Module_AD ) THEN !bjj: do this before calling SrvD so that SrvD can get the correct wind speed...
         CALL AD_InputSolve( AD%Input(1), ED%Output(1), MeshMapData, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from AD_InputSolve: '//NewLine//ErrMsg  )
         
         CALL AD_CalcOutput( this_time, AD%Input(1), AD%p, x_AD_this, xd_AD_this, z_AD_this, AD%OtherSt, AD%y, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from AD_CalcOutput: '//NewLine//ErrMsg  )
 
!bjj FIX THIS>>>>>         
            !InflowWind outputs
         IF ( allocated(AD%y%IfW_Outputs%WriteOutput) ) &
         IfW_WriteOutput = AD%y%IfW_Outputs%WriteOutput
!<<<         

      END IF
      
                       
      IF ( p_FAST%CompServo == Module_SrvD  ) THEN
         
            ! note that the inputs at step(n) for ServoDyn include the outputs from step(n-1)
         IF ( n_t_global < 0 ) THEN
            CALL SrvD_InputSolve( p_FAST, SrvD%Input(1), ED%Output(1), IfW_WriteOutput )    ! At initialization, we don't have a previous value, so we'll use the guess inputs instead. note that this violates the framework.... (done for the Bladed DLL)
         ELSE
            CALL SrvD_InputSolve( p_FAST, SrvD%Input(1), ED%Output(1), IfW_WriteOutput, y_SrvD_prev   ) 
         END IF

         CALL SrvD_CalcOutput( this_time, SrvD%Input(1), SrvD%p, x_SrvD_this, xd_SrvD_this, z_SrvD_this, SrvD%OtherSt, SrvD%y, ErrStat, ErrMsg )
            CALL CheckError( ErrStat, 'Message from SrvD_CalcOutput: '//NewLine//ErrMsg  )

      END IF
      
      
         ! User Tower Loading
      IF ( p_FAST%CompUserTwrLd ) THEN !bjj: array below won't work... routine needs to be converted to UsrTwr_CalcOutput()
      !   CALL UserTwrLd ( JNode, X, XD, t, p_FAST%DirRoot, y_UsrTwr%AddedMass(1:6,1:6,J), (/ y_UsrTwr%Force(:,J),y_UsrTwr%Moment(:,J) /) )
      END IF

        
      
      !bjj: note ED%Input(1) may be a sibling mesh of output, but ED%u is not (routine may update something that needs to be shared between siblings)      
      CALL ED_InputSolve( p_FAST, ED%Input(1), ED%Output(1), AD%y, SrvD%y, MeshMapData, ErrStat, ErrMsg )
         CALL CheckError( ErrStat, 'Message from ED_InputSolve: '//NewLine//ErrMsg  )   
   
   
   END SUBROUTINE SolveOption2
   !...............................................................................................................................
   SUBROUTINE ExitThisProgram( Error, ErrLev )
   ! This subroutine is called when FAST exits. It calls all the modules' end routines and cleans up variables declared in the
   ! main program. If there was an error, it also aborts. Otherwise, it prints the run times and performs a normal exit.
   !...............................................................................................................................

         ! Passed arguments
      LOGICAL,        INTENT(IN)           :: Error        ! flag to determine if this is an abort or normal stop
      INTEGER(IntKi), INTENT(IN), OPTIONAL :: ErrLev       ! Error level when Error == .TRUE. (required when Error is .TRUE.)

         ! Local arguments:
      INTEGER(IntKi)                       :: ErrStat2                                    ! Error status
      CHARACTER(LEN(ErrMsg))               :: ErrMsg2                                     ! Error message

      
      
      !...............................................................................................................................
      ! Clean up modules (and write binary FAST output file), destroy any other variables
      !...............................................................................................................................
!bjj: if any of these operations produces an error >= AbortErrLev, we should also set Error = TRUE and update ErrLev appropriately.

      CALL FAST_End( p_FAST, y_FAST, ErrStat2, ErrMsg2 )
      IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

      IF ( p_FAST%ModuleInitialized(Module_ED) ) THEN
         CALL ED_End(   ED%Input(1),   ED%p,   ED%x,   ED%xd,   ED%z,   ED%OtherSt,   ED%Output(1),   ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF

      IF ( p_FAST%ModuleInitialized(Module_AD) ) THEN
         CALL AD_End(   AD%Input(1),   AD%p,   AD%x,   AD%xd,   AD%z,   AD%OtherSt,   AD%y,   ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF
      
      IF ( p_FAST%ModuleInitialized(Module_SrvD) ) THEN
         CALL SrvD_End( SrvD%Input(1), SrvD%p, SrvD%x, SrvD%xd, SrvD%z, SrvD%OtherSt, SrvD%y, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF

      IF ( p_FAST%ModuleInitialized(Module_HD) ) THEN
         CALL HydroDyn_End(    HD%Input(1),   HD%p,   HD%x,   HD%xd,   HD%z,   HD%OtherSt,   HD%y,   ErrStat2, ErrMsg2)
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF

      IF ( p_FAST%ModuleInitialized(Module_SD) ) THEN
         CALL SD_End(    SD%Input(1),   SD%p,   SD%x,   SD%xd,   SD%z,   SD%OtherSt,   SD%y,   ErrStat2, ErrMsg2)
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF
      
      IF ( p_FAST%ModuleInitialized(Module_MAP) ) THEN
         CALL MAP_End(    MAPp%Input(1),   MAPp%p,   MAPp%x,   MAPp%xd,   MAPp%z,   MAPp%OtherSt,   MAPp%y,   ErrStat2, ErrMsg2)
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      ELSEIF ( p_FAST%ModuleInitialized(Module_FEAM) ) THEN
         CALL FEAM_End(   FEAM%Input(1),  FEAM%p,  FEAM%x,  FEAM%xd,  FEAM%z,  FEAM%OtherSt,  FEAM%y,  ErrStat2, ErrMsg2)
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      END IF
      
      IF ( p_FAST%ModuleInitialized(Module_IceF) ) THEN
         CALL IceFloe_End(IceF%Input(1),  IceF%p,  IceF%x,  IceF%xd,  IceF%z,  IceF%OtherSt,  IceF%y,  ErrStat2, ErrMsg2)
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      ELSEIF ( p_FAST%ModuleInitialized(Module_IceD) ) THEN
         
         DO i=1,p_FAST%numIceLegs                     
            CALL IceD_End(IceD%Input(1,i),  IceD%p(i),  IceD%x(i),  IceD%xd(i),  IceD%z(i),  IceD%OtherSt(i),  IceD%y(i),  ErrStat2, ErrMsg2)
            IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )            
         END DO
         
      END IF
      
      
      ! -------------------------------------------------------------------------
      ! Initialization input/output variables:
      !     in case we didn't get them destroyed earlier....
      ! -------------------------------------------------------------------------

      CALL ED_DestroyInitInput(  InitInData_ED,        ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL ED_DestroyInitOutput( InitOutData_ED,       ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))

      CALL AD_DestroyInitInput(  InitInData_AD,        ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL AD_DestroyInitOutput( InitOutData_AD,       ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
            
      CALL SrvD_DestroyInitInput(  InitInData_SrvD,    ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL SrvD_DestroyInitOutput( InitOutData_SrvD,   ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))

      CALL HydroDyn_DestroyInitInput(  InitInData_HD,  ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL HydroDyn_DestroyInitOutput( InitOutData_HD, ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))

      CALL SD_DestroyInitInput(  InitInData_SD,        ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL SD_DestroyInitOutput( InitOutData_SD,       ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
                                                       
      CALL MAP_DestroyInitInput(  InitInData_MAP,      ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL MAP_DestroyInitOutput( InitOutData_MAP,     ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      
      CALL FEAM_DestroyInitInput(  InitInData_FEAM,    ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL FEAM_DestroyInitOutput( InitOutData_FEAM,   ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      
      CALL IceFloe_DestroyInitInput(  InitInData_IceF, ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL IceFloe_DestroyInitOutput( InitOutData_IceF,ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))

      CALL IceD_DestroyInitInput(     InitInData_IceD, ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      CALL IceD_DestroyInitOutput(    InitOutData_IceD,ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
      
      
      ! -------------------------------------------------------------------------
      ! Deallocate/Destroy structures associated with mesh mapping
      ! -------------------------------------------------------------------------

      CALL Destroy_FAST_ModuleMapType( MeshMapData, ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr(TRIM(ErrMsg2))
                              
      ! -------------------------------------------------------------------------
      ! variables for ExtrapInterp:
      ! -------------------------------------------------------------------------

      ! ElastoDyn
      CALL ED_DestroyInput( ED%u, ErrStat2, ErrMsg2 )
      IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

      CALL ED_DestroyOutput( ED%y, ErrStat2, ErrMsg2 )
      IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      
      IF ( ALLOCATED(ED%Input)   ) THEN
         DO j = 2,p_FAST%InterpOrder+1  !note that ED%Input(1) was destroyed in ED_End
            CALL ED_DestroyInput( ED%Input(j), ErrStat2, ErrMsg2 )
            IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )                  
         END DO
         DEALLOCATE( ED%Input )
      END IF

      IF ( ALLOCATED(ED%Output)   ) THEN
         DO j = 2,p_FAST%InterpOrder+1  !note that ED%Input(1) was destroyed in ED_End
            CALL ED_DestroyOutput( ED%Output(j), ErrStat2, ErrMsg2 )
            IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )         
         END DO
         DEALLOCATE( ED%Output )
      END IF            
      
      IF ( ALLOCATED(ED%InputTimes) ) DEALLOCATE( ED%InputTimes )
      
      
      ! ServoDyn     
      IF ( ALLOCATED(SrvD%Input)      ) THEN
         
         IF ( p_FAST%CompServo == Module_SrvD ) THEN
         
            CALL SrvD_DestroyOutput( y_SrvD_prev, ErrStat2, ErrMsg2)
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
                  
            CALL SrvD_DestroyInput( SrvD%u, ErrStat2, ErrMsg2 )
            IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

            DO j = 2,p_FAST%InterpOrder+1 !note that SrvD%Input(1) was destroyed in SrvD_End
               CALL SrvD_DestroyInput( SrvD%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
         END IF
         
         DEALLOCATE( SrvD%Input )
      END IF

      IF ( ALLOCATED(SrvD%InputTimes) ) DEALLOCATE( SrvD%InputTimes )
                           
         
      ! AeroDyn
      IF ( p_FAST%CompAero == Module_AD ) THEN
         CALL AD_DestroyInput( AD%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(AD%Input)      )  THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that AD%Input(1) was destroyed in AD_End
               CALL AD_DestroyInput( AD%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( AD%Input )
         END IF
      ELSE
         IF ( ALLOCATED(AD%Input)      ) DEALLOCATE( AD%Input )         
      END IF

      IF ( ALLOCATED(AD%InputTimes) ) DEALLOCATE( AD%InputTimes )
                  
      
      ! HydroDyn
      IF ( p_FAST%CompHydro == Module_HD ) THEN                  
         CALL HydroDyn_DestroyInput( HD%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(HD%Input)      )  THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that HD%Input(1) was destroyed in HydroDyn_End
               CALL HydroDyn_DestroyInput( HD%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( HD%Input )
         END IF
      ELSE
         IF ( ALLOCATED(HD%Input)      ) DEALLOCATE( HD%Input )         
      END IF

      IF ( ALLOCATED(HD%InputTimes) ) DEALLOCATE( HD%InputTimes )

      ! SubDyn
      IF ( p_FAST%CompSub == Module_SD ) THEN
         CALL SD_DestroyInput( SD%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(SD%Input)      ) THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that SD%Input(1) was destroyed in SD_End
               CALL SD_DestroyInput( SD%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( SD%Input )
         END IF
      ELSE
         IF ( ALLOCATED(SD%Input)      ) DEALLOCATE( SD%Input )
      END IF

      IF ( ALLOCATED(SD%InputTimes) ) DEALLOCATE( SD%InputTimes )
      
      ! MAP      
      IF ( p_FAST%ModuleInitialized(Module_MAP)  ) THEN        
         CALL MAP_DestroyInput( MAPp%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(MAPp%Input)      ) THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that SD%Input(1) was destroyed in MAP_End
               CALL MAP_DestroyInput( MAPp%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( MAPp%Input )
         END IF
      ELSE
         IF ( ALLOCATED(MAPp%Input)      ) DEALLOCATE( MAPp%Input )
      END IF

      IF ( ALLOCATED(MAPp%InputTimes) ) DEALLOCATE( MAPp%InputTimes )
      
      
      ! FEAM      
      IF ( p_FAST%ModuleInitialized(Module_FEAM)  ) THEN        
         CALL FEAM_DestroyInput( FEAM%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(FEAM%Input)      ) THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that SD%Input(1) was destroyed in MAP_End
               CALL FEAM_DestroyInput( FEAM%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( FEAM%Input )
         END IF
      ELSE
         IF ( ALLOCATED(FEAM%Input)      ) DEALLOCATE( FEAM%Input )
      END IF

      IF ( ALLOCATED(FEAM%InputTimes) ) DEALLOCATE( FEAM%InputTimes )
      
      ! IceFloe
      IF ( p_FAST%CompIce == Module_IceF ) THEN
         CALL IceFloe_DestroyInput( IceF%u, ErrStat2, ErrMsg2 )
         IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )

         IF ( ALLOCATED(IceF%Input)      ) THEN
            DO j = 2,p_FAST%InterpOrder+1 !note that IceF%Input(1) was destroyed in IceFloe_End
               CALL IceFloe_DestroyInput( IceF%Input(j), ErrStat2, ErrMsg2 )
               IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
            END DO
            DEALLOCATE( IceF%Input )
         END IF
      ELSE
         IF ( ALLOCATED(IceF%Input)      ) DEALLOCATE( IceF%Input )
      END IF

      IF ( ALLOCATED(IceF%InputTimes) ) DEALLOCATE( IceF%InputTimes )      
      
      
      ! IceDyn
      IF ( p_FAST%CompIce == Module_IceD ) THEN
                                          
         IF ( ALLOCATED(IceD%Input)  ) THEN
            DO i=1,p_FAST%numIceLegs
               DO j = 2,p_FAST%InterpOrder+1 !note that IceD%Input(1,:) was destroyed in ID_End
                  CALL IceD_DestroyInput( IceD%Input(j,i), ErrStat2, ErrMsg2 );   IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               END DO
            END DO
         END IF
                              
         IF ( ALLOCATED(IceD%OtherSt_old) ) THEN  ! and all the others that need to be allocated...
            DO i=1,p_FAST%numIceLegs
               CALL IceD_DestroyContState(  IceD%x(          i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyDiscState(  IceD%xd(         i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyConstrState(IceD%z(          i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyOtherState( IceD%OtherSt(    i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyParam(      IceD%p(          i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyInput(      IceD%u(          i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyOutput(     IceD%y(          i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )                              
               CALL IceD_DestroyContState(  IceD%x_pred(     i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyDiscState(  IceD%xd_pred(    i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyConstrState(IceD%z_pred(     i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
               CALL IceD_DestroyOtherState( IceD%OtherSt_old(i), ErrStat2, ErrMsg2 ); IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )                              
            END DO                        
         END IF         
         
      END IF 
      
      IF ( ALLOCATED(IceD%Input      ) ) DEALLOCATE( IceD%Input      )      
      IF ( ALLOCATED(IceD%InputTimes ) ) DEALLOCATE( IceD%InputTimes )      
      IF ( ALLOCATED(IceD%x          ) ) DEALLOCATE( IceD%x          )      
      IF ( ALLOCATED(IceD%xd         ) ) DEALLOCATE( IceD%xd         )      
      IF ( ALLOCATED(IceD%z          ) ) DEALLOCATE( IceD%z          )      
      IF ( ALLOCATED(IceD%OtherSt    ) ) DEALLOCATE( IceD%OtherSt    )      
      IF ( ALLOCATED(IceD%p          ) ) DEALLOCATE( IceD%p          )      
      IF ( ALLOCATED(IceD%u          ) ) DEALLOCATE( IceD%u          )      
      IF ( ALLOCATED(IceD%y          ) ) DEALLOCATE( IceD%y          )      
      IF ( ALLOCATED(IceD%x_pred     ) ) DEALLOCATE( IceD%x_pred     )      
      IF ( ALLOCATED(IceD%xd_pred    ) ) DEALLOCATE( IceD%xd_pred    )      
      IF ( ALLOCATED(IceD%z_pred     ) ) DEALLOCATE( IceD%z_pred     )      
      IF ( ALLOCATED(IceD%OtherSt_old) ) DEALLOCATE( IceD%OtherSt_old)      
                        
      ! -------------------------------------------------------------------------
      ! predicted state variables:
      ! -------------------------------------------------------------------------

      CALL ED_DestroyContState   (  ED%x_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL ED_DestroyDiscState   ( ED%xd_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL ED_DestroyConstrState (  ED%z_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL ED_DestroyOtherState  (  ED%OtherSt_old,       ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
                                                          
      CALL AD_DestroyContState   (  AD%x_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL AD_DestroyDiscState   ( AD%xd_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL AD_DestroyConstrState (  AD%z_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL AD_DestroyOtherState  (  AD%OtherSt_old,       ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
                                                          
      CALL SrvD_DestroyContState   (  SrvD%x_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL SrvD_DestroyDiscState   ( SrvD%xd_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL SrvD_DestroyConstrState (  SrvD%z_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL SrvD_DestroyOtherState  (  SrvD%OtherSt_old,   ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
                                                          
      CALL HydroDyn_DestroyContState   (  HD%x_pred,      ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL HydroDyn_DestroyDiscState   ( HD%xd_pred,      ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL HydroDyn_DestroyConstrState (  HD%z_pred,      ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL HydroDyn_DestroyOtherState  (  HD%OtherSt_old, ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
                                                        
      CALL SD_DestroyContState   (  SD%x_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL SD_DestroyDiscState   ( SD%xd_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL SD_DestroyConstrState (  SD%z_pred,            ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL SD_DestroyOtherState  (  SD%OtherSt_old,       ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
                                                          
      CALL MAP_DestroyContState   (  MAPp%x_pred,          ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL MAP_DestroyDiscState   ( MAPp%xd_pred,          ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL MAP_DestroyConstrState (  MAPp%z_pred,          ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL MAP_DestroyOtherState  (  MAPp%OtherSt_old,     ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  

!TODO:
!BJJ: do I have to call these other routines for MAP's c_obj stuff, like Marco indicates in his glue code?
!CALL MAP_InitInput_Destroy ( MAP_InitInput%C_obj%object )              
      
      CALL FEAM_DestroyContState   (  FEAM%x_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL FEAM_DestroyDiscState   ( FEAM%xd_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL FEAM_DestroyConstrState (  FEAM%z_pred,        ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL FEAM_DestroyOtherState  (  FEAM%OtherSt_old,   ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      
      CALL IceFloe_DestroyContState   (  IceF%x_pred,     ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )
      CALL IceFloe_DestroyDiscState   ( IceF%xd_pred,     ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL IceFloe_DestroyConstrState (  IceF%z_pred,     ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      CALL IceFloe_DestroyOtherState  (  IceF%OtherSt_old,ErrStat2, ErrMsg2);  IF ( ErrStat2 /= ErrID_None ) CALL WrScr( TRIM(ErrMsg2) )  
      
      
      
      !............................................................................................................................
      ! Set exit error code if there was an error;
      !............................................................................................................................
      IF (Error) THEN !This assumes PRESENT(ErrID) is also .TRUE. :
         IF ( t_global < t_initial ) THEN
            ErrMsg = 'at initialization'
         ELSEIF ( n_t_global > n_TMax_m1 ) THEN
            ErrMsg = 'after computing the solution'
         ELSE            
            ErrMsg = 'at simulation time '//TRIM(Num2LStr(t_global))//' of '//TRIM(Num2LStr(p_FAST%TMax))//' seconds'
         END IF
                    
         
         CALL ProgAbort( 'FAST encountered an error '//TRIM(ErrMsg)//'.'//NewLine//' Simulation error level: '&
                         //TRIM(GetErrStr(ErrLev)), TrapErrors=.FALSE., TimeWait=3._ReKi )  ! wait 3 seconds (in case they double-clicked and got an error)
      END IF
      
      !............................................................................................................................
      !  Write simulation times and stop
      !............................................................................................................................

      CALL RunTimes( StrtTime, UsrTime1, SimStrtTime, UsrTime2, t_global, UsrTimeDiff )

      CALL NormStop( )


   END SUBROUTINE ExitThisProgram
   !...............................................................................................................................
   SUBROUTINE CheckError(ErrID,Msg)
   ! This subroutine sets the error message and level and cleans up if the error is >= AbortErrLev
   !...............................................................................................................................

         ! Passed arguments
      INTEGER(IntKi), INTENT(IN) :: ErrID       ! The error identifier (ErrStat)
      CHARACTER(*),   INTENT(IN) :: Msg         ! The error message (ErrMsg)


      IF ( ErrID /= ErrID_None ) THEN
         CALL WrScr( NewLine//TRIM(Msg)//NewLine )
         IF ( ErrID >= AbortErrLev ) CALL ExitThisProgram( Error=.TRUE., ErrLev=ErrID )
      END IF


   END SUBROUTINE CheckError   
   !...............................................................................................................................  

END PROGRAM FAST
!=======================================================================
