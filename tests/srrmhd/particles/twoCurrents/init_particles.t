!=============================================================================
subroutine init_particle_integrator()

use mod_particles
use constants
include 'amrvacdef.f'
!-----------------------------------------------------------------------------
! set the number of steps:
itmax_particles = 10000000
tmax_particles  = tmax * UNIT_LENGTH/UNIT_VELOCITY !< same maximum time as MHD
ditsave_particles = 1
dtsave_ensemble   = dtsave(2) * UNIT_LENGTH/UNIT_VELOCITY !< same timestep as MHD output
dtheta            = 2.0d0 * dpi / 60.0d0 !< gyrations resolved with at least 60 timesteps

losses = .false.

end subroutine init_particle_integrator
!=============================================================================
subroutine init_particles()
! initialise the particles

use constants
use mod_particles
use mod_gridvars
use Knuth_random
include 'amrvacdef.f'

double precision, dimension(ndir)    :: x
integer                              :: igrid_particle, ipe_particle
integer, parameter                   :: Npart=1000
integer                              :: seed
double precision                     :: r^C(1:Npart), s^C(1:Npart), t^C(1:Npart), u^C(1:Npart)
double precision		     :: theta, prob, theta2, prob2
double precision                     :: vthermal, lfac, gamma
double precision                     :: B(1:ndir), absB, u(1:ndir), absS
integer                              :: ipart
logical, dimension(1:Npart)          :: follow=.false.
!-----------------------------------------------------------------------------

! initialise the random number generator
seed = 310952
call rnstrt(seed)
{^C&
call rand(r^C,Npart)
call rand(s^C,Npart)
call rand(t^C,Npart)
call rand(u^C,Npart)
\}


! flags to follow particles
follow(1)   = .true.
!follow(81)  = .true.
!follow(100) = .true.
!follow(20) = .true.
!follow(23) = .true.
!follow(5) = .true.
!follow(855) = .true.

do while (nparticles .lt. Npart)
! first find ipe and igrid responsible for particle

!> uniform spatial distribution
{^D&x(^D) = (xprobmin^D) + r^D(nparticles+1) * ((xprobmax^D) - (xprobmin^D))\}

   call find_particle_ipe(x,igrid_particle,ipe_particle)

   nparticles=nparticles+1
   particle(nparticles)%igrid  = igrid_particle
   particle(nparticles)%ipe    = ipe_particle

   if (ipe_particle == mype) then 

      call push_particle_into_particles_on_mype(nparticles)
      allocate(particle(nparticles)%self)
      particle(nparticles)%self%follow = follow(nparticles)
      particle(nparticles)%self%index  = nparticles
      particle(nparticles)%self%q      = - CONST_e
      particle(nparticles)%self%m      =   CONST_me

      particle(nparticles)%self%t      = 0.0d0
      particle(nparticles)%self%dt     = 1.0d0

      particle(nparticles)%self%x(:) = x

{#IFDEF PARTICLES_GCA

      lfac = one/sqrt(one-(UNIT_VELOCITY/CONST_c)**2)
      absS = sqrt(s1(nparticles)**2+s2(nparticles)**2+s3(nparticles)&
           &**2)
     
      !> maxwellian velocity distribution assigned here
      prob  = sqrt(-2.0d0*log(1.0-.999999*s1(nparticles)));

      !> random pitch angle given to each particle
      theta = 2.0d0*dpi*t1(nparticles)

      !> random maxwellian velocity. In this way v_perp = u(2)^2+u(3)^2, v// =
      !> sqrt(u(1)^2) and vthermal = sqrt(v_perp^2 + v//^2)
     
      u(1) = sqrt(2.0d0) * UNIT_VELOCITY *prob*dsin(theta)*sqrt(CONST_mp/CONST_me)
      u(2) =  UNIT_VELOCITY *prob*dcos(theta)*sqrt(CONST_mp/CONST_me)
      u(3) =  UNIT_VELOCITY *prob*dcos(theta)*sqrt(CONST_mp/CONST_me)


      lfac = one/sqrt(one-(u(1)**2+u(2)**2+u(3)**2)/CONST_c**2)
      !u(1) = s1(nparticles)/absS * UNIT_VELOCITY * lfac
      !u(2) = s2(nparticles)/absS * UNIT_VELOCITY * lfac
      !u(3) = s3(nparticles)/absS * UNIT_VELOCITY * lfac

      gamma = sqrt(1.0d0 + lfac**2*({^C& u(^C)**2 |+})/CONST_c**2 ) !< particles Lorentz factor

      call get_vec(igrid_particle,x,particle(nparticles)%self%t,B&
           &,bp1_,bp^NC_)
      absB = sqrt({^C& B(^C)**2 |+})

      particle(nparticles)%self%u(1) = lfac * u(1) !< parallel momentum component (gamma v||)

      particle(nparticles)%self%u(2) = (sqrt(u(2)**2+u(3)**2) *&
           & particle(nparticles)%self%m )**2 / (2.0d0 *&
           & particle(nparticles)%self%m * absB) !< Mr: the conserved magnetic moment

      particle(nparticles)%self%u(3) = lfac !< Lorentz factor

      !> initialise payloads for guiding centre module
      particle(nparticles)%self%payload(1:npayload) = 0.0d0

      !> gyroradius
      particle(nparticles)%self%payload(1) = sqrt(2.0d0*particle(nparticles)%self%m*particle(nparticles)%self%u(2)*absB)/abs(particle(nparticles)%self%q*absB)*CONST_c

      !> pitch angle
      particle(nparticles)%self%payload(2)=datan(sqrt((2.0d0*particle(nparticles)%self%u(2)*absB)/(particle(nparticles)%self%m*particle(nparticles)%self%u(3)**2))/(u(1)))

      !> perpendicular velocity
      particle(nparticles)%self%payload(3)=sqrt((2.0d0*particle(nparticles)%self%u(2)*absB)/(particle(nparticles)%self%m*particle(nparticles)%self%u(3)**2))

}


{#IFDEF PARTICLES_LORENTZ
{^C&
     !> mono-energetic velocity distribution
     ! particle(nparticles)%self%u(^C) = 0.5d0*(-1.5d0+s^C(nparticles)+t^C(nparticles)+u^C(nparticles)) * vthermal /CONST_c
     
     !> Maxwellian velocity distribution

        absS = sqrt(s1(nparticles)**2+s2(nparticles)**2+s3(nparticles)&
           &**2)

      !> maxwellian velocity distribution assigned here
      prob  = sqrt(-2.0d0*log(1.0-.999999*s1(nparticles)));
      prob2 = sqrt(-2.0d0*log(1.0-.999999*s2(nparticles)));

      !> random pitch angle given to each particle
      theta = 2.0d0*dpi*t1(nparticles)
      theta2 = 2.0d0*dpi*t2(nparticles)
      
      !> random maxwellian velocity
      u(1) =  UNIT_VELOCITY *prob*dcos(theta)/CONST_c*sqrt(CONST_mp/CONST_me)    !< momentum gamma*vx/c normalised by speed of light
      u(2) =  UNIT_VELOCITY *prob*dsin(theta)/CONST_c*sqrt(CONST_mp/CONST_me)    !< momentum gamma*vy/c normalised by speed of light
      u(3) =  UNIT_VELOCITY *prob2*dcos(theta2)/CONST_c*sqrt(CONST_mp/CONST_me)  !< momentum gamma*vz/c normalised by speed of light
      particle(nparticles)%self%u(^C) = u(^C)
      !> initialise payloads for Lorentz module
      particle(nparticles)%self%payload(1:npayload) = 0.0d0
\}
}


   end if

end do

end subroutine init_particles
!=============================================================================
logical function user_destroy(myparticle)

use mod_particles, only: particle_node

type(particle_node), intent(in)          :: myparticle
!-----------------------------------------------------------------------------
user_destroy = .false.

end function user_destroy
!=============================================================================
