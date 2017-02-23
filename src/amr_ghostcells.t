!=============================================================================
subroutine getbc(time,qdt,ixG^L,pwuse,pwuseCo,pgeoFi,pgeoCo,richardson,nwstart,nwbc)

include 'amrvacdef.f'

double precision, intent(in)               :: time, qdt
integer, intent(in)                        :: ixG^L,nwstart,nwbc
type(walloc), dimension(ngridshi)          :: pwuse, pwuseCo
type(geoalloc), target,dimension(ngridshi) :: pgeoFi, pgeoCo
logical, intent(in)                        :: richardson

integer :: ixM^L, ixCoG^L, ixCoM^L, idims, iside
integer :: my_neighbor_type, ipole
integer :: iigrid, igrid, ineighbor, ipe_neighbor
integer :: nrecvs, nsends, isizes
integer :: ixR^L, ixS^L
integer :: ixB^L
integer :: k^L
integer :: i^D, n_i^D, ic^D, inc^D, n_inc^D
integer, dimension(-1:1) :: ixS_srl_^L, ixR_srl_^L, ixS_r_^L
integer, dimension(0:3) :: ixR_r_^L, ixS_p_^L, ixR_p_^L, &
                           ixS_old_^L, ixR_old_^L
integer, dimension(-1:1^D&) :: type_send_srl, type_recv_srl, type_send_r
integer, dimension(0:3^D&) :: type_recv_r, type_send_p, type_recv_p, &
                              type_send_old, type_recv_old
integer :: isend_buf(npwbuf), ipwbuf
type(walloc) :: pwbuf(npwbuf)
logical  :: isphysbound

double precision :: time_bcin
{#IFDEF STRETCHGRID
double precision :: logGl,qstl
}
!-----------------------------------------------------------------------------
time_bcin=MPI_WTIME()

call init_bc
if (internalboundary) then 
   call getintbc(time,ixG^L,pwuse)
end if

! default : no singular axis
ipole=0

irecv=0
isend=0
isend_buf=0
ipwbuf=1
nrecvs=nrecv_bc_srl+nrecv_bc_r
nsends=nsend_bc_srl+nsend_bc_r
if (richardson) then
   nrecvs=nrecvs+nrecv_bc_p
   nsends=nsends+nsend_bc_p
end if
if (nrecvs>0) then
   allocate(recvstatus(MPI_STATUS_SIZE,nrecvs),recvrequest(nrecvs))
   recvrequest=MPI_REQUEST_NULL
end if
if (nsends>0) then
   allocate(sendstatus(MPI_STATUS_SIZE,nsends),sendrequest(nsends))
   sendrequest=MPI_REQUEST_NULL
end if

do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
      
   {do i^DB=-1,1\}
      if (i^D==0|.and.) cycle

      my_neighbor_type=neighbor_type(i^D,igrid)
      select case (my_neighbor_type)
      case (2)
         if (richardson) call bc_recv_old
      case (3)
         call bc_recv_srl
      case (4)
         call bc_recv_restrict
      end select
   {end do\}
end do

do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
   if (any(neighbor_type(:^D&,igrid)==2)) then
      if (richardson) then
         ^D&dxlevel(^D)=two*rnode(rpdx^D_,igrid);
      else
         ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
      end if
      call coarsen_grid(pwuse(igrid)%w,px(igrid)%x,ixG^L,ixM^L,pwuseCo(igrid)%w,pxCoarse(igrid)%x, &
                        ixCoG^L,ixCoM^L,pgeoFi(igrid),pgeoCo(igrid), &
                        coarsenprimitive,.true.)
   end if
   {do i^DB=-1,1\}
      if (i^D==0|.and.) cycle

      {^IFPHI ipole=neighbor_pole(i^D,igrid)}
      my_neighbor_type=neighbor_type(i^D,igrid)
      select case (my_neighbor_type)
      case (2)
         call bc_send_restrict
      case (3)
         call bc_send_srl
      case (4)
         if (richardson) call bc_send_old
      end select
   {end do\}
end do

if (irecv/=nrecvs) then
   call mpistop("number of recvs in phase1 in amr_ghostcells is incorrect")
end if
if (isend/=nsends) then
   call mpistop("number of sends in phase1 in amr_ghostcells is incorrect")
end if

if (irecv>0) then
   call MPI_WAITALL(irecv,recvrequest,recvstatus,ierrmpi)
   deallocate(recvstatus,recvrequest)
end if
if (isend>0) then
   call MPI_WAITALL(isend,sendrequest,sendstatus,ierrmpi)
   deallocate(sendstatus,sendrequest)
   do ipwbuf=1,npwbuf
      if (isend_buf(ipwbuf)/=0) deallocate(pwbuf(ipwbuf)%w)
   end do
end if


if (.not.richardson) then
   irecv=0
   isend=0
   isend_buf=0
   ipwbuf=1
   nrecvs=nrecv_bc_p
   nsends=nsend_bc_p
   if (nrecvs>0) then
      allocate(recvstatus(MPI_STATUS_SIZE,nrecvs),recvrequest(nrecvs))
      recvrequest=MPI_REQUEST_NULL
   end if
   if (nsends>0) then
      allocate(sendstatus(MPI_STATUS_SIZE,nsends),sendrequest(nsends))
      sendrequest=MPI_REQUEST_NULL
   end if

   do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
      
      {do i^DB=-1,1\}
         if (i^D==0|.and.) cycle

         my_neighbor_type=neighbor_type(i^D,igrid)
         if (my_neighbor_type==2) call bc_recv_prolong
      {end do\}
   end do
   do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
      ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
     if (any(neighbor_type(:^D&,igrid)==4)) then
      {do i^DB=-1,1\}
         if (i^D==0|.and.) cycle

         {^IFPHI ipole=neighbor_pole(i^D,igrid)}
         my_neighbor_type=neighbor_type(i^D,igrid)
         if (my_neighbor_type==4) call bc_send_prolong
      {end do\}
     end if
   end do


   if (irecv/=nrecvs) then
      call mpistop("number of recvs in phase2 in amr_ghostcells is incorrect")
   end if
   if (isend/=nsends) then
      call mpistop("number of sends in phase2 in amr_ghostcells is incorrect")
   end if

   if (irecv>0) then
      call MPI_WAITALL(irecv,recvrequest,recvstatus,ierrmpi)
      deallocate(recvstatus,recvrequest)
   end if

   do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
      ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
      if (any(neighbor_type(:^D&,igrid)==2)) then
         {do i^DB=-1,1\}
            if (i^D==0|.and.) cycle
            my_neighbor_type=neighbor_type(i^D,igrid)
            if (my_neighbor_type==2) call bc_prolong
         {end do\}
      end if
   end do

   if (isend>0) then
      call MPI_WAITALL(isend,sendrequest,sendstatus,ierrmpi)
      deallocate(sendstatus,sendrequest)
      do ipwbuf=1,npwbuf
         if (isend_buf(ipwbuf)/=0) deallocate(pwbuf(ipwbuf)%w)
      end do
   end if
end if

if(bcphys) then
!$OMP PARALLEL DO PRIVATE(igrid,kmin^D,kmax^D,ixBmin^D,ixBmax^D,iside,i^D,isphysbound)
  do iigrid=1,igridstail; igrid=igrids(iigrid);
     saveigrid=igrid
     ^D&dxlevel(^D)=rnode(rpdx^D_,igrid);
     do idims=1,ndim
        ! to avoid using as yet unknown corner info in more than 1D, we
        ! fill only interior mesh ranges of the ghost cell ranges at first,
        ! and progressively enlarge the ranges to include corners later
        kmin1=0; kmax1=0;
        {^IFTWOD
         kmin2=merge(1, 0,  idims .lt. 2 .and. neighbor_type(0,-1,igrid)==1)
         kmax2=merge(1, 0,  idims .lt. 2 .and. neighbor_type(0, 1,igrid)==1)}
        {^IFTHREED
         kmin2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0,-1,0,igrid)==1)
         kmax2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0, 1,0,igrid)==1)
         kmin3=merge(1, 0, idims .lt. 3 .and. neighbor_type(0,0,-1,igrid)==1)
         kmax3=merge(1, 0, idims .lt. 3 .and. neighbor_type(0,0, 1,igrid)==1)}
        ixBmin^D=ixGmin^D+kmin^D*dixB;
        ixBmax^D=ixGmax^D-kmax^D*dixB;
        do iside=1,2
           i^D=kr(^D,idims)*(2*iside-3);
           if (aperiodB(idims)) then 
              call physbound(i^D,igrid,isphysbound)
              if (neighbor_type(i^D,igrid)/=1 .and. .not. isphysbound) cycle
           else 
              if (neighbor_type(i^D,igrid)/=1) cycle
           end if
           if (richardson) then
              if(.not.slab)mygeo=>pgeoCo(igrid)
              call bc_phys(iside,idims,time,qdt,pwuse(igrid)%w,pxCoarse(igrid)%x,ixG^L,ixB^L)
           else
              if(.not.slab)mygeo=>pgeoFi(igrid)
              if (B0field) then
                 myB0_cell => pB0_cell(igrid)
                 {^D&myB0_face^D => pB0_face^D(igrid)\}
              end if
              call bc_phys(iside,idims,time,qdt,pwuse(igrid)%w,px(igrid)%x,ixG^L,ixB^L)
           end if
        end do
     end do
  end do
!$OMP END PARALLEL DO
end if

if (npe>1) call put_bc_comm_types

if (nwaux>0) call fix_auxiliary

time_bc=time_bc+(MPI_WTIME()-time_bcin)

contains
!=============================================================================
! internal procedures
!=============================================================================
subroutine bc_send_srl
!-----------------------------------------------------------------------------
ineighbor=neighbor(1,i^D,igrid)
ipe_neighbor=neighbor(2,i^D,igrid)


if (ipole==0) then
   n_i^D=-i^D;
   if (ipe_neighbor==mype) then
      ixS^L=ixS_srl_^L(i^D);
      ixR^L=ixR_srl_^L(n_i^D);
      pwuse(ineighbor)%w(ixR^S,nwstart+1:nwstart+nwbc)=pwuse(igrid)%w(ixS^S,nwstart+1:nwstart+nwbc)
   else
      isend=isend+1
      itag=(3**^ND+4**^ND)*(ineighbor-1)+{(n_i^D+1)*3**(^D-1)+}
      call MPI_ISEND(pwuse(igrid)%w,1,type_send_srl(i^D), &
                     ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
   end if
else
   ixS^L=ixS_srl_^L(i^D);
   select case (ipole)
   {case (^D)
      n_i^D=i^D^D%n_i^DD=-i^DD;\}
   end select
   if (ipe_neighbor==mype) then
      ixR^L=ixR_srl_^L(n_i^D);
      call pole_copy(pwuse(ineighbor),ixR^L,pwuse(igrid),ixS^L)
   else
      if (isend_buf(ipwbuf)/=0) then
         call MPI_WAIT(sendrequest(isend_buf(ipwbuf)), &
                       sendstatus(1,isend_buf(ipwbuf)),ierrmpi)
         deallocate(pwbuf(ipwbuf)%w)
      end if
      allocate(pwbuf(ipwbuf)%w(ixS^S,nwstart+1:nwstart+nwbc))
      call pole_copy(pwbuf(ipwbuf),ixS^L,pwuse(igrid),ixS^L)
      isend=isend+1
      isend_buf(ipwbuf)=isend
      itag=(3**^ND+4**^ND)*(ineighbor-1)+{(n_i^D+1)*3**(^D-1)+}
      isizes={(ixSmax^D-ixSmin^D+1)*}*nwbc
      call MPI_ISEND(pwbuf(ipwbuf)%w,isizes,MPI_DOUBLE_PRECISION, &
                     ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
      ipwbuf=1+modulo(ipwbuf,npwbuf)
   end if
end if

end subroutine bc_send_srl
!=============================================================================
subroutine bc_send_restrict
!-----------------------------------------------------------------------------
ic^D=1+modulo(node(pig^D_,igrid)-1,2);
if ({.not.(i^D==0.or.i^D==2*ic^D-3)|.or.}) return

ineighbor=neighbor(1,i^D,igrid)
ipe_neighbor=neighbor(2,i^D,igrid)

if (ipole==0) then
   n_inc^D=-2*i^D+ic^D;
   if (ipe_neighbor==mype) then
      ixS^L=ixS_r_^L(i^D);
      ixR^L=ixR_r_^L(n_inc^D);
      pwuse(ineighbor)%w(ixR^S,nwstart+1:nwstart+nwbc)=pwuseCo(igrid)%w(ixS^S,nwstart+1:nwstart+nwbc)
   else
      isend=isend+1
      itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
      call MPI_ISEND(pwuseCo(igrid)%w,1,type_send_r(i^D), &
                     ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
   end if
else
   ixS^L=ixS_r_^L(i^D);
   select case (ipole)
   {case (^D)
      n_inc^D=2*i^D+(3-ic^D)^D%n_inc^DD=-2*i^DD+ic^DD;\}
   end select
   if (ipe_neighbor==mype) then
      ixR^L=ixR_r_^L(n_inc^D);
      call pole_copy(pwuse(ineighbor),ixR^L,pwuseCo(igrid),ixS^L)
   else
      if (isend_buf(ipwbuf)/=0) then
         call MPI_WAIT(sendrequest(isend_buf(ipwbuf)), &
                       sendstatus(1,isend_buf(ipwbuf)),ierrmpi)
         deallocate(pwbuf(ipwbuf)%w)
      end if
      allocate(pwbuf(ipwbuf)%w(ixS^S,nwstart+1:nwstart+nwbc))
      call pole_copy(pwbuf(ipwbuf),ixS^L,pwuseCo(igrid),ixS^L)
      isend=isend+1
      isend_buf(ipwbuf)=isend
      itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
      isizes={(ixSmax^D-ixSmin^D+1)*}*nwbc
      call MPI_ISEND(pwbuf(ipwbuf)%w,isizes,MPI_DOUBLE_PRECISION, &
                     ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
      ipwbuf=1+modulo(ipwbuf,npwbuf)
   end if
end if

end subroutine bc_send_restrict
!=============================================================================
subroutine bc_send_prolong
integer :: ii^D
!-----------------------------------------------------------------------------
{do ic^DB=1+int((1-i^DB)/2),2-int((1+i^DB)/2)
   inc^DB=2*i^DB+ic^DB\}

   ixS^L=ixS_p_^L(inc^D);

   if(bcphys) then
     do idims=1,ndim
        do iside=1,2
           ii^D=kr(^D,idims)*(2*iside-3);

           if (neighbor_type(ii^D,igrid)/=1) cycle

           if ((  {(iside==1.and.idims==^D.and.ixSmin^D<ixMlo^D)|.or. }) &
            .or.( {(iside==2.and.idims==^D.and.ixSmax^D>ixMhi^D)|.or. }))then
            {ixBmin^D=merge(ixGmin^D,ixSmin^D,idims==^D);}
            {ixBmax^D=merge(ixGmax^D,ixSmax^D,idims==^D);}
           ! to avoid using as yet unknown corner info in more than 1D, we
           ! fill only interior mesh ranges of the ghost cell ranges at first,
           ! and progressively enlarge the ranges to include corners later
            kmin1=0; kmax1=0;
           {^IFTWOD
            kmin2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0,-1,  igrid)==1)
            kmax2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0, 1,  igrid)==1)
            if(neighbor_type(0,-1,igrid)==1.and.(neighbor_type(1,0,igrid)==1&
               .or. neighbor_type(-1,0,igrid)==1) .and. i2== 1) kmin2=0
            if(neighbor_type(0, 1,igrid)==1.and.(neighbor_type(1,0,igrid)==1&
               .or. neighbor_type(-1,0,igrid)==1) .and. i2==-1) kmax2=0}
           {^IFTHREED
            kmin2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0,-1,0,igrid)==1)
            kmax2=merge(1, 0, idims .lt. 2 .and. neighbor_type(0, 1,0,igrid)==1)
            kmin3=merge(1, 0, idims .lt. 3 .and. neighbor_type(0,0,-1,igrid)==1)
            kmax3=merge(1, 0, idims .lt. 3 .and. neighbor_type(0,0, 1,igrid)==1)
            if(neighbor_type(0,-1,0,igrid)==1.and.(neighbor_type(1,0,0,igrid)==1&
               .or. neighbor_type(-1,0,0,igrid)==1) .and. i2== 1) kmin2=0
            if(neighbor_type(0, 1,0,igrid)==1.and.(neighbor_type(1,0,0,igrid)==1&
               .or. neighbor_type(-1,0,0,igrid)==1) .and. i2==-1) kmax2=0
            if(neighbor_type(0,0,-1,igrid)==1.and.(neighbor_type(0,1,0,igrid)==1&
               .or. neighbor_type(0,-1,0,igrid)==1) .and. i3== 1) kmin3=0
            if(neighbor_type(0,0, 1,igrid)==1.and.(neighbor_type(0,1,0,igrid)==1&
               .or. neighbor_type(0,-1,0,igrid)==1) .and. i3==-1) kmax3=0}
            ixBmin^D=ixBmin^D+kmin^D;
            ixBmax^D=ixBmax^D-kmax^D;

            if(.not.slab)mygeo=>pgeoFi(igrid)
            if (B0field) then
              myB0_cell => pB0_cell(igrid)
              {^D&myB0_face^D => pB0_face^D(igrid)\}
            end if

            call bc_phys(iside,idims,time,qdt,pwuse(igrid)%w, &
                              px(igrid)%x,ixG^L,ixB^L)
           end if
        end do
     end do
   end if

   ineighbor=neighbor_child(1,inc^D,igrid)
   ipe_neighbor=neighbor_child(2,inc^D,igrid)

   if (ipole==0) then
      n_i^D=-i^D;
      n_inc^D=ic^D+n_i^D;
      if (ipe_neighbor==mype) then
         ixR^L=ixR_p_^L(n_inc^D);
         pwuseCo(ineighbor)%w(ixR^S,nwstart+1:nwstart+nwbc) &
            =pwuse(igrid)%w(ixS^S,nwstart+1:nwstart+nwbc)
      else
         isend=isend+1
         itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
         call MPI_ISEND(pwuse(igrid)%w,1,type_send_p(inc^D), &
                        ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
      end if
   else
      select case (ipole)
      {case (^D)
         n_inc^D=inc^D^D%n_inc^DD=ic^DD-i^DD;\}
      end select
      if (ipe_neighbor==mype) then
         ixR^L=ixR_p_^L(n_inc^D);
         call pole_copy(pwuseCo(ineighbor),ixR^L,pwuse(igrid),ixS^L)
      else
         if (isend_buf(ipwbuf)/=0) then
            call MPI_WAIT(sendrequest(isend_buf(ipwbuf)), &
                          sendstatus(1,isend_buf(ipwbuf)),ierrmpi)
            deallocate(pwbuf(ipwbuf)%w)
         end if
         allocate(pwbuf(ipwbuf)%w(ixS^S,nwstart+1:nwstart+nwbc))
         call pole_copy(pwbuf(ipwbuf),ixS^L,pwuse(igrid),ixS^L)
         isend=isend+1
         isend_buf(ipwbuf)=isend
         itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
         isizes={(ixSmax^D-ixSmin^D+1)*}*nwbc
         call MPI_ISEND(pwbuf(ipwbuf)%w,isizes,MPI_DOUBLE_PRECISION, &
                        ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
         ipwbuf=1+modulo(ipwbuf,npwbuf)
      end if
   end if
{end do\}

end subroutine bc_send_prolong
!=============================================================================
subroutine bc_send_old
!-----------------------------------------------------------------------------
{do ic^DB=1+int((1-i^DB)/2),2-int((1+i^DB)/2)
   inc^DB=2*i^DB+ic^DB\}

   ineighbor=neighbor_child(1,inc^D,igrid)
   ipe_neighbor=neighbor_child(2,inc^D,igrid)

   if (ipole==0) then
      n_i^D=-i^D;
      n_inc^D=ic^D+n_i^D;
      if (ipe_neighbor==mype) then
         ixS^L=ixS_old_^L(inc^D);
         ixR^L=ixR_old_^L(n_inc^D);
         pwuse(ineighbor)%w(ixR^S,nwstart+1:nwstart+nwbc) &
            =pwold(igrid)%w(ixS^S,nwstart+1:nwstart+nwbc)
      else
         isend=isend+1
         itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
         call MPI_ISEND(pwold(igrid)%w,1,type_send_old(inc^D), &
                        ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
      end if
   else
      ixS^L=ixS_old_^L(inc^D);
      select case (ipole)
      {case (^D)
         n_inc^D=inc^D^D%n_inc^DD=ic^DD-i^DD;\}
      end select
      if (ipe_neighbor==mype) then
         ixR^L=ixR_old_^L(n_inc^D);
         call pole_copy(pwuse(ineighbor),ixR^L,pwold(igrid),ixS^L)
      else
         if (isend_buf(ipwbuf)/=0) then
            call MPI_WAIT(sendrequest(isend_buf(ipwbuf)), &
                          sendstatus(1,isend_buf(ipwbuf)),ierrmpi)
            deallocate(pwbuf(ipwbuf)%w)
         end if
         allocate(pwbuf(ipwbuf)%w(ixS^S,nwstart+1:nwstart+nwbc))
         call pole_copy(pwbuf(ipwbuf),ixS^L,pwold(igrid),ixS^L)
         isend=isend+1
         isend_buf(ipwbuf)=isend
         itag=(3**^ND+4**^ND)*(ineighbor-1)+3**^ND+{n_inc^D*4**(^D-1)+}
         isizes={(ixSmax^D-ixSmin^D+1)*}*nwbc
         call MPI_ISEND(pwbuf(ipwbuf)%w,isizes,MPI_DOUBLE_PRECISION, &
                        ipe_neighbor,itag,icomm,sendrequest(isend),ierrmpi)
         ipwbuf=1+modulo(ipwbuf,npwbuf)
      end if
   end if

{end do\}

end subroutine bc_send_old
!=============================================================================
subroutine bc_recv_srl
!-----------------------------------------------------------------------------
ipe_neighbor=neighbor(2,i^D,igrid)
if (ipe_neighbor/=mype) then
   irecv=irecv+1
   itag=(3**^ND+4**^ND)*(igrid-1)+{(i^D+1)*3**(^D-1)+}
   call MPI_IRECV(pwuse(igrid)%w,1,type_recv_srl(i^D), &
                  ipe_neighbor,itag,icomm,recvrequest(irecv),ierrmpi)
end if

end subroutine bc_recv_srl
!=============================================================================
subroutine bc_recv_restrict
!-----------------------------------------------------------------------------
{do ic^DB=1+int((1-i^DB)/2),2-int((1+i^DB)/2)
   inc^DB=2*i^DB+ic^DB\}
   ipe_neighbor=neighbor_child(2,inc^D,igrid)
   if (ipe_neighbor/=mype) then
      irecv=irecv+1
      itag=(3**^ND+4**^ND)*(igrid-1)+3**^ND+{inc^D*4**(^D-1)+}
      call MPI_IRECV(pwuse(igrid)%w,1,type_recv_r(inc^D), &
                     ipe_neighbor,itag,icomm,recvrequest(irecv),ierrmpi)
   end if
{end do\}

end subroutine bc_recv_restrict
!=============================================================================
subroutine bc_recv_prolong
!-----------------------------------------------------------------------------
ic^D=1+modulo(node(pig^D_,igrid)-1,2);
if ({.not.(i^D==0.or.i^D==2*ic^D-3)|.or.}) return

ipe_neighbor=neighbor(2,i^D,igrid)
if (ipe_neighbor/=mype) then
   irecv=irecv+1
   inc^D=ic^D+i^D;
   itag=(3**^ND+4**^ND)*(igrid-1)+3**^ND+{inc^D*4**(^D-1)+}
   call MPI_IRECV(pwuseCo(igrid)%w,1,type_recv_p(inc^D), &
                  ipe_neighbor,itag,icomm,recvrequest(irecv),ierrmpi)  
end if

end subroutine bc_recv_prolong
!=============================================================================
subroutine bc_recv_old
!-----------------------------------------------------------------------------
ic^D=1+modulo(node(pig^D_,igrid)-1,2);
if ({.not.(i^D==0.or.i^D==2*ic^D-3)|.or.}) return

ipe_neighbor=neighbor(2,i^D,igrid)
if (ipe_neighbor/=mype) then
   irecv=irecv+1
   inc^D=ic^D+i^D;
   itag=(3**^ND+4**^ND)*(igrid-1)+3**^ND+{inc^D*4**(^D-1)+}
   call MPI_IRECV(pwuse(igrid)%w,1,type_recv_old(inc^D), &
                  ipe_neighbor,itag,icomm,recvrequest(irecv),ierrmpi)
end if

end subroutine bc_recv_old
!=============================================================================
subroutine bc_prolong

integer :: ixFi^L,ixCo^L,ii^D
double precision :: dxFi^D, dxCo^D, xFimin^D, xComin^D, invdxCo^D
!-----------------------------------------------------------------------------
ixFi^L=ixR_srl_^L(i^D);

dxFi^D=rnode(rpdx^D_,igrid);
dxCo^D=two*dxFi^D;
invdxCo^D=1.d0/dxCo^D;

xFimin^D=rnode(rpxmin^D_,igrid)-dble(dixB)*dxFi^D;
xComin^D=rnode(rpxmin^D_,igrid)-dble(dixB)*dxCo^D;
{#IFDEF STRETCHGRID
qst=qsts(node(plevel_,igrid))
logG=logGs(node(plevel_,igrid))
qstl=qsts(node(plevel_,igrid)-1)
logGl=logGs(node(plevel_,igrid)-1)
xFimin1=rnode(rpxmin1_,igrid)*qst**(-dixB)
xComin1=rnode(rpxmin1_,igrid)*qstl**(-dixB)
}

! moved the physical boundary filling here, to only fill the
! part needed

ixComin^D=int((xFimin^D+(dble(ixFimin^D)-half)*dxFi^D-xComin^D)*invdxCo^D)+1-1;
ixComax^D=int((xFimin^D+(dble(ixFimax^D)-half)*dxFi^D-xComin^D)*invdxCo^D)+1+1;

if(bcphys) then
  do idims=1,ndim
     do iside=1,2
        ii^D=kr(^D,idims)*(2*iside-3);
  
        if (neighbor_type(ii^D,igrid)/=1) cycle
  
        if  (( {(iside==1.and.idims==^D.and.ixComin^D<ixCoGmin^D+dixB)|.or.} ) &
         .or.( {(iside==2.and.idims==^D.and.ixComax^D>ixCoGmax^D-dixB)|.or. }))then
          {ixBmin^D=merge(ixCoGmin^D,ixComin^D,idims==^D);}
          {ixBmax^D=merge(ixCoGmax^D,ixComax^D,idims==^D);}
          if(.not.slab)mygeo=>pgeoCo(igrid)
  
          call bc_phys(iside,idims,time,0.d0,pwuseCo(igrid)%w, &
                              pxCoarse(igrid)%x,ixCoG^L,ixB^L)
        end if
     end do
  end do
end if

if (amrentropy) then
   call e_to_rhos(ixCoG^L,ixCo^L,pwuseCo(igrid)%w,pxCoarse(igrid)%x)
else if (prolongprimitive) then
   call primitive(ixCoG^L,ixCo^L,pwuseCo(igrid)%w,pxCoarse(igrid)%x)
end if

select case (typeghostfill)
case ("linear")
   call interpolation_linear(pwuse(igrid),ixFi^L,dxFi^D,xFimin^D, &
                           pwuseCo(igrid),dxCo^D,invdxCo^D,xComin^D)
case ("copy")
   call interpolation_copy(pwuse(igrid),ixFi^L,dxFi^D,xFimin^D, &
                           pwuseCo(igrid),dxCo^D,invdxCo^D,xComin^D)
case ("unlimit")
   call interpolation_unlimit(pwuse(igrid),ixFi^L,dxFi^D,xFimin^D, &
                           pwuseCo(igrid),dxCo^D,invdxCo^D,xComin^D)
case default
   write (unitterm,*) "Undefined typeghostfill ",typeghostfill
   call mpistop("")
end select

if (amrentropy) then
    call rhos_to_e(ixCoG^L,ixCo^L,pwuseCo(igrid)%w,pxCoarse(igrid)%x)
else if (prolongprimitive) then
    call conserve(ixCoG^L,ixCo^L,pwuseCo(igrid)%w,pxCoarse(igrid)%x,patchfalse)
end if

end subroutine bc_prolong
!=============================================================================
subroutine interpolation_linear(pwFi,ixFi^L,dxFi^D,xFimin^D, &
                                pwCo,dxCo^D,invdxCo^D,xComin^D)

integer, intent(in) :: ixFi^L
double precision, intent(in) :: dxFi^D, xFimin^D,dxCo^D, invdxCo^D, xComin^D
type(walloc) :: pwCo, pwFi

integer :: ixCo^D, jxCo^D, hxCo^D, ixFi^D, ix^D, iw, idims
double precision :: xCo^D, xFi^D, eta^D
double precision :: slopeL, slopeR, slopeC, signC, signR
double precision :: slope(nwstart+1:nwstart+nwbc,ndim)
!-----------------------------------------------------------------------------
{do ixFi^DB = ixFi^LIM^DB
   ! cell-centered coordinates of fine grid point
   xFi^DB=xFimin^DB+(dble(ixFi^DB)-half)*dxFi^DB

   ! indices of coarse cell which contains the fine cell
   ixCo^DB=int((xFi^DB-xComin^DB)*invdxCo^DB)+1

   ! cell-centered coordinate for coarse cell
   xCo^DB=xComin^DB+(dble(ixCo^DB)-half)*dxCo^DB\}
{#IFDEF STRETCHGRID
   xFi1=xFimin1/(one-half*logG)*qst**(ixFi1-1)
   do ixCo1=1,ixCoGmax1
     xCo1=xComin1/(one-half*logGl)*qstl**(ixCo1-1)
     if(dabs(xFi1-xCo1)<half*logGl*xCo1) exit
   end do
}
   ! normalized distance between fine/coarse cell center
   ! in coarse cell: ranges from -0.5 to 0.5 in each direction
   ! (origin is coarse cell center)
   if (slab) then
      eta^D=(xFi^D-xCo^D)*invdxCo^D;
   else
      ix^D=2*int((ixFi^D+ixMlo^D)/2)-ixMlo^D;
      {eta^D=(xFi^D-xCo^D)*invdxCo^D &
            *two*(one-pgeoFi(igrid)%dvolume(ixFi^DD) &
            /sum(pgeoFi(igrid)%dvolume(ix^D:ix^D+1^D%ixFi^DD))) \}
{#IFDEF STRETCHGRID
      eta1=(xFi1-xCo1)/(logGl*xCo1)*two*(one-pgeoFi(igrid)%dvolume(ixFi^D) &
            /sum(pgeoFi(igrid)%dvolume(ix1:ix1+1^%1ixFi^D))) 
}
   end if

   do idims=1,ndim
      hxCo^D=ixCo^D-kr(^D,idims)\
      jxCo^D=ixCo^D+kr(^D,idims)\

      do iw=nwstart+1,nwstart+nwbc
         slopeL=pwCo%w(ixCo^D,iw)-pwCo%w(hxCo^D,iw)
         slopeR=pwCo%w(jxCo^D,iw)-pwCo%w(ixCo^D,iw)
         slopeC=half*(slopeR+slopeL)

         ! get limited slope
         signR=sign(one,slopeR)
         signC=sign(one,slopeC)
         select case(typeprolonglimit)
         case('minmod')
           slope(iw,idims)=signR*max(zero,min(dabs(slopeR), &
                                             signR*slopeL))
         case('woodward')
           slope(iw,idims)=two*signR*max(zero,min(dabs(slopeR), &
                              signR*slopeL,signR*half*slopeC))
         case('mcbeta')
           slope(iw,idims)=signR*max(zero,min(mcbeta*dabs(slopeR), &
                              mcbeta*signR*slopeL,signR*slopeC))
         case('koren')
           slope(iw,idims)=signR*max(zero,min(two*signR*slopeL, &
            (dabs(slopeR)+two*slopeL*signR)*third,two*dabs(slopeR)))
         case default
           slope(iw,idims)=signC*max(zero,min(dabs(slopeC), &
                             signC*slopeL,signC*slopeR))
         end select
      end do
   end do

   ! Interpolate from coarse cell using limited slopes
   pwFi%w(ixFi^D,nwstart+1:nwstart+nwbc)=pwCo%w(ixCo^D,nwstart+1:nwstart+nwbc)+{(slope(nwstart+1:nwstart+nwbc,^D)*eta^D)+}

{end do\}

if (amrentropy) then
   call rhos_to_e(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x)
else if (prolongprimitive) then
   call conserve(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x,patchfalse)
end if

end subroutine interpolation_linear
!=============================================================================
subroutine interpolation_copy(pwFi,ixFi^L,dxFi^D,xFimin^D, &
                              pwCo,dxCo^D,invdxCo^D,xComin^D)

integer, intent(in) :: ixFi^L
double precision, intent(in) :: dxFi^D, xFimin^D,dxCo^D, invdxCo^D, xComin^D
type(walloc) :: pwCo, pwFi

integer :: ixCo^D, ixFi^D
double precision :: xFi^D
!-----------------------------------------------------------------------------
{do ixFi^DB = ixFi^LIM^DB
   ! cell-centered coordinates of fine grid point
   xFi^DB=xFimin^DB+(dble(ixFi^DB)-half)*dxFi^DB

   ! indices of coarse cell which contains the fine cell
   ixCo^DB=int((xFi^DB-xComin^DB)*invdxCo^DB)+1\}

   ! Copy from coarse cell
   pwFi%w(ixFi^D,nwstart+1:nwstart+nwbc)=pwCo%w(ixCo^D,nwstart+1:nwstart+nwbc)

{end do\}

if (amrentropy) then
   call rhos_to_e(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x)
else if (prolongprimitive) then
   call conserve(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x,patchfalse)
end if

end subroutine interpolation_copy
!=============================================================================
subroutine interpolation_unlimit(pwFi,ixFi^L,dxFi^D,xFimin^D, &
                                 pwCo,dxCo^D,invdxCo^D,xComin^D)

integer, intent(in) :: ixFi^L
double precision, intent(in) :: dxFi^D, xFimin^D, dxCo^D,invdxCo^D, xComin^D
type(walloc) :: pwCo, pwFi

integer :: ixCo^D, jxCo^D, hxCo^D, ixFi^D, ix^D, idims
double precision :: xCo^D, xFi^D, eta^D
double precision :: slope(nwstart+1:nwstart+nwbc,ndim)
!-----------------------------------------------------------------------------
{do ixFi^DB = ixFi^LIM^DB
   ! cell-centered coordinates of fine grid point
   xFi^DB=xFimin^DB+(dble(ixFi^DB)-half)*dxFi^DB

   ! indices of coarse cell which contains the fine cell
   ixCo^DB=int((xFi^DB-xComin^DB)*invdxCo^DB)+1

   ! cell-centered coordinate for coarse cell
   xCo^DB=xComin^DB+(dble(ixCo^DB)-half)*dxCo^DB\}

   ! normalized distance between fine/coarse cell center
   ! in coarse cell: ranges from -0.5 to 0.5 in each direction
   ! (origin is coarse cell center)
   if (slab) then
      eta^D=(xFi^D-xCo^D)*invdxCo^D;
   else
      ix^D=2*int((ixFi^D+ixMlo^D)/2)-ixMlo^D;
      {eta^D=(xFi^D-xCo^D)*invdxCo^D &
            *two*(one-pgeoFi(igrid)%dvolume(ixFi^DD) &
            /sum(pgeoFi(igrid)%dvolume(ix^D:ix^D+1^D%ixFi^DD))) \}
   end if

   do idims=1,ndim
      hxCo^D=ixCo^D-kr(^D,idims)\
      jxCo^D=ixCo^D+kr(^D,idims)\

      ! get centered slope
      slope(nwstart+1:nwstart+nwbc,idims)=half*(pwCo%w(jxCo^D,nwstart+1:nwstart+nwbc)-pwCo%w(hxCo^D,nwstart+1:nwstart+nwbc))
   end do

   ! Interpolate from coarse cell using centered slopes
   pwFi%w(ixFi^D,nwstart+1:nwstart+nwbc)=pwCo%w(ixCo^D,nwstart+1:nwstart+nwbc)+{(slope(nwstart+1:nwstart+nwbc,^D)*eta^D)+}
{end do\}

if (amrentropy) then
   call rhos_to_e(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x)
else if (prolongprimitive) then
   call conserve(ixG^LL,ixFi^L,pwFi%w,px(igrid)%x,patchfalse)
end if

end subroutine interpolation_unlimit
!=============================================================================
subroutine init_bc

integer :: dixBCo, interpolation_order
integer :: ixoldG^L, ixoldM^L, nx^D, nxCo^D
!-----------------------------------------------------------------------------
ixM^L=ixG^L^LSUBdixB;
ixCoGmin^D=1;
ixCoGmax^D=ixGmax^D/2+dixB;
ixCoM^L=ixCoG^L^LSUBdixB;

if (richardson) then
   ixoldGmin^D=1; ixoldGmax^D=2*ixMmax^D;
   ixoldM^L=ixoldG^L^LSUBdixB;
end if

nx^D=ixMmax^D-ixMmin^D+1;
nxCo^D=nx^D/2;

select case (typeghostfill)
case ("copy")
   interpolation_order=1
case ("linear","unlimit")
   interpolation_order=2
case default
   write (unitterm,*) "Undefined typeghostfill ",typeghostfill
   call mpistop("")
end select
dixBCo=int((dixB+1)/2)

if (dixBCo+interpolation_order-1>dixB) then
   call mpistop("interpolation order for prolongation in getbc to high")
end if

{
ixS_srl_min^D(-1)=ixMmin^D
ixS_srl_min^D(0) =ixMmin^D
ixS_srl_min^D(1) =ixMmax^D+1-dixB
ixS_srl_max^D(-1)=ixMmin^D-1+dixB
ixS_srl_max^D(0) =ixMmax^D
ixS_srl_max^D(1) =ixMmax^D

ixR_srl_min^D(-1)=1
ixR_srl_min^D(0) =ixMmin^D
ixR_srl_min^D(1) =ixMmax^D+1
ixR_srl_max^D(-1)=dixB
ixR_srl_max^D(0) =ixMmax^D
ixR_srl_max^D(1) =ixGmax^D
\}

if (levmin/=levmax) then
{
   ixS_r_min^D(-1)=ixCoMmin^D
   ixS_r_min^D(0) =ixCoMmin^D
   ixS_r_min^D(1) =ixCoMmax^D+1-dixB
   ixS_r_max^D(-1)=ixCoMmin^D-1+dixB
   ixS_r_max^D(0) =ixCoMmax^D
   ixS_r_max^D(1) =ixCoMmax^D

   ixR_r_min^D(0)=1
   ixR_r_min^D(1)=ixMmin^D
   ixR_r_min^D(2)=ixMmin^D+nxCo^D
   ixR_r_min^D(3)=ixMmax^D+1
   ixR_r_max^D(0)=dixB
   ixR_r_max^D(1)=ixMmin^D-1+nxCo^D
   ixR_r_max^D(2)=ixMmax^D
   ixR_r_max^D(3)=ixGmax^D

   if (richardson) then
      ixS_old_min^D(0)=ixoldMmin^D
      ixS_old_min^D(1)=ixoldMmin^D
      ixS_old_min^D(2)=ixoldMmin^D+nx^D-dixB
      ixS_old_min^D(3)=ixoldMmax^D+1-dixB
      ixS_old_max^D(0)=ixoldMmin^D-1+dixB
      ixS_old_max^D(1)=ixoldMmin^D-1+nx^D+dixB
      ixS_old_max^D(2)=ixoldMmax^D
      ixS_old_max^D(3)=ixoldMmax^D

      ixR_old_min^D(0)=1
      ixR_old_min^D(1)=ixMmin^D
      ixR_old_min^D(2)=1
      ixR_old_min^D(3)=ixMmax^D+1
      ixR_old_max^D(0)=dixB
      ixR_old_max^D(1)=ixGmax^D
      ixR_old_max^D(2)=ixMmax^D
      ixR_old_max^D(3)=ixGmax^D
   else
      ixS_p_min^D(0)=ixMmin^D-(interpolation_order-1)
      ixS_p_min^D(1)=ixMmin^D-(interpolation_order-1)
      ixS_p_min^D(2)=ixMmin^D+nxCo^D-dixBCo-(interpolation_order-1)
      ixS_p_min^D(3)=ixMmax^D+1-dixBCo-(interpolation_order-1)
      ixS_p_max^D(0)=ixMmin^D-1+dixBCo+(interpolation_order-1)
      ixS_p_max^D(1)=ixMmin^D-1+nxCo^D+dixBCo+(interpolation_order-1)
      ixS_p_max^D(2)=ixMmax^D+(interpolation_order-1)
      ixS_p_max^D(3)=ixMmax^D+(interpolation_order-1)

      ixR_p_min^D(0)=ixCoMmin^D-dixBCo-(interpolation_order-1)
      ixR_p_min^D(1)=ixCoMmin^D-(interpolation_order-1)
      ixR_p_min^D(2)=ixCoMmin^D-dixBCo-(interpolation_order-1)
      ixR_p_min^D(3)=ixCoMmax^D+1-(interpolation_order-1)
      ixR_p_max^D(0)=dixB+(interpolation_order-1)
      ixR_p_max^D(1)=ixCoMmax^D+dixBCo+(interpolation_order-1)
      ixR_p_max^D(2)=ixCoMmax^D+(interpolation_order-1)
      ixR_p_max^D(3)=ixCoMmax^D+dixBCo+(interpolation_order-1)
   end if
\}
end if

if (npe>1) then
   {do i^DB=-1,1\}
      if (i^D==0|.and.) cycle

      call get_bc_comm_type(type_send_srl(i^D),ixS_srl_^L(i^D),ixG^L)
      call get_bc_comm_type(type_recv_srl(i^D),ixR_srl_^L(i^D),ixG^L)

      if (levmin==levmax) cycle

      call get_bc_comm_type(type_send_r(i^D),ixS_r_^L(i^D),ixCoG^L)
      {do ic^DB=1+int((1-i^DB)/2),2-int((1+i^DB)/2)
         inc^DB=2*i^DB+ic^DB\}
         call get_bc_comm_type(type_recv_r(inc^D),ixR_r_^L(inc^D),ixG^L)
         if (richardson) then
            call get_bc_comm_type(type_send_old(inc^D), &
                                  ixS_old_^L(inc^D),ixoldG^L)
            call get_bc_comm_type(type_recv_old(inc^D), &
                                  ixR_old_^L(inc^D),ixG^L)
         else
            call get_bc_comm_type(type_send_p(inc^D),ixS_p_^L(inc^D),ixG^L)
            call get_bc_comm_type(type_recv_p(inc^D),ixR_p_^L(inc^D),ixCoG^L)
         end if
      {end do\}
   {end do\}
end if

end subroutine init_bc
!=============================================================================
subroutine get_bc_comm_type(comm_type,ix^L,ixG^L)

integer, intent(inout) :: comm_type
integer, intent(in) :: ix^L, ixG^L

integer, dimension(ndim+1) :: size, subsize, start
!-----------------------------------------------------------------------------
^D&size(^D)=ixGmax^D;
size(ndim+1)=nw
^D&subsize(^D)=ixmax^D-ixmin^D+1;
subsize(ndim+1)=nwbc
^D&start(^D)=ixmin^D-1;
start(ndim+1)=nwstart

call MPI_TYPE_CREATE_SUBARRAY(ndim+1,size,subsize,start,MPI_ORDER_FORTRAN, &
                              MPI_DOUBLE_PRECISION,comm_type,ierrmpi)
call MPI_TYPE_COMMIT(comm_type,ierrmpi)

end subroutine get_bc_comm_type
!=============================================================================
subroutine put_bc_comm_types
!-----------------------------------------------------------------------------
{do i^DB=-1,1\}
   if (i^D==0|.and.) cycle

   call MPI_TYPE_FREE(type_send_srl(i^D),ierrmpi)
   call MPI_TYPE_FREE(type_recv_srl(i^D),ierrmpi)

   if (levmin==levmax) cycle

   call MPI_TYPE_FREE(type_send_r(i^D),ierrmpi)
   {do ic^DB=1+int((1-i^DB)/2),2-int((1+i^DB)/2)
      inc^DB=2*i^DB+ic^DB\}
      call MPI_TYPE_FREE(type_recv_r(inc^D),ierrmpi)
      if (richardson) then
         call MPI_TYPE_FREE(type_send_old(inc^D),ierrmpi)
         call MPI_TYPE_FREE(type_recv_old(inc^D),ierrmpi)
      else
         call MPI_TYPE_FREE(type_send_p(inc^D),ierrmpi)
         call MPI_TYPE_FREE(type_recv_p(inc^D),ierrmpi)
      end if
   {end do\}
{end do\}

end subroutine put_bc_comm_types
!=============================================================================
subroutine pole_copy(pwrecv,ixR^L,pwsend,ixS^L)

integer, intent(in) :: ixR^L, ixS^L
type(walloc) :: pwrecv, pwsend

integer :: iw, iB
!-----------------------------------------------------------------------------
select case (ipole)
{case (^D)
   iside=int((i^D+3)/2)
   iB=2*(^D-1)+iside
   do iw=nwstart+1,nwstart+nwbc
      select case (typeB(iw,iB))
      case ("symm")
         pwrecv%w(ixR^S,iw) = pwsend%w(ixSmax^D:ixSmin^D:-1^D%ixS^S,iw)
      case ("asymm")
         pwrecv%w(ixR^S,iw) =-pwsend%w(ixSmax^D:ixSmin^D:-1^D%ixS^S,iw)
      case default
         call mpistop("Boundary condition at pole should be symm or asymm")
      end select
   end do \}
end select

end subroutine pole_copy
!=============================================================================
subroutine fix_auxiliary

integer :: ix^L
!-----------------------------------------------------------------------------

!$OMP PARALLEL DO PRIVATE(igrid,i^D,ix^L)
do iigrid=1,igridstail; igrid=igrids(iigrid);
      saveigrid=igrid
      
   {do i^DB=-1,1\}
      if (i^D==0|.and.) cycle

      ix^L=ixR_srl_^L(i^D);
      if(.not.slab)mygeo=>pgeoFi(igrid)
      call getaux(.true.,pwuse(igrid)%w,px(igrid)%x,ixG^L,ix^L,"bc")
   {end do\}
end do
!$OMP END PARALLEL DO

end subroutine fix_auxiliary
!=============================================================================
! end of internal procedures
!=============================================================================
end subroutine getbc
!=============================================================================
subroutine physbound(i^D,igrid,isphysbound)
use mod_forest
include 'amrvacdef.f'

integer, intent(in)  :: i^D, igrid
logical, intent(out) :: isphysbound
type(tree_node_ptr)  :: tree
integer              :: level, ig^D, ign^D
!-----------------------------------------------------------------------------
isphysbound = .false.

tree%node => igrid_to_node(igrid,mype)%node
level = tree%node%level
{ig^D = tree%node%ig^D; }

{ign^D = ig^D + i^D; }
if ({ign^D .gt. ng^D(level) .or. ign^D .lt. 1|.or.}) isphysbound = .true.

end subroutine physbound
!=============================================================================
