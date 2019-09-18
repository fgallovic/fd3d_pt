!-------------------------------------------------------
! Main routine for the FD dynamic simulation and enforcement of
! the fault boundary condition.
!-------------------------------------------------------
! Authors: Jan Premus and Frantisek Gallovic (8/2019)
! Charles University in Prague, Faculty of Mathematics and Physics

! This code is published under the GNU General Public License. To any
! licensee is given permission to modify the work, as well as to copy
! and redistribute the work or any derivative version. Still we would
! like to kindly ask you to acknowledge the authors and don't remove
! their names from the code. This code is distributed in the hope
! that it will be useful, but WITHOUT ANY WARRANTY.
! ------------------------------------------------------

	
      subroutine fd3d()
      USE medium_com
      USE displt_com
      USE strfld_com
      USE fd3dparam_com
      USE friction_com
      USE source_com
      USE traction_com
      USE pml_com
      USE SlipRates_com
      IMPLICIT NONE

      real    :: time,friction,tmax,xmax,ymax,numer,denom,veltest,dd
      integer :: incrack(nxt,nzt),broken(nxt,nzt),nsurf, brokenX(nxt,nzt),brokenZ(nxt,nzt)
      real    :: pdx, pdz,tabs
      real    :: u1out,sliprateoutX(nxt,nzt),sliprateoutZ(nxt,nzt),slipX(nxt,nzt)
      real    :: CPUT1,CPUT2
	  REAL 	  :: maxvelX,maxvelZ,maxvelsave,tint, tint2
      real    :: dht, ek, es, ef, c1, c2
      integer :: i,j,it,k, nxe, nxb, nyb, nye, nzb, nze
      integer :: ifrom,ito,jfrom,jto,kk
	  real 	  :: rup_tresh, rv, cz
#if defined FVW
	  real 	  :: fss, flv, psiss, dpsi,  sr
	  real 	  :: FXZ, GT, hx, hz, rr,AA,BB
	  real	  :: pert(nxt,nzt), psiout(nxt,nzt)
#endif
!---------------------------
! Write down the input
!---------------------------
       if (ioutput.eq.1) then
#if defined FVW
#else
         open(95,file='result/vmodel.inp')
         open(96,file='result/friction.inp')
         do k = nabc+1,nzt-nfs
           do i = nabc+1,nxt-nabc
             write(95,*) mu1(i,nysc,k)
             write(96,'(5E13.5)') striniX(i,k),striniZ(i,k),peak_xz(i,k),Dc(i,k),peak_xz(i,k)/normstress(k)
            enddo
         enddo
         close(95)
         close(96)
#endif
		 open(31,file='result/stan0.txt')		 
		 open(32,file='result/stan1.txt')	 
		 open(33,file='result/stan2.txt')	 
		 open(34,file='result/stan3.txt')
		 open(35,file='result/stan4.txt')	 
		 open(36,file='result/stan5.txt')	 
		 open(37,file='result/stan6.txt')	 
		 open(38,file='result/stan7.txt')	 
		 open(39,file='result/stan8.txt')
		 open(40,file='result/stan9.txt')
		 
       endif
!-------------------------------------------------------
!   initialize arrays
!-------------------------------------------------------
      allocate(u1(nxt,nyt,nzt),v1(nxt,nyt,nzt),w1(nxt,nyt,nzt))
      allocate(xx(nxt,nyt,nzt),yy(nxt,nyt,nzt),zz(nxt,nyt,nzt),xy(nxt,nyt,nzt),yz(nxt,nyt,nzt),xz(nxt,nyt,nzt))
	  allocate(tx(nxt,nzt),tz(nxt,nzt),v1t(nxt,nzt),avdx(nxt,nzt),avdz(nxt,nzt), RFx(nxt,nzt),RFz(nxt,nzt))
      allocate(omega_pml(nabc-1), omegaR_pml(nabc-1),omega_pmlM(nabc-1), omegaR_pmlM(nabc-1))
	  allocate(au1(nxt,nzt),av1(nxt,nzt),aw1(nxt,nzt))
	  
      u1=0.;v1=0.;w1=0.
      xx=0.;yy=0.;zz=0.;xy=0.;yz=0.;xz=0.
      ruptime=1.e4;rise=0.;sliptime=1.e4
      broken=0;incrack=0
      tx=0.;tz=0.;v1t=0.
	  uZ=0.;wX=0.
      avdx = 0.; avdz = 0.
	  RFx = 0.; RFz = 0.
      au1=0.; av1=0.;aw1=0 
      MSRX=0.;MSRZ=0.;MomentRate=0.
	  slipX=0.;slipZ=0.
      rup_tresh=1.e-3 !	Rate treshold for rupture time calculation
	  brokenX=0.;brokenZ=0.
      c1  = 9./8. !	4th order central FD formula parameters	
      c2  = -1./24.
#if defined FVW
	  tabsX=striniX
	  tabsZ=striniX
#endif
	  dht = dh/dt
	  seisU=0;seisV=0;seisW=0;
	  call init_pml()
	  call interp_fric()

!-------------------------------------------------------
!     Loop over time
!-------------------------------------------------------
      if(ioutput.eq.1) then
#if defined FVW
		OPEN(24, file='result/psi.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
#endif
		OPEN(25, file='result/sliprateZ.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
		OPEN(27, file='result/sliprateX.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
        OPEN(26, file='result/shearstressZ.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
        OPEN(28, file='result/shearstressX.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
		OPEN(29, file='result/sliprateY.res',FORM='UNFORMATTED',ACCESS='STREAM',STATUS='REPLACE')
      endif
	  
      CALL CPU_TIME(CPUT1)
      maxvelsave=0.

      !$ACC DATA COPYIN (LAM1,MU1,D1) &
      !$ACC      COPYIN (U1,V1,W1) COPYIN (XX,YY,ZZ,XY,YZ,XZ) &
      !$ACC      COPYIN (tx,tz,v1t,avdx,avdz,RFx,RFz,uZ,wX) &
      !$ACC      COPYIN (au1,av1,aw1) &
      !$ACC      COPYIN (omega_pml,omegaR_pml,omega_pmlM,omegaR_pmlM) &
      !$ACC      COPYIN (u11,u12,u13,u21,u22,u23,u31,u32,u33,u41,u42,u43) &
      !$ACC      COPYIN (v11,v12,v13,v21,v22,v23,v31,v32,v33,v41,v42,v43) &
      !$ACC      COPYIN (w11,w12,w13,w21,w22,w23,w31,w32,w33,w41,w42,w43) &
      !$ACC      COPYIN (xx11,xx12,xx13,xx21,xx22,xx23,xx31,xx32,xx33,xx41,xx42,xx43) &
      !$ACC      COPYIN (yy11,yy12,yy13,yy21,yy22,yy23,yy31,yy32,yy33,yy41,yy42,yy43) &
      !$ACC      COPYIN (zz11,zz12,zz13,zz21,zz22,zz23,zz31,zz32,zz33,zz41,zz42,zz43) &
      !$ACC      COPYIN (xy11,xy12,xy21,xy22,xy31,xy32,xy41,xy42) &
      !$ACC      COPYIN (xz11,xz12,xz21,xz22,xz31,xz32,xz41,xz42) &
      !$ACC      COPYIN (yz11,yz12,yz21,yz22,yz31,yz32,yz41,yz42) &
      !$ACC      COPYIN (omegax1,omegax2,omegax3,omegax4) &
      !$ACC      COPYIN (omegay1,omegay2,omegay3,omegay4) &
      !$ACC      COPYIN (omegaz1,omegaz2,omegaz3,omegaz4) &
      !$ACC      COPYIN (omegaxS1,omegaxS2,omegaxS3,omegaxS4) &
      !$ACC      COPYIN (omegayS3,omegayS4,omegazS4) &
      !$ACC      COPYIN (broken,dyn_xz,striniZ,striniX,peak_xz,Dc,coh,tabsX,tabsZ) &
	  !$ACC      COPYIN (peakX, dynX, DcX, peakZ, dynZ, DcZ,staX,staY,staZ) &
#if defined FVW
	  !$ACC      COPYIN (aX,bX,psiX,vwX,aZ,bZ,psiZ,vwZ,pert)&
#endif
      !$ACC      COPY (incrack,ruptime,sliptime,slipz,rise,slipx)  

	  
	  !seisU,seisV,seisW  
	  
      do it = 1,ntfd
         time = it*dt
         sliprateoutX(:,:)=0.
		 sliprateoutZ(:,:)=0.
         schangeZ(:,:)=0.
		 schangeX(:,:)=0.
		 seisU = 0.
		 seisV = 0.
		 seisW = 0.
#if defined FVW
		 psiout = 0.
	    !$ACC DATA COPY (sliprateoutX,sliprateoutZ,schangeZ,schangeX,seisU,seisV,seisW,psiout)
#else
		!$ACC DATA COPY (sliprateoutX,sliprateoutZ,schangeZ,schangeX,seisU,seisV,seisW)
#endif
!-------------------------------------------------------------
!	Velocity tick
!-------------------------------------------------------------
         call dvel(nxt,nyt-2,nzt,dt,dh)   !Apply 4th-order differencing to interior particle velocities
		 call bnd2d(nxt,nyt,nzt,dt,dh)    !Compute velocities of 2nd order accuracy near fault and apply symmetry in normal component
         call tasu1(nxt,nysc,nzt,dt,dh)   !Compute velocities at fault boundary
         call tasw1(nxt,nysc,nzt,dt,dh)
         call pml_uvw (nxt,nyt,nzt,dt,dh) !Stress free condition
		 call fuvw(nxt,nyt,nzt-nfs)		  !Absorbing condition
		 
!-------------------------------------------------------------
!   Stress tick
!-------------------------------------------------------------
         call dstres(nxt,nyt-2,nzt,dh,dt) !4th-order differencing of stress
         call strbnd(nxt,nyt,nzt,dh,dt)   !Compute stress tensor of 2nd order accuracy near fault and apply symmetry in normal components
         call tasxz(nxt,nysc,nzt,dt,dh)   !Compute stress components at fault boundary
         call tasii(nxt,nysc,nzt,dt,dh)
         call pml_xyz (nxt,nyt,nzt,dt,dh) !Absorbing condition 
		 call fres(nxt,nyt,nzt-nfs)       !Stress free condition

!----------------------------------------------------------------
! Fault BOUNDARY CONDITION applied in ABSOLUTE STRESS,
! not in relative stress, otherwise we get all sort of problems
!----------------------------------------------------------------
		!traction calculation
        !$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP GANG
        do k = nabc+1,nzt-nfs-1
          !$ACC LOOP VECTOR
          do i = nabc+1,nxt-nabc

			!pdz = ((xz(i+1,nysc,k) - xz(i,nysc,k))/(2.*2.) + (zz(i,nysc,k+1) - zz(i,nysc,k))/(2.*2.) - yz(i,nysc-1,k))
			pdz = (c1*(xz(i+1,nysc,k) - xz(i,nysc,k))   +  c2*(xz(i+2,nysc,k) - xz(i-1,nysc,k)))/(2.) + &
			(c1*(zz(i,nysc,k+1) - zz(i,nysc,k))   +  c2*(zz(i,nysc,k+2) - zz(i,nysc,k-1)))/(2.) - &
			yz(i,nysc-1,k)
			avdz(i,k)= damp_s*(pdz - avdz(i,k))
			RFz(i,k) = pdz + avdz(i,k)
			tz(i,k) = -RFz(i,k) - 0.5*d1(i,nysc,k)*dht*w1(i,nysc,k)
			avdz(i,k) = pdz

			!pdx = ((xx(i,nysc,k) - xx(i-1,nysc,k))/(2.*2.) + (xz(i,nysc,k) - xz(i,nysc,k-1))/(2.*2.) - xy(i,nysc-1,k))
			pdx = (c1*(xx(i,nysc,k)   - xx(i-1,nysc,k)) +  c2*(xx(i+1,nysc,k) - xx(i-2,nysc,k)))/(2.) + &
			(c1*(xz(i,nysc,k)   - xz(i,nysc,k-1)) +  c2*(xz(i,nysc,k+1) - xz(i,nysc,k-2)))/(2.) - &
			xy(i,nysc-1,k)
			avdx(i,k)= damp_s*(pdx - avdx(i,k))
			RFx(i,k) = pdx + avdx(i,k)
			tx(i,k) = -RFx(i,k) - 0.5*d1(i,nysc,k)*dht*u1(i,nysc,k)
			avdx(i,k) = pdx
					
          enddo
        enddo
        !$ACC END PARALLEL
		
		!Traction calculation near free surface
		k=nzt-nfs
		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP VECTOR
        do i = nabc+1,nxt-nabc
			pdz = ((xz(i+1,nysc,k-1) - xz(i,nysc,k-1))/(2.*4.) + (zz(i,nysc,k+1) - zz(i,nysc,k))/(2.*2.) - yz(i,nysc-1,k-1)/4.)			
			avdz(i,k)= damp_s*(pdz - avdz(i,k))
			RFz(i,k) = pdz + avdz(i,k)
			tz(i,k) = -RFz(i,k) - 0.5*d1(i,nysc,k)*dht*w1(i,nysc,k)/2.
			avdz(i,k) = pdz	
		    
			!pdx = ((xx(i,nysc,k) - xx(i-1,nysc,k))/(2.*2.) + (xz(i,nysc,k) - xz(i,nysc,k-1))/(2.*2.) - xy(i,nysc-1,k))			
			pdx = (c1*(xx(i,nysc,k)   - xx(i-1,nysc,k)) +  c2*(xx(i+1,nysc,k) - xx(i-2,nysc,k)))/(2.) + &
			(c1*(xz(i,nysc,k)   - xz(i,nysc,k-1)) +  c2*(xz(i,nysc,k+1) - xz(i,nysc,k-2)))/(2.) - &
			xy(i,nysc-1,k)
			avdx(i,k)= damp_s*(pdx - avdx(i,k))
			RFx(i,k) = pdx + avdx(i,k)
			tx(i,k) = -RFx(i,k) - 0.5*d1(i,nysc,k)*dht*u1(i,nysc,k)
			avdx(i,k) = pdx	
	
		enddo 
        !$ACC END PARALLEL
		
		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP VECTOR
        do i = nabc+1,nxt-nabc
			tx(i,nzt-1)=+tx(i,nzt-2)
			tz(i,nzt-1)=-tz(i,nzt-3)
		enddo
        !$ACC END PARALLEL
!-------------------------------------------------------------
!  Apply Boundary Conditions
!-------------------------------------------------------------
		!Traction interpolation in staggered positions
        !$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP GANG
        do k = nabc+1,nzt-nfs
          !$ACC LOOP VECTOR
          do i = nabc+1,nxt-nabc
			tint=(tx(i,k)+striniX(i,k)+tx(i+1,k)+striniX(i+1,k)+tx(i,k+1)+striniX(i,k+1)+tx(i+1,k+1)+striniX(i+1,k+1))/4.
            tabsZ(i,k) = sqrt(tint**2 + (tz(i,k)+striniZ(i,k))**2)	
            tint=(tz(i,k)+striniZ(i,k)+tz(i-1,k)+striniZ(i-1,k)+tz(i,k-1)+striniZ(i,k-1)+tz(i-1,k-1)+striniZ(i-1,k-1))/4.
			tabsX(i,k) = sqrt((tx(i,k)+striniX(i,k))**2 + (tint)**2)	
          enddo
        enddo
        !$ACC END PARALLEL

		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP GANG
        do k = nabc+1,nzt-nfs
          !$ACC LOOP VECTOR
          do i = nabc+1,nxt-nabc
			tabs=tabsZ(i,k)
			uZ(i,k)=(U1(I,NYSC,K)+U1(I+1,NYSC,K)+U1(I,NYSC,K+1)+U1(I+1,NYSC,K+1))/4.
            u1out=-sqrt(W1(I,NYSC,K)**2+uZ(i,k)**2)			 


#if defined FVW
			sr=sqrt((2.*(w1(i,nysc,k)-wini))**2+(2.*(uZ(i,k)-uini))**2)
            flv = f0 - (bZ(i,k) - aZ(i,k))*log(sr/v0)
			fss = fw + (flv - fw)/((1. + (sr/vwZ(i,k))**8)**(1./8.))
			psiss = aZ(i,k)*(log(sinh(fss/aZ(i,k))) + log(2*v0/(sr))) 
			psiZ(i,k)=(psiZ(i,k)-psiss)*exp(-sr*dt/Dc(i,k)) + psiss
			friction  = Sn * aZ(i,k)*asinh(sr*exp(psiZ(i,k)/aZ(i,k))/(2*v0)) 
			
			slipZ(i,k) = slipZ(i,k)  - 2*u1out*dt
			brokenZ(i,k)=1
			SCHANGEZ(I,K) = friction
			sliprateoutZ(i,k) = - 2.*W1(I,NYSC,K)
			psiout(i,k)=psiZ(i,k)
#else
            if (slipZ(i,k).le.DcZ(i,k)) then
                friction = peakZ(i,k) * (1.0 - slipZ(i,k)/DcZ(i,k)) + dynZ(i,k)*slipZ(i,k)/DcZ(i,k) + coh(i,k)
            else
				friction = dynZ(i,k) + coh(i,k)
			endif
			
			if (tabs .ge. friction) then
                slipZ(i,k) = slipZ(i,k)  - 2*u1out*dt
                tz(i,k) =  (tz(i,k) + striniZ(i,k))*friction/tabs - striniZ(i,k)
				brokenZ(i,k)=1
				
				if (-2*u1out>rup_tresh) then
					if (ruptime(i,k).ne.1.e4) rise(i,k)=time
					if (ruptime(i,k).eq.1.e4) ruptime(i,k) = time
					broken(i,k)=1
				endif
            endif
			SCHANGEZ(I,K) = tz(i,k) + striniZ(i,k)
			sliprateoutZ(i,k) = - 2.*W1(I,NYSC,K)
#endif
			if ((sliptime(i,k)==1.e4).AND.(slipZ(i,k)>Dc(i,k))) sliptime(i,k)=time

          enddo
        enddo
        !$ACC END PARALLEL
		
		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP GANG
        do k = nabc+1,nzt-nfs
          !$ACC LOOP VECTOR
          do i = nabc+1,nxt-nabc
			tabs=tabsX(i,k)
			wX(i,k)=(W1(I,NYSC,K)+W1(I-1,NYSC,K)+W1(I,NYSC,K-1)+W1(I-1,NYSC,K-1))/4.
            u1out=-sqrt(wX(i,k)**2+U1(I,NYSC,K)**2)
			
#if defined FVW
			sr=sqrt((2.*(wX(i,k)-wini))**2+(2.*(u1(i,nyt,k)-uini))**2)
            flv = f0 - (bX(i,k) - aX(i,k))*log(sr/v0)
			fss = fw + (flv - fw)/((1. + (sr/vwX(i,k))**8)**(1./8.))
			psiss = aX(i,k)*(log(sinh(fss/aX(i,k))) + log(2*v0/(sr))) 
			psiX(i,k)=(psiX(i,k)-psiss)*exp(-sr*dt/Dc(i,k)) + psiss
			friction  = Sn * aX(i,k)*asinh(sr*exp(psiX(i,k)/aX(i,k))/(2*v0)) 

            slipX(i,k) = slipX(i,k)  - 2*u1out*dt
			brokenX(i,k)=1	
			SCHANGEX(I,K) = friction
			sliprateoutX(i,k) = - 2.*U1(I,NYSC,K)			
			
#else
            if (slipX(i,k).le.Dc(i,k)) then
				friction = peakX(i,k) * (1.0 - slipX(i,k)/DcX(i,k)) + dynX(i,k)*slipX(i,k)/DcX(i,k) + coh(i,k)
            else
                friction = dynX(i,k) + coh(i,k)
            endif
			
            if (tabs .ge. friction) then
                slipX(i,k) = slipX(i,k)  - 2*u1out*dt
			  	tx(i,k) = (tx(i,k) + striniX(i,k))*friction/tabs - striniX(i,k)
				brokenX(i,k)=1
            endif
			SCHANGEX(I,K) = tx(i,k)+striniX(i,k)
			sliprateoutX(i,k) = - 2.*U1(I,NYSC,K)
#endif			 
          enddo
        enddo

        !$ACC END PARALLEL


		if(ioutput.eq.1) then	
		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP VECTOR			
          do i=1,Nstations
            seisU(i)=u1(staX(i),staY(i),staZ(i))
		    seisV(i)=v1(staX(i),staY(i),staZ(i))
		    seisW(i)=w1(staX(i),staY(i),staZ(i))
          enddo
		!$ACC END PARALLEL
		endif
	
#if defined TPV104
!	Smooth nucleation for the tpv104 benchmark
	  	if (time <= TT2) then
		 
		if (time < TT2) then
		   GT=exp((time-TT2)**2/(time*(time-2*TT2)))
		else
		   GT=1.
		endif
		!$ACC PARALLEL DEFAULT (PRESENT)
        !$ACC LOOP GANG		 
		do k = 1,nzt
		!$ACC LOOP VECTOR
			do i = 1,nxt
				hx = real(i)*dh
				hz = real(k)*dh
				rr = (hx-hx0)**2 + (hz-hz0)**2
				if (rr<RR2) then
					FXZ=exp(rr/(rr-RR2))
				else
					FXZ = 0.
				endif
				pert(i,k) = perturb*FXZ*GT
				strinix(i,k) = strinixI + pert(i,k)
			enddo
		enddo
        !$ACC END PARALLEL			
		endif
#endif	 

      !$ACC END DATA
      if(ioutput.eq.1) then
#if defined FVW
		WRITE(24) psiout(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
#endif
        WRITE(25) sliprateoutZ(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
		WRITE(27) sliprateoutX(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
        WRITE(26) SCHANGEZ(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
        WRITE(28) SCHANGEX(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
        write(29) v1t(nabc+1:nxt-nabc,nabc+1:nzt-nfs)
        do i=1,Nstations
          write (30+i,*)seisU(i),seisV(i),seisW(i)
        enddo
      endif
 
      k=int(real(it-1)*dt/dtseis)+1
      if(k<1.or.k>nSR)write(*,*)'CHYBA!',k
      do j=1,NW
        jto=max(1,int(dW/dh*j))+1+nabc
        jfrom=min(jto,int(dW/dh*(j-1))+1)+1+nabc
        do i=1,NL
          ifrom=int(dL/dh*(i-1))+1+nabc
          ito=int(dL/dh*i)+nabc
          kk=((j-1)*NL+i-1)*nSR+k
          MSRX(kk)=MSRX(kk)+sum(sliprateoutX(ifrom:ito,jfrom:jto))/dble((ito-ifrom+1)*(jto-jfrom+1)*(dtseis/dt))
          MSRZ(kk)=MSRZ(kk)+sum(sliprateoutZ(ifrom:ito,jfrom:jto))/dble((ito-ifrom+1)*(jto-jfrom+1)*(dtseis/dt))

        enddo
      enddo
	  
	  do j = nabc+1,nzt-nfs
		do i = nabc+1,nxt-nabc
			MomentRate(k)=MomentRate(k)+sqrt(sliprateoutX(i,j)**2+sliprateoutZ(i,j)**2)*mu1(i,nysc,j)*dh*dh/(dtseis/dt)
		enddo
	  enddo
	  
    
        if(mod(it,int(1./dt))==0)then
          maxvelZ=maxval(sliprateoutZ(nabc+1:nxt-nabc,nabc+1:nzt-nfs))
          maxvelX=maxval(sliprateoutX(nabc+1:nxt-nabc,nabc+1:nzt-nfs))
          write(*,*)'Time: ',time,'Slip rate max: ',maxvelX,maxvelZ
#if defined DIPSLIP
          if(maxvelZ>maxvelsave)maxvelsave=maxvelZ
!          if (maxvelZ<=0.01*maxvelsave)exit
#else
          if(maxvelX>maxvelsave)maxvelsave=maxvelX
!          if (maxvelX<=0.01*maxvelsave)exit
#endif
        endif
      enddo ! --- End of the time loop
    
      !$ACC END DATA

      SCHANGEZ(:,:)=SCHANGEZ(:,:)-striniZ(:,:)   !stress drop
      SCHANGEX(:,:)=SCHANGEX(:,:)-striniX(:,:)
      
      deallocate(u1,v1,w1)
      deallocate(xx,yy,zz,xy,yz,xz)
      deallocate(tx,tz,v1t,avdx,avdz, RFx,RFz)

      deallocate(omega_pml,omegaR_pml,omega_pmlM,omegaR_pmlM,au1,av1,aw1)
      deallocate (omegax1,omegay1,omegaz1,omegaxS1)    
      deallocate (u11,u12,u13,v11,v12,v13,w11,w12,w13)
      deallocate (xx11,xx12,xx13,yy11,yy12,yy13,zz11,zz12,zz13,xz11,xz12,xy11,xy12,yz11,yz12)
      deallocate (omegax2,omegay2,omegaz2,omegaxS2)      
      deallocate (u21,u22,u23,v21,v22,v23,w21,w22,w23)
      deallocate (xx21,xx22,xx23,yy21,yy22,yy23,zz21,zz22,zz23,xz21,xz22,xy21,xy22,yz21,yz22)  
      deallocate (omegax3,omegay3,omegaz3,omegaxS3,omegayS3) 
      deallocate (u31,u32,u33,v31,v32,v33,w31,w32,w33)
      deallocate (xx31,xx32,xx33,yy31,yy32,yy33,zz31,zz32,zz33,xz31,xz32,xy31,xy32,yz31,yz32)  
      deallocate (omegax4,omegay4,omegaz4,omegaxS4,omegayS4,omegazS4)
      deallocate (u41,u42,u43,v41,v42,v43,w41,w42,w43)
      deallocate (xx41,xx42,xx43,yy41,yy42,yy43,zz41,zz42,zz43,xz41,xz42,xy41,xy42,yz41,yz42)    

      CALL CPU_TIME(CPUT2)
      PRINT *,'CPU TIME OF TIME LOOP: ',CPUT2-CPUT1


!-------------------
! Open output files:
!-------------------
      if(ioutput.eq.1) then
#if defined FVW
		close(24)
#endif	  
        close(25)
        close(26)
		close(27)
		close(28)
		close(29)
      endif
	  
	  rise=rise-ruptime
	  
      tmax            = -1.
      output_param(1) =  0.
      nsurf           =  0
      output_param(2) =  0.
      numer           =  0.
      denom           =  0.
      do k = nabc+1,nzt-nfs	
        do i = nabc+1,nxt-nabc
          ! --- Surface of rupture:
          if (incrack(i,k).eq.1) nsurf = nsurf + 1
          
		  output_param(3) = nsurf * (dh*dh)
          ! --- Seismic moment:
          output_param(2) = output_param(2) + slipZ(i,k)*mu1(i,nysc,k)*(dh*dh)
          ! --- Stress drop:
          
          numer = numer + sqrt((schangeZ(i,k)*slipZ(i,k))**2+(schangeX(i,k)*slipX(i,k))**2)
          denom = denom + slipZ(i,k)
          if (denom .ne. 0.0) then
            output_param(4) = -(numer/denom)
          else
            output_param(4) = 0.0
          endif
        enddo
      enddo
   !   output_param(5) = (1./2.)**sum(peak_xz*Dc)/dble((nxt-2*nabc)*(nzt-nfs-nabc))
    !  output_param(6) = (1./2.)*output_param(4)*(output_param(2)/(mu_mean*output_param(3)))
      M0=output_param(2)

!---------------------------
! Write down the output
!---------------------------
       if (ioutput.eq.1) then
         open(96,file='result/risetime.res')
         open(97,file='result/ruptime.res')
         open(98,file='result/slip.res')
         open(99,file='result/stressdrop.res')
         do k = nabc+1,nzt-nfs
           do i = nabc+1,nxt-nabc
		   
             write(96,*) rise(i,k)
             write(97,*) ruptime(i,k)
             write(98,*) slipZ(i,k)
             write(99,*) schangeZ(i,k)
           enddo
         enddo
         close(96)
         close(97)
         close(98)
         close(99)

         open(501,file='result/contour.res')
         write(501,*) 'j k t'
         do k = nabc+1,nzt-nfs
           do i = nabc+1,nxt-nabc
             write (501,*) (real(i-nabc-1) - real(nxt-2*nabc)/2.)*dh,real(k-nabc-1)*dh,ruptime(i,k) 
           enddo
         enddo		
         close(501)
         open(502,file='result/czone.res')
         open(503,file='result/rvel.res')
		 tint=0.
		 tint2=0.
         do k = nabc+1,nzt-nfs
           do i = nabc+1,nxt-nabc
             cz=0.
             rv=0.
             if ((ruptime(i,k).ne.1.e4).and.(ruptime(i+1,k).ne.1.e4).and.(ruptime(i,k+1).ne.1.e4).and.(ruptime(i-1,k).ne.1.e4).and.(ruptime(i,k-1).ne.1.e4)) then
               if (sliptime(i,k).ne.1.e4) then
                 rv = (sqrt((ruptime(i+1,k)-ruptime(i,k))**2+(ruptime(i,k+1)-ruptime(i,k))**2)+sqrt((ruptime(i,k)-ruptime(i-1,k))**2+(ruptime(i,k)-ruptime(i,k-1))**2))
                 if (rv.ne.0.) then
                   rv=2*dh/(sqrt((ruptime(i+1,k)-ruptime(i,k))**2+(ruptime(i,k+1)-ruptime(i,k))**2)+sqrt((ruptime(i,k)-ruptime(i-1,k))**2+(ruptime(i,k)-ruptime(i,k-1))**2))
				   tint=tint+rv*slipZ(i,k)
				   tint2=tint2+slipZ(i,k)
                 else
                   rv = 0.
                 endif
                 cz=rv*(sliptime(i,k)-ruptime(i,k))
               endif
             endif
             write (502,*) cz
             write (503,*) rv
           enddo
         enddo
		 output_param(1)=tint/tint2
         close(502)
         close(503)
       endif

       END
