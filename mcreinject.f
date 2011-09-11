c********************************************************************
c Reinject particle i using the MC pre-calculated distribution
      subroutine mcreinject(ipart)
      implicit none
c Input variables
c     Particle index
      integer ipart
c Common data
      include 'piccom.f'
      include 'errcom.f'
c Functions used
      real ran0
c Local variables
c     Injection radius; theta, psi, and their sin and cos
      real rs,theta,psi,st,ct,sp,cp
c     Theta and psi indices of face, and the face particle index
      integer ith, ips, ifacepart
c     Working variables
      real rnd
      integer idum, n

c Select face based on cumulative flux distribution
c     Argument of ran0 doesn't do anything, so just set to 1
      idum = 1
      rnd = ran0(idum)
      call invtarray(mcrcumfacewght,1,mcrntheta*mcrnpsi,rnd,n)
c     Convert n to theta and psi indices
      ith = 1 + mod(n-1,mcrntheta)
      ips = 1 + (n-ith)/mcrntheta

c Choose random particle (by flux) from those injectable by face
      rnd = ran0(idum)
      call invtarray(mcrfacecumnormv(1,ith,ips),
     $  1,mcrfacenpart(ith,ips),rnd,n)
      ifacepart = mcrfacepart(n,ith,ips)

c Choose random position on face (assuming equal spacing in psi)
      rnd = ran0(idum)
      ct = mcrcostheta(ith-1)*(1-rnd) + mcrcostheta(ith)*rnd
      st = sqrt(1-ct**2)

      rnd = ran0(idum)
      cp = cos( mcrpsi(ips-1)*(1-rnd) + mcrpsi(ips)*rnd )
      sp = sin( mcrpsi(ips-1)*(1-rnd) + mcrpsi(ips)*rnd )

c It is possible at this point that the velocity is actually slightly
c   outwards at the new position, since the normal is slightly different
c   than that at the face center. However, since particles are injected
c   within the outer radius these particles will just leave in the next
c   time step and thus be reinjected again. This shouldn't be a problem,
c   though an alternate approach would be to keep choosing positions
c   on the face until an inwards velocity is found.

c Set velocity and position of injected particle
      xp(6,ipart)=mcrpart(3,ifacepart)
      xp(5,ipart)=mcrpart(2,ifacepart)
      xp(4,ipart)=mcrpart(1,ifacepart)

      rs=r(nr)*0.99999
      xp(3,ipart)=rs*ct
      xp(2,ipart)=(rs*st)*sp
      xp(1,ipart)=(rs*st)*cp

c Do the outer flux accumulation
c     Assuming potential is zero at boundary, so no change to sum
      spotrein = spotrein + 0.
c     Have injected another particle, so increment nrein
      nrein = nrein + 1

      end


c********************************************************************
c Generate particles to be injected and calculate cumulative prob.s
      subroutine mcrinjinit(icolntype, colnwt)
      implicit none
c Input variables
      integer icolntype
      real colnwt
c Common data
      include 'piccom.f'
      include 'errcom.f'
      include 'colncom.f'
c Functions used
      real dot
c Local variables
c     Step sizes in psi and cos theta
      real psistep, costhstep
c     Angles of face center and solid angle of face
      real theta, psi, solidangle
c     Normal to face
      real normal(mcrndim)
c     Magnitude of velocity normal to face and cumulative normalv
      real normalv, cumnormv
c     Cumulative weight for faces
      real cumweight
c     Working variables
      integer i, j, k

c Set theta and psi grid (i.e. define injection faces)
      costhstep = 2./mcrntheta
      do i=0,mcrntheta
         mcrcostheta(i) = -1. + i*costhstep
      enddo

      psistep = 2.*pi/mcrnpsi
      do i=0,mcrnpsi
         mcrpsi(i) = i*psistep
      enddo

c Generate particles to be injected
      call mcgenpart(mcrpart,mcrndim,mcrnpart,1,colnwt)

c Determine which particles are injectable by, and the flux through, each face
c This may take a significant amount of computational time, but is only done once
      cumweight = 0.
      mcrtotflux = 0.
      do i=1,mcrnpsi
         do j=1,mcrntheta
            theta = acos((mcrcostheta(j)+mcrcostheta(j-1))/2.)
            psi = (mcrpsi(i)+mcrpsi(i-1))/2.
c           Normal is just inward radial vector (- r hat)
            normal(1) = -cos(psi)*sin(theta);
            normal(2) = -sin(psi)*sin(theta);
            normal(3) = -cos(theta);
            mcrfacenpart(j,i) = 0
            cumnormv = 0.
            do k=1,mcrnpart
               normalv = dot(mcrpart(1,k),normal(1),mcrndim)
               if (normalv.gt.0.) then
                  mcrfacenpart(j,i) = mcrfacenpart(j,i) + 1
                  mcrfacepart(mcrfacenpart(j,i),j,i) = k
                  cumnormv = cumnormv + normalv
c                 Store cumulative distribution and normalize later
                  mcrfacecumnormv(mcrfacenpart(j,i),j,i) = cumnormv
               endif
            enddo
c           Normalize cumulative distribution
            do k=1,mcrfacenpart(j,i)
               mcrfacecumnormv(k,j,i) = mcrfacecumnormv(k,j,i)/
     $           cumnormv
            enddo
c           Store cumulative distribution and normalize later
            solidangle = (mcrpsi(i)-mcrpsi(i-1))*
     $        (mcrcostheta(j)-mcrcostheta(j-1))
            cumweight = cumweight + cumnormv*solidangle
            mcrcumfacewght(j+(i-1)*mcrntheta) = cumweight
c           Update total flux; normalize later
            mcrtotflux = mcrtotflux + cumnormv*solidangle
         enddo
      enddo

c     Normalize cumulative distribution
      do i=1,mcrnpsi
         do j=1,mcrntheta
            mcrcumfacewght(j+(i-1)*mcrntheta) =
     $        mcrcumfacewght(j+(i-1)*mcrntheta) / cumweight
         enddo
      enddo

c     Normalize total flux
c       Note that the flux is now calculated at each node,
c       but rhoinf is calculated by node 0 and then broadcast.
c       Could average flux from each node before calculating rhoinf.
c     This is not really per unit area, so flux may not be the best name for this
      mcrtotflux = mcrtotflux/mcrnpart
      mcrtotflux = mcrtotflux*r(nrused)**2


      end

c********************************************************************
c Generate particle velocities from neutral distribution and evolve for
c   a collisional time
      subroutine mcgenpart(velocities,ndims,n,dimmin,colnwt)
      implicit none
c Input variables
c     Number of dimensions of particle info (generally 3 or 6, depending
c       on whether or not positional info is included)
      integer ndims
c     Number of particles
      integer n
c     Index of first dimension to put velocity info in (1 or 4, depending
c       on whether or not positional info is included)
      integer dimmin
c     Particle velocities to be output
      real velocities(ndims,n)
c     Collision frequency
      real colnwt
c Common data
      include 'piccom.f'
      include 'errcom.f'
      include 'colncom.f'
c Functions used
      real ran0, gasdev, dot
c Local variables
c     Velocity scale
      real vscale
c     Time since last collision
      real colldt
c     Initial parallel (to B) velocity and evolved perpendicular vel.
      real vpar(mcrndim), vperp(mcrndim), vperpmag
c     Orthonormal base vectors spanning vperp plane (forming R.H. x-y-b)
      real vperpx(mcrndim), vperpy(mcrndim)
c     Change in parallel velocity due to electric field,
c       and E cross B drift velocity
      real epardv(mcrndim), ecbdr(mcrndim)
c     Angle of rotation due to cyclotron motion
      real rot
c     Working variables
      integer i,j,idum

c Generate particles from a drifting Maxwellian of neutrals
c     Argument of ran0 doesn't do anything, so just set to 1
      idum = 1
      if (Tneutral.gt.0.) then
         vscale=sqrt(Tneutral)
      else
         write (*,*) 'Error in mcgenpart: Tneutral=0'
      endif
      do i=1,n
         do j=1,mcrndim
            velocities(dimmin-1+j,i) = vscale*gasdev(idum) + vneut(j)
         enddo
      enddo

c Evolve each velocity over time since last collision
      do i=1,n
         if (colnwt.gt.0.) then
            colldt = -alog(ran0(idum))/colnwt
         else
            colldt = 0.
         endif
         if (Bz.ne.0.) then
c           Non-zero magnetic field, so evolve velocity accordingly
c           Initial perpendicular velocity
            call cross(velocities(dimmin,i),magdir(1),vperp(1))
            call cross(magdir(1),vperp(1),vperp(1))
            vperpmag = sqrt(dot(vperp(1),vperp(1),mcrndim))
            do j=1,mcrndim
               vpar(j) = magdir(j)*dot(velocities(dimmin,i),
     $           magdir(1),mcrndim)
               if (colldt.gt.0.) then
                  epardv(j)=magdir(j)*dot(Eneut(1),magdir(1),mcrndim)*
     $              colldt
               else
c                 If no collisions, the drift is specified
                  epardv(j)=magdir(j)*dot(drvect(1),magdir(1),mcrndim)
               endif
               if (vperpmag .gt. 0.) then
                  vperpx(j) = vperp(j)/vperpmag
               else
                  vperpx(j) = 0.
               endif
            enddo
            call cross(magdir(1),vperpx(1),vperpy(1))
            rot = Bz*colldt
            do j=1,mcrndim
c              Evolved perpendicular velocity
               vperp(j) = vperpmag *
     $           ( vperpx(j)*cos(rot) - vperpy(j)*sin(rot) )
            enddo
         else
c           No magnetic field, so no E cross B and no perp dir.
            do j=1,mcrndim
               vperp(j) = 0.
               vpar(j) = velocities(dimmin-1+j,i)
               if (colldt.gt.0.) then
                  epardv(j) = Eneut(j)*colldt
               else
c                 No collisions, so just add specified drift
                  epardv(j) = drvect(j)
               endif
            enddo
         endif
c        Set final velocity
         do j=1,mcrndim
            velocities(dimmin-1+j,i) = vpar(j) + vperp(j) + epardv(j) +
     $        ecbdrift(j)
         enddo
      enddo

      end