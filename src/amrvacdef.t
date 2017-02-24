!=============================================================================
! include file amrvacdef.t

use mod_indices
use mod_physicaldata
use mod_connectivity

IMPLICIT NONE

! DEFINITIONS OF GLOBAL PARAMETERS AND VARIABLES
! Parameters:

! Indices for cylindrical coordinates FOR TESTS, negative value when not used:
INTEGER,PARAMETER:: r_=1, phi_=^PHI, z_=^Z

! Indices for cylindrical coordinates FOR INDEXING, always positive
INTEGER,PARAMETER:: pphi_=^PPHI, zz_=^ZZ

include 'amrvacpar.f'

INTEGER,PARAMETER:: ndim=^ND, ndir=^NC

include 'amrvacsettings.f'

INTEGER,PARAMETER:: filelog_=1,fileout_=2,fileslice_=3,filecollapse_=4,fileanalysis_=5,nfile=5 ! outputfiles
INTEGER,PARAMETER:: nslicemax=1000

INTEGER,PARAMETER:: unitstdin=5,unitterm=6,uniterr=6 ! Unit names.

! Units reserved for files:
INTEGER,PARAMETER:: unitpar=9
INTEGER,PARAMETER:: unitconvert=10
INTEGER,PARAMETER:: unitslice=11
INTEGER,PARAMETER:: unitsnapshot=12
INTEGER,PARAMETER:: unitcollapse=13
INTEGER,PARAMETER:: unitanalysis=14

INTEGER,PARAMETER:: biginteger=10000000

! Note: smalldouble must be above machine precision 
DOUBLE PRECISION,PARAMETER:: smalldouble=1.D-12, bigdouble=1.D+99
DOUBLE PRECISION,PARAMETER:: zero=0D0,one=1D0,two=2D0,half=0.5D0,quarter=0.25D0,third=0.33333333333333333333d0
DOUBLE PRECISION,PARAMETER:: dpi=3.141592653589793238462643383279502884197169399375105d0

! Physical scaling parameters:
DOUBLE PRECISION:: UNIT_LENGTH, UNIT_DENSITY, UNIT_VELOCITY

include 'amrvacusrpar.f'

! For transform variables and save selected data
INTEGER :: nwtf
INTEGER :: neqpartf

!Kronecker delta and Levi-Civita tensors
INTEGER:: kr(3,3),lvc(3,3,3)

!Equation and method parameters
DOUBLE PRECISION:: eqpar(neqpar+nspecialpar)

! Time step control parameters
DOUBLE PRECISION :: courantpar, dtpar, dtdiffpar, dtTCpar{#IFDEF MAGNETOFRICTION ,cmf_c,cmf_y,cmf_divb}
CHARACTER*131 :: typecourant,typeresid
LOGICAL :: time_accurate, addmpibarrier

!Time parameters
INTEGER,PARAMETER:: nsavehi=100       ! maximum No. saves into outputfiles
                                      ! defined by arrays of tsave or itsave
DOUBLE PRECISION:: t,tmax,dtmin,residmin,residmax,residual{#IFDEF MAGNETOFRICTION ,tmf}
DOUBLE PRECISION:: tfixgrid
DOUBLE PRECISION:: tsave(nsavehi,nfile),tsavelast(nfile),dtsave(nfile),slicecoord(nslicemax)
LOGICAL:: tmaxexact,treset,itreset,firstprocess,resetgrid,fixprocess,changeglobals,collapse(ndim)
INTEGER:: it,itmax,itmin,slowsteps{#IFDEF MAGNETOFRICTION , itmaxmf, ditsavemf}
INTEGER:: itsave(nsavehi,nfile),itsavelast(nfile),ditsave(nfile)
INTEGER:: isavet(nfile),isaveit(nfile), nslices, slicedir(nslicemax), collapseLevel
INTEGER:: n_saves(1:nfile)
INTEGER:: typeparIO
INTEGER:: itfixgrid,ditregrid
INTEGER:: nwauxio
INTEGER:: istep, nstep

!Method switches
CHARACTER*131 :: typeadvance
CHARACTER*131 :: typelow1(nlevelshi),typelimited,typesourcesplit
CHARACTER*131 :: typefull1(nlevelshi), typepred1(nlevelshi)
CHARACTER*131 :: typelimiter1(nlevelshi),typegradlimiter1(nlevelshi)
CHARACTER*131 :: typelimiter,typegradlimiter,typeprolonglimit
CHARACTER*131 :: typeentropy(nw),typetvd,typetvdlf,typeaverage
CHARACTER*131 :: typedimsplit,typeaxial,typecoord,typepoly
INTEGER:: errorestimate,nxdiffusehllc,typespherical,ncyclemax
DOUBLE PRECISION:: entropycoef(nw)
DOUBLE PRECISION:: tvdlfeps, mcbeta, parastsnu, TCphi
LOGICAL:: sourceparasts,sourceimpl,sourceimplcycle,conduction,TCsaturate,bcphys
LOGICAL:: loglimit(nw),logflag(nw),flathllc,flatcd,flatsh,flatppm
LOGICAL:: ssplitdust,ssplitdivb,ssplitresis,ssplituser,useprimitive,dimsplit
LOGICAL:: restrictprimitive,prolongprimitive, &
                  coarsenprimitive,useprimitiveRel, &
                  amrentropy

LOGICAL:: divbwave,compactres,BnormLF
DOUBLE PRECISION:: divbdiff,smallT,smallp,smallrho,amr_wavefilter(nlevelshi)
CHARACTER*131 :: typedivbdiff,typedivbfix,typediv,typegrad

LOGICAL:: fixsmall,strictnr,strictsmall,strictzero,strictgetaux
DOUBLE PRECISION::dmaxvel,tolernr,absaccnr,tlow
INTEGER:: maxitnr,nflatgetaux

LOGICAL:: nocartesian
LOGICAL:: writew(nw),writelevel(nlevelshi)
DOUBLE PRECISION:: writespshift(ndim,2)
INTEGER:: level_io, level_io_min, level_io_max

! cooling related parameters
INTEGER:: ncool, cmulti
CHARACTER*131 :: coolcurve,coolmethod
DOUBLE PRECISION :: cfrac
LOGICAL :: Tfix

! dust related paramters
LOGICAL  :: dustzero
DOUBLE PRECISION :: smallrhod
CHARACTER*131 :: dustmethod,dustspecies,dusttemp

! local and global fastest wave speed (computed in setdt):
DOUBLE PRECISION :: cmax_mype, cmax_global

!Gravity related parameters
DOUBLE PRECISION ::  x1ptms,x2ptms,x3ptms,ptmass

!Boundary region parameters
INTEGER,PARAMETER:: nhiB=2*ndim         ! maximum No. boundary sections
LOGICAL:: periodB(ndim), poleB(2,ndim), aperiodB(ndim)
CHARACTER*131 :: typeB(nw,nhiB)
CHARACTER*131 :: typeghostfill,typegridfill
DOUBLE PRECISION::ratebdflux
LOGICAL:: internalboundary

!File parameters
CHARACTER*131 :: inifile,filenameout,filenameini,filenamelog
CHARACTER*131 :: fileheadout
CHARACTER*1024 :: wnames,primnames,wnameslog
CHARACTER*131 :: typefilelog
INTEGER :: snapshotini
LOGICAL :: sliceascii

!Convert parameters
LOGICAL :: convert,autoconvert,saveprim,uselimiter,endian_swap
CHARACTER*131 :: convert_type, slice_type, dxfiletype, collapse_type
DOUBLE PRECISION :: normvar(0:nw),normt
! --------------------------------------------
!Test parameters
CHARACTER*131 :: teststr
INTEGER :: ixtest1,ixtest2,ixtest3,iwtest,idimtest
INTEGER:: saveigrid
! Stores the memory and load imbalance, to be used in printlog:
DOUBLE PRECISION :: Xload, Xmemory

LOGICAL:: oktest    !This is a local variable for all subroutines and functions

DOUBLE PRECISION:: time_bc
{#IFDEF STRETCHGRID
! stretching factor qst for log stretch grid
DOUBLE PRECISION:: logG, qst
DOUBLE PRECISION:: logGs(0:nlevelshi), qsts(0:nlevelshi)
}

integer,parameter:: nodehi=^ND+1
integer,parameter:: plevel_=1
integer,parameter:: pig^D_=plevel_+^D

integer,parameter:: rnodehi=3*^ND
integer,parameter:: rpxmin0_=0
integer,parameter:: rpxmin^D_=rpxmin0_+^D 
integer,parameter:: rpxmax0_=^ND
integer,parameter:: rpxmax^D_=rpxmax0_+^D 
integer,parameter:: rpdx^D_=2*^ND+^D

! parameters for bc_phys
integer,parameter:: ismin^D=-1+2*^D
integer,parameter:: ismax^D=2*^D

include 'mpif.h'

!-----------------------------------------------------------------------------
! common block variables
!-----------------------------------------------------------------------------

! nodal info per grid: 
! rnode:            corner coordinates,dx(idim)
! node:             dimensions and pointers 

! mxnest:           maximal number of levels

! tol:              error tolerance used for refinement decision
! nbufferx^D:       number of cells as buffer zone

! dixB:             number of ghost cells surrounding a grid for boundary cndt.

double precision :: tol, tolratio
double precision :: rnode, rnode_sub, dx, dt, dtimpl, dt_grid, dxlevel
integer          :: mxnest, dixB, nbufferx^D
integer          :: node, node_sub, levmin, levmax, levmax_sub
logical          :: skipfinestep, phyboundblock, time_advance{#IFDEF MAGNETOFRICTION , mf_advance}

common /nodalr/     rnode(rnodehi,ngridshi), rnode_sub(rnodehi,ngridshi), tol(nlevelshi), tolratio(nlevelshi), &
                    dx(ndim,nlevelshi), dt, dtimpl, dt_grid(ngridshi)
common /nodali/     node(nodehi,ngridshi), node_sub(nodehi,ngridshi), &
                    nbufferx^D, mxnest, dixB, levmin, levmax, levmax_sub
common /nodall/     skipfinestep, phyboundblock(ngridshi), time_advance{#IFDEF MAGNETOFRICTION , mf_advance}

common /INTE/ nwtf,neqpartf,kr,lvc,it,itmax,itmin,slowsteps,itsave,itsavelast,&
   ditsave,isavet,isaveit, nslices, slicedir, collapseLevel,n_saves,typeparIO,&
   itfixgrid,ditregrid,nwauxio,istep, nstep,errorestimate,nxdiffusehllc,&
   typespherical,ncyclemax,maxitnr,nflatgetaux,level_io, level_io_min,&
    level_io_max,ncool, cmulti,snapshotini,ixtest1,ixtest2,ixtest3,iwtest,&
   idimtest{#IFDEF MAGNETOFRICTION , itmaxmf, ditsavemf}
common /DOUB/ UNIT_LENGTH, UNIT_DENSITY, UNIT_VELOCITY,eqpar,courantpar,&
    dtpar, dtdiffpar, dtTCpar,t,tmax,dtmin,residmin,residmax,residual,&
   tfixgrid,tsave,tsavelast,dtsave,slicecoord,entropycoef,tvdlfeps, mcbeta,&
    parastsnu, TCphi,divbdiff,smallT,smallp,smallrho,amr_wavefilter,dmaxvel,&
   tolernr,absaccnr,tlow,writespshift,cfrac,smallrhod,cmax_mype, cmax_global,&
   x1ptms,x2ptms,x3ptms,ptmass,ratebdflux,normvar,normt,Xload,Xmemory,time_bc{#IFDEF STRETCHGRID ,logGs,qsts}{#IFDEF MAGNETOFRICTION ,cmf_c,cmf_y,cmf_divb,tmf}
common /CHAR/ typecourant,typeresid,typeadvance,typelow1,typelimited,&
   typesourcesplit,typefull1, typepred1,typelimiter1,typegradlimiter1,&
   typeprolonglimit,typeentropy,typetvd,typetvdlf,&
   typeaverage,typedimsplit,typeaxial,typecoord,typepoly,typedivbdiff,&
   typedivbfix,typediv,typegrad,coolcurve,coolmethod,dustmethod,dustspecies,&
   dusttemp,typeB,typeghostfill,typegridfill,inifile,filenameout,filenameini,&
   filenamelog,fileheadout,wnames,primnames,wnameslog,typefilelog,&
   convert_type, slice_type, dxfiletype, collapse_type,teststr
common /LOGI/ time_accurate, addmpibarrier,tmaxexact,treset,itreset,&
   firstprocess,resetgrid,fixprocess,changeglobals,collapse,sourceparasts,&
   sourceimpl,sourceimplcycle,conduction,TCsaturate,bcphys,loglimit,logflag,&
   flathllc,flatcd,flatsh,flatppm,ssplitdust,ssplitdivb,ssplitresis,&
   ssplituser,useprimitive,dimsplit,restrictprimitive,prolongprimitive,&
    coarsenprimitive,useprimitiveRel, amrentropy,divbwave,compactres,BnormLF,&
   fixsmall,strictnr,strictsmall,strictzero,strictgetaux,nocartesian,writew,&
   writelevel,Tfix,dustzero,periodB, poleB, aperiodB,internalboundary,&
   convert,autoconvert,saveprim,uselimiter,endian_swap,sliceascii
common /ompdoub/ dxlevel(ndim){#IFDEF STRETCHGRID ,logG,qst} 
common /ompinte/ saveigrid
common /ompchar/ typelimiter,typegradlimiter

!$OMP THREADPRIVATE(/ompdoub/,/ompinte/,/ompchar/)
! end include file amrvacdef.t
!============================================================================
