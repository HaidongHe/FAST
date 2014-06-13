------- FAST v8.08.* INPUT FILE ------------------------------------------------
FAST Certification Test #01: AWT-27CR2 with many DOFs with fixed yaw error and steady wind
---------------------- SIMULATION CONTROL --------------------------------------
False         Echo            - Echo input data to <RootName>.ech (flag)
"FATAL"       AbortLevel      - Error level when simulation should abort {"WARNING", "SEVERE", "FATAL"} (string)
         20   TMax            - Total run time (s)
      0.004   DT              - Recommended module time step (s)
          1   InterpOrder     - Interpolation order for input/output time history {1=linear, 2=quadratic} (-)
          0   NumCrctn        - Number of correction iterations {0=explicit calculation, i.e., no corrections} (-)
      99999   DT_UJac         - Time between calls to get Jacobians (s)
      1E+06   UJacSclFact     - Scaling factor used in Jacobians (-)
---------------------- FEATURE SWITCHES AND FLAGS ------------------------------
          1   CompElast       - Compute structural dynamics (switch) {1=ElastoDyn; 2=ElastoDyn + BeamDyn for blades}
          1   CompAero        - Compute aerodynamic loads (switch) {0=None; 1=AeroDyn}
          1   CompServo       - Compute control and electrical-drive dynamics (switch) {0=None; 1=ServoDyn}
          0   CompHydro       - Compute hydrodynamic loads (switch) {0=None; 1=HydroDyn}
          0   CompSub         - Compute sub-structural dynamics (switch) {0=None; 1=SubDyn}
          0   CompMooring     - Compute mooring system (switch) {0=None; 1=MAP; 2=FEAMooring}
          0   CompIce         - Compute ice loads (switch) {0=None; 1=IceFloe; 2=IceDyn}
False         CompUserPtfmLd  - Compute additional platform loading {false: none; true: user-defined from routine UserPtfmLd} (flag)
False         CompUserTwrLd   - Compute additional tower loading {false: none; true: user-defined from routine UserTwrLd} (flag)
---------------------- INPUT FILES ---------------------------------------------
"AWT27/Test01_ElastoDyn.dat"    EDFile          - Name of file containing ElastoDyn input parameters (quoted string)
"unused"      BDBldFile(1)    - Name of file containing BeamDyn input parameters for blade 1 (quoted string)
"unused"      BDBldFile(2)    - Name of file containing BeamDyn input parameters for blade 2 (quoted string)
"unused"      BDBldFile(3)    - Name of file containing BeamDyn input parameters for blade 3 (quoted string)
"AWT27/Test01_AD.ipt"    AeroFile        - Name of file containing aerodynamic input parameters (quoted string)
"AWT27/Test01_ServoDyn.dat"    ServoFile       - Name of file containing control and electrical-drive input parameters (quoted string)
"unused"      HydroFile       - Name of file containing hydrodynamic input parameters (quoted string)
"unused"      SubFile         - Name of file containing sub-structural input parameters (quoted string)
"unused"      MooringFile     - Name of file containing mooring system input parameters (quoted string)
"unused"      IceFile         - Name of file containing ice input parameters (quoted string)
---------------------- OUTPUT --------------------------------------------------
True          SumPrint        - Print summary data to "<RootName>.sum" (flag)
          1   SttsTime        - Amount of time between screen status messages (sec)
       0.02   DT_Out          - Time step for tabular output (sec)
         10   TStart          - Time to begin tabular output (s)
          1   OutFileFmt      - Format for tabular (time-marching) output file(s) (1: text file [<RootName>.out], 2: binary file [<RootName>.outb], 3: both) (switch)
True          TabDelim        - Use tab delimiters in text tabular output file? (flag) {uses spaces if false}
"ES10.3E2"    OutFmt          - Format used for text tabular output (except time).  Resulting field should be 10 characters. (quoted string)
