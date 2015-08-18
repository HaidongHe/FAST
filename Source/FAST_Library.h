// routines in FAST_Library_$(PlatformName).dll
#include "OpenFOAM_Types.h"
extern void FAST_OpFM_Restart(char *CheckpointRootName, int *AbortErrLev, double * dt, OpFM_InputType_t* OpFM_Input, OpFM_OutputType_t* OpFM_Output, int *ErrStat, char *ErrMsg);
extern void FAST_OpFM_Init(char *InputFileName, int *AbortErrLev, double * dt, OpFM_InputType_t* OpFM_Input, OpFM_OutputType_t* OpFM_Output, int *ErrStat, char *ErrMsg);
extern void FAST_OpFM_Solution0(int *ErrStat, char *ErrMsg);
extern void FAST_OpFM_Step(int *ErrStat, char *ErrMsg);

extern void FAST_Restart(char *CheckpointRootName, int *AbortErrLev, int * NumOuts, double * dt, int *ErrStat, char *ErrMsg);
extern void FAST_Sizes(double *TMax, double *InitInputAry, char *InputFileName, int *AbortErrLev, int * NumOuts, double * dt, int *ErrStat, char *ErrMsg, char *ChannelNames);
extern void FAST_Start( int *NumInputs_c, int *NumOutputs_c, double *InputAry, double *OutputAry, int *ErrStat, char *ErrMsg);
extern void FAST_Update(int *NumInputs_c, int *NumOutputs_c, double *InputAry, double *OutputAry, int *ErrStat, char *ErrMsg);
extern void FAST_End();
extern void FAST_CreateCheckpoint(char *CheckpointRootName, int *ErrStat, char *ErrMsg);

// some constants (keep these synced with values in FAST's fortran code)
#define INTERFACE_STRING_LENGTH 1025

#define ErrID_None 0 
#define ErrID_Info 1 
#define ErrID_Warn 2 
#define ErrID_Severe 3 
#define ErrID_Fatal 4 

static int AbortErrLev = ErrID_Fatal;      // abort error level; compare with NWTC Library

#define SensorType_None -1

// make sure these parameters match with FAST_Library.f90
#define MAXIMUM_BLADES 3
#define MAXIMUM_OUTPUTS 1000
#define CHANNEL_LENGTH 10  
#define MAXInitINPUTS 10

#define NumFixedInputs  2 + 2 + MAXIMUM_BLADES + 1
