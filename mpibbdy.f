
c***********************************************************************
c Block boundary communication.
      subroutine bbdy(cg_comm,iLs,iuds,u,kc,iorig, ndims,idims,lperiod
     $     ,icoords,iLcoords,myside,myorig, myorig1,myorig2,myorig3
     $     ,icommcart,mycartid,myid,lflag,out,inn)

      integer cg_comm
c Dimensional structure of u, for 2d should be (1,Li,Li*Lj), 
c 3d (1,Li,Li*Lj,Li*Lj*Lk) etc (last element may not be used)
      integer iLs(ndims+1)
c iuds used dimensions of u
      integer iuds(ndims)
c Inside this routine, u and iorig are referenced linearly.
      real u(*)
c kc      is iteration count which also determines the end of the solver
      integer kc
c iorig(idims(1)+1,idims(2)+1,...) (IN) is a pointer to the
c origin of block(i,j,..) within u.
c Blocks must be of equal size except for the uppermost
c The top of uppermost, with iblock=idims(n)) is indicated
c by a value pointing to 1 minus the used length of u in that dimension.
      integer iorig(*)
c The number of dimensions of the cartesian topology. (2 for 2d) (IN)
      integer ndims
c The length of each topology dimension (number of blocks) (IN)
      integer idims(ndims)
c For each topology dimension whether it is periodic or not (IN)
      logical lperiod(ndims)
c Cartesian topology coords of this process block (OUT)
      integer icoords(ndims)
c structure of icoords (1,(idims(1)+1),(idims(1)+1)*(idims(2)+1),...)
      integer iLcoords(ndims+1)
c My side length data, accounting for my position in the topology (OUT).
      integer myside(ndims)
c icommcart is the id of the cartesian topology communicator (OUT).
      integer icommcart
c mycartid is the process id in cartesian topology communicator (OUT).
      integer mycartid
c myid returns the process id in the sor_comm (OUT)
      integer myid
c Am I on the outer or inner part of the domain (Need BC)
      logical out,inn
c End of arguments.
c---------------------------------------------------------------
c The first time, set up the cartesian topology and return info 
c to calling process.
c Subsequently, do the boundary communication.
c---------------------------------------------------------------
c Start of local variables.
      logical lalltoall
      parameter (idebug=0,lalltoall=.false.)
c Local storage:
      logical lreorder
c vector type ids for each dimension (maximum 10 dimensions)
      parameter(imds=10)
c facevector ids for each dimension; bulk, top. 
c These are the handles to datatype that picks out data in the correct
c pattern, based on the u-address provided to the MPI call.
      integer iface(imds,2)
c Integer indication of whether we are bulk (1), top (2), or inner (3)
      integer ibt(imds)
c stack pointers and lengths iall(imds) points to the place in the 
c stack is where the vector starts. lall is the vector length.
      integer iall(imds),lall(imds)
c shift source and destination ids for each dimension left and right
      integer isdl(imds),iddl(imds),isdr(imds),iddr(imds)
c Right and left u-origins of each dimension for this block.
c      integer iobr(imds),iobl(imds)
c iside(imds,2) holds the side length of blocks in u for each dimension.
c iside(*,1) is the general value, iside(*,2) the uppermost value.
      integer iside(imds,2)
c irdims is the block count per dimension array with the order of the
c dimensions reversed to maintian fortran compatibility. 
c Ditto ircoords, lrperiod
      integer irdims(imds),ircoords(imds)
      logical lrperiod(imds)
c Scratch stack, whose length must be at least Prod_1^nd(iside(i,2)+1)
c Possibly this should be passed to the routine. 
      parameter (istacksize=100000)
      integer is(istacksize)
      integer ktype(2**imds)
c Arrays for constructing ALLtoALL calls.
      parameter (maxprocs=1000)
      integer isdispls(maxprocs),irdispls(maxprocs)
      integer istypes(maxprocs),irtypes(maxprocs)
      integer iscounts(maxprocs),ircounts(maxprocs)
      integer iconp(imds)
c      character*40 string
c Debugging arrays
c      parameter (ndebug=1000)
c      integer iaints(ndebug),iaadds(ndebug),iadats(ndebug)
c      integer isc(ndebug),isd(ndebug),ist(ndebug)
c      integer irc(ndebug),ird(ndebug),irt(ndebug)


      include 'mpif.h'
      integer status(MPI_STATUS_SIZE)
c Flag that we have called this routine once. Can't use multiple
c instances in one program. No way to reset this. Might include as
c an argument to allow us to reset. Not done yet.
      logical lflag
c      data lflag/.false./
      save

      if(.not.lflag)then

c -----------------------------------------------------------------
c First time. Set up topology and calculate comm-types
c------------------------------------------------------------------
c Check roughly if the istacksize and imds are enough.
         if(2.*iLs(ndims).ge.istacksize) then
            write(*,*) 'Stack size',istacksize,
     $           ' possibly too small for arrays',iLs(ndims)
            write(*,*) 'Danger of overrun.'
            goto 999
         endif
         if(ndims.gt.imds)then
            write(*,*)'MPI too many dimensions error',ndims
            goto 999
         endif
c End of safety checks
         nproc=1
         iLcoords(1)=1
         do n=1,ndims
c Populate the block structure vector 
            if(n.gt.1) iLcoords(n)=iLcoords(n-1)*(idims(n-1)+1)
c Count the processes needed for this topology
            nproc=nproc*idims(n)
         enddo


         if(nproc.gt.maxprocs) then
            write(*,*)'Too many processes',nproc,' Increase maxprocs.'
            goto 999
         endif
c         write(*,*)'iLcoords',iLcoords
c Output some diagnostic data, perhaps.
         if(idebug.gt.0) call bbdyorigprint(ndims,idims,iorig)
         
         do n=1,ndims
c Calculate the block side lengths from the origins data.
            iside(n,1)=(iorig(1+iLcoords(n))-iorig(1))/iLs(n)+2
            kt=(1+(idims(n))*iLcoords(n))
            kn=(1+(idims(n)-1)*iLcoords(n))
            iside(n,2)=(iorig(kt)-iorig(kn))/iLs(n)+2
         enddo

c         write(*,*) (iorig(ii),ii=1,100)
c         write(*,*) (iLs(ii),ii=1,3)
c         write(*,*) (iLcoords(ii),ii=1,3)
c         write(*,*)'((iside(ii,jj),jj=1,2),ii=1,ndims)='
c         write(*,'(2i10)')((iside(ii,jj),jj=1,2),ii=1,ndims)

c Initialize
         lflag=.true.
         call MPI_COMM_RANK(cg_comm, myid, ierr )
         call MPI_COMM_SIZE(cg_comm, numprocs, ierr )
         
c This could be relaxed if I check for return of MPI_COMM_NULL
c after CART_CREATE
         if(nproc.ne.numprocs)then
c            if(myid.eq.0)
                write(*,*)'MPI setup error: incorrect process count ',
     $           numprocs,
     $           ' for this topology ',(idims(n),n=1,ndims),' =',nproc
            goto 999
         endif
c Reverse the order of the dimensions in the calls to MPI_CART
c to compensate for the C-ordering in those.
         do n=1,ndims
            irdims(n)=idims(ndims-n+1)
            lrperiod(n)=lperiod(ndims-n+1)
c            irdims(n)=idims(n)
c            lrperiod(n)=lperiod(n)
         enddo
c Create topology
         lreorder=.true.

         call MPI_CART_CREATE(cg_comm,ndims,irdims,lrperiod,
     $        lreorder,icommcart,ierr)
         call MPI_COMM_RANK(icommcart,mycartid, ierr )
c         write(*,*)'returned from create',ndims,idims,lperiod,ierr,
c     $        icommcart
c Determine my block cartesian coords, and hence start of my data.
c icoords are zero-origin not one-origin.
c Although we know idims,lperiod already, we want icoords.
c         call MPI_CART_GET(icommcart,ndims,irdims,lrperiod,
c     $        ircoords,ierr)
         call MPI_CART_COORDS(icommcart,mycartid,ndims,ircoords,ierr)
c     Reverse the order of the dimensions in the calls to MPI_CART
         do n=1,ndims
c     icoords(n)=ircoords(n)
            icoords(n)=ircoords(ndims-n+1)
         enddo

         do n=1,ndims
            ibt(n)=1
            if(icoords(n).eq.idims(n)-1) ibt(n)=2
c     Get my block side lengths, now knowing my cluster position.
            myside(n)=iside(n,ibt(n))
         enddo

c     Determine if the current block is at the inner or/and outer boundary
c     of the domain

         if (ibt(1).eq.2) then
            out=.true.
         else
            out=.false.
         endif
         if(icoords(1).eq.0) then
            inn=.true.
         else
            inn=.false.
         endif

         if(idebug.gt.0)then
            write(*,*)'u used dimensions',(iuds(k),k=1,ndims)
            write(*,*)'Blocks in each dim',(idims(k),k=1,ndims)
            write(*,*)'Rank=',myid,' icoords=',(icoords(k),k=1,ndims)
            write(*,*)'Block myside lengths',(myside(k),k=1,ndims)
            if(idebug.ge.2)then
               write(*,*)'u dim-structure',(iLs(k),k=1,3)
               write(*,*)'iLcoords=',iLcoords
            endif
         endif
        
c For all dimensions create vector types for communications.
c nn is the normal direction.

         do nn=1,ndims
c Reuse the stack (drop previous data).
            ibeg=1
c Create the face vector indexes iall(id), id=ndims.
c In iall(1,...,ndims-1) are the subface indices 0...ndims-2,
c which however are not used externally.

c nn is the normal direction
            call bbdyfacecreate(nn,ndims,ibeg,is,iLs,myside,
     $           iall,lall,id)

            if(idebug.gt.1)then
            write(*,*)'Face indices, direction nn=',nn,', block-dims'
     $           ,(myside(mod(k+nn-1,ndims)+1),k=1,2)
     $           ,' (group(1)= block-dim(1)/2)'
            write(*,*)'nn,id,iall(id),lall(id)',
     $           nn,id,iall(id),lall(id)
            write(*,*)' is(iall (',nn,'))'
     $           ,(is(iall(id)+ii),ii=0,lall(id)-1)
         endif
c     Make a buffer of the correct length telling data lengths (1 each)
c     in scratch stack.
            iblens=ibeg
            do i=1,lall(id)
               is(ibeg)=1
               ibeg=ibeg+1
            enddo


c     Create the new data types. With cg no odd and even separation. Do
c     all at once with lall and iall
            call MPI_TYPE_INDEXED(lall(id),is(iblens),is(iall(id)),
     $           MPI_REAL,iface(nn,ibt(nn)),ierr)
            call MPI_TYPE_COMMIT(iface(nn,ibt(nn)),ierr)
         enddo

         iobindex=1
         ioffset=0
         do n=1,ndims
c Calculate my block origin index which is 
c   (1+icoords(1)*iLcoords(1)+icoords(2)*iLcoords(2),...)
            iobindex=iobindex+icoords(n)*iLcoords(n)
            ioffset=ioffset+iLs(n)
c Determine Shift ids.
c C-order shifts abandoned.
c            call MPI_CART_SHIFT(icommcart,n-1,1,isdr(n),iddr(n),ierr)
c            call MPI_CART_SHIFT(icommcart,n-1,-1,isdl(n),iddl(n),ierr)
c Shifts compensating for the dimension order reversal.
            call MPI_CART_SHIFT(icommcart,ndims-n,1,
     $           isdr(n),iddr(n),ierr)
            call MPI_CART_SHIFT(icommcart,ndims-n,-1,
     $           isdl(n),iddl(n),ierr)
         enddo
         myorig=iorig(iobindex)
c         myorig1=iorig(icoords(1)+1)
         myorig1=icoords(1)*(iside(1,1)-2)+1
         myorig2=icoords(2)*(iside(2,1)-2)
         myorig3=icoords(3)*(iside(3,1)-2)
c--------------------------------------------------------------------
c Create the types for block gathering.
c         write(*,*)'calling bbdyblockcreate'
         call bbdyblockcreate( ndims,ktype,iLs,iside,isizeofreal)
         ith0=2**ndims
         if(idebug.ge.1) write(*,*)'Block types:',(ktype(ith),
     $        ith=ith0,2*ith0-1)
c Create the required arrays for the ALLTOALL
         call bbdycoords(mycartid+1,ndims,idims,iconp,ithi,
     $        iLcoords,ionp)
         do np=1,nproc
c Here we need to send only the active length of data, so the origin
c is offset.
            isdispls(np)=(iorig(iobindex)-1+ioffset)*isizeofreal
            istypes(np)=ktype(ith0+ithi)
            call bbdycoords(np,ndims,idims,iconp,ithj,
     $           iLcoords,ionp)
            irdispls(np)=(iorig(ionp)-1+ioffset)*isizeofreal
            irtypes(np)=ktype(ith0+ithj)

            if(lalltoall) then
c All to all
               if(np.eq.mycartid+1)then
c Don't send to or receive from myself.
                  iscounts(np)=0
                  ircounts(np)=0
               else
                  iscounts(np)=1
                  ircounts(np)=1
               endif
            else
c Gather to process 0 (fortran index 1)
               if(np.eq.1.and.mycartid+1.ne.np)then
                  iscounts(np)=1
               else
                  iscounts(np)=0
               endif
               if(mycartid.eq.0.and.mycartid+1.ne.np)then
                  ircounts(np)=1
               else
                  ircounts(np)=0
               endif
            endif
         enddo
c Don't send to or receive from anyone test.
c Process 1 sends to process 0 test
c         if(mycartid.eq.0) ircounts(2)=1
c         if(mycartid.eq.1) iscounts(1)=1
c Process 2 sends to process 0 test
c         if(mycartid.eq.0) ircounts(3)=1
c         if(mycartid.eq.2) iscounts(1)=1


c         write(*,*)'     np,sendcts,senddp,sendtp,recvcts,recvdp,recvtp'
c         write(*,'(7i8)')(np,iscounts(np),isdispls(np)/4,
c     $        mod(istypes(np),10000),
c     $        ircounts(np),irdispls(np)/4,
c     $        mod(irtypes(np),10000),np=1,nproc)
c--------------------------------------------------------------------
         if(idebug.ge.2) write(*,*)'End of initialization'
c         return

      endif
c--------------------------------------------------------------------
c (First and) Subsequent calls. Do the actual communication
c--------------------------------------------------------------------
      if(kc.eq.-1)goto 100


      itag=100


c Origin of left face (the same for all dimensions)
      iolp=iorig(iobindex)
      do n=1,ndims
c         write(*,*)'iolp,n,ndims,iLcoords',iolp,n,ndims,iLcoords
c Origin of right face (i.e. of block to right)
         iorp=iorig(iobindex+iLcoords(n))
c      write(*,*)'iorp=',iorp
c iolp is for receiving +1 shift, iorp is for sending +1 shift.
         iolm=iolp+iLs(n)
         iorm=iorp+iLs(n)
c iorm is for receiving -1 shift, iolm is for sending -1 shift.
         if(idebug.ge.2)then
         if(n.eq.1) write(*,*)' n,iolp,iorp,iolm,iorm,',
     $        'iddr,isdr,iddl(n),isdl(n)'
         write(*,'(3i3,8i5)') n,ko,ke,iolp,iorp,iolm,iorm,
     $        iddr(n),isdr(n),iddl(n),isdl(n)
         endif

c Send data to right, receive data from left
c Sendrcv should be faster, maybe

         if((iddr(n).ne.-1).and.(isdr(n).ne.-1)) then
            call MPI_SENDRECV(u(iorp),1,iface(n,ibt(n)),
     $        iddr(n),itag,u(iolp),1,iface(n,ibt(n)),
     $        isdr(n),itag,icommcart,status,ierr)
         else
            if(iddr(n).ne.-1) call MPI_SEND(u(iorp),1,iface(n,ibt(n)),
     $           iddr(n),itag,icommcart,ierr)
            if(isdr(n).ne.-1) call MPI_RECV(u(iolp),1,iface(n,ibt(n)),
     $           isdr(n),itag,icommcart,status,ierr)
         endif

c Send data to left, receive  from right
c shift in the direction left (-1).
         if((iddl(n).ne.-1).and.(isdl(n).ne.-1)) then
            call MPI_SENDRECV(u(iolm),1,iface(n,ibt(n)),
     $        iddl(n),itag,u(iorm),1,iface(n,ibt(n)),
     $        isdl(n),itag,icommcart,status,ierr)
         else
            if(iddl(n).ne.-1) call MPI_SEND(u(iolm),1,iface(n,ibt(n)),
     $           iddl(n),itag,icommcart,ierr)
            if(isdl(n).ne.-1) call MPI_RECV(u(iorm),1,iface(n,ibt(n)),
     $           isdl(n),itag,icommcart,status,ierr)
         endif



      enddo

      return
c------------------------------------------------------------------
c Special cases determined by the value of kc.
 100  continue
c kc=-1. Do the block exchanging.
c Debugging test.
c      do np=1,nproc
c         istypes(np)=MPI_REAL
c         irtypes(np)=MPI_REAL
c      enddo
      if(idebug.ge.1)then
         write(*,*)'     np,sendcts,senddp,sendtp,recvcts,recvdp,recvtp'
         write(*,'(7i8)')(np,iscounts(np),isdispls(np)/4,
     $        mod(istypes(np),10000),
     $        ircounts(np),irdispls(np)/4,
     $        mod(irtypes(np),10000),
     $        np=1,nproc)

      endif
      call MPI_ALLTOALLW(u,iscounts,isdispls,istypes,
     $     u,ircounts,irdispls,irtypes,
     $     icommcart,ierr)
      return

c Exception stop:
 999  call MPI_FINALIZE()
      stop

      end

c*****************************************************************
c Concatenate data from istart with length ilen into is at ibeg,
c with iinc added to it.
      subroutine bbdycatstep(is,ibeg,istart,ilen,iinc)
      integer is(*)
      do j=1,ilen
         is(ibeg)=is(istart-1+j)+iinc
         ibeg=ibeg+1
      enddo
      end
c****************************************************************
      subroutine bbdyfacecreate(nn,nd,ibeg,is,iLs,myside,
     $     iall,lall,id)
c nn: normal dimension, nd: total dimensions.
      integer nn,nd,id
c ibeg: stack counter, is: stack array, iLs: u-structure,
c myside: block length in dimension n.
      integer ibeg,is(*),iLs(nd+1),myside(nd)
c iall: returns the vector representing the face indices of is
      integer iall(nd),lall(nd)

c      write(*,*)'Bbdyfacecreate: nn,nd,ibeg,myside',nn,nd,ibeg,myside
c      write(*,*) iLs
c Create vectors that get elements from face normal to nn.
c Iterate over all the dimensions

c Zeroth dimension addresses and lengths: 
      iall(1)=ibeg
      is(ibeg)=0
      lall(1)=1
      ibeg=ibeg+1
      id=1
c If ndims>1 iterate to the higher face dimension.
      do  nc=nn,nn+nd-2
c     The actual dimension number: n
         n=mod(nc,nd)+1
c     Count of the dimension id starting at two.
         id=nc-nn+2

         iall(id)=ibeg
         iinc=0
         do i=1,myside(n)
c     write(*,*)'iinc=',iinc,iainc
c     create array is with the face index
            call bbdycatstep(is,ibeg,iall(id-1),lall(id-1),iinc)
            iinc=iinc+iLs(n)
         enddo
         lall(id)=ibeg-iall(id)

      enddo
      end

c****************************************************************
      subroutine bbdyorigprint(ndims,idims,iorig)
      integer ndims
      integer idims(ndims),iorig(*)
      integer kk(3)
      character*40 string
c This diagnostic works only for up to 3-d arrays.
c Ought to become a subroutine.
         if(ndims.le.3) then
            do j=3,1,-1
               if(ndims.lt.j)then 
                  kk(j)=1
               else
                  kk(j)=idims(j)+1
               endif
            enddo
            write(*,*)'j,k,Block origins(i)='
            write(string,'(''('',i4''i8)'')')kk(1)+2
            write(*,string)
     $           ((j,k,(iorig(i+kk(1)*((j-1)+kk(2)*(k-1))),
     $           i=1,kk(1)),j=1,kk(2)),k=1,kk(3))
         endif

         end
c*******************************************************************
c Return the block origins for a multidimensional block arrangement.
      subroutine bbdydefine(ndims,idims,ifull,iuds,iorig,iLs)
c ndims: number of dimensions, 
c idims(ndims) number of blocks in each dimension, 
c ifull(ndims) full lengths of declared array in each dimension. 
c iuds(ndims) used lengths in each dimension
c iorig: return block origin displacements. (OUT)
c iLs(ndims+1) full-length step structure of declared array (OUT)
      integer ndims,idims(ndims),ifull(ndims),iuds(ndims)
      integer iLs(ndims+1)
c Presumed effective dimensions of iorig are 
c    (idims(1)+1,idims(2)+1,...)
      integer iorig(*)
      character*20 string
c Define the block origin addresses
      iorig(1)=1
      ibeg=2
      ifn=1
      iLs(1)=1
      do n=1,ndims
         isz=2+(iuds(n)-2)/idims(n)
         if(mod(isz,2).eq.1)isz=isz-1
         istep=(isz-2)*ifn
         ilen=ibeg-1
         do i=1,idims(n)
            if(i.eq.idims(n))then
               iinc=(iuds(n)-2)*ifn
            else
               iinc=i*istep
            endif
c            write(*,*)'iinc,ifn,istep,isz=',iinc,ifn,istep,isz
            call bbdycatstep(iorig,ibeg,1,ilen,iinc)
         enddo
         ifn=ifull(n)*ifn
         iLs(n+1)=ifn
      enddo
c      write(*,*)'iorig='
      write(string,'(''('',i5,''i8)'')')(idims(1)+1)
c      write(*,string)(iorig(jj),jj=1,ibeg-1)
      end
c********************************************************************
      subroutine bbdyblockcreate(ndims,ktype,iLs,iside,iSIZEOFREAL)
      
      parameter(imds=10)
      integer iLs(ndims+1)
c iside(*,1) is the general value, iside(*,2) the uppermost value.
      integer iside(imds,2)
      
c ktype stores the type handles in the order
c 0-d; 1d bulk, 1d top; 2d bulk (1b,1t), 2d top (1b,1t), ...
c So for the nn-th level the start of the types is at 2**nn.

      integer ktype(*)
      include 'mpif.h'

      call MPI_TYPE_SIZE(MPI_REAL,iSIZEOFREAL,ierr)
c zeroth dimension type is MPI_REAL
      ktype(1)=MPI_REAL
      inew=2
      do nn=1,ndims
         iprior=2**(nn-1)
c         write(*,*)'bbdyblockcreate: nn,iprior,inew,ktype(iprior)'
c     $        ,nn,iprior,inew,ktype(iprior)
c laminate to higher dimension
         call bbdyblam(ndims,ktype,inew,iprior,nn,iside,
     $        iLs,iSIZEOFREAL)
c         write(*,*)'nn,ithis,inew,ktype(ithis...)',
c     $        nn,2**nn,inew,(ktype(ith),ith=(2**nn),2**(nn+1)-1)
      enddo
c The types we use now start at ktype(2**ndims), 2**ndims of them.
      end

c*********************************************************************
      subroutine bbdyblam(ndims,ktype,inew,iprior,nn,iside,
     $     iLs,iSIZEOFREAL)
      parameter(imds=10)
c iside(*,1) is the general value, iside(*,2) the uppermost value.
      integer iside(imds,2)
      integer iLs(ndims+1)
      integer ktype(*)
      include 'mpif.h'
      ilen=1
      istride=iLs(nn)*iSIZEOFREAL
c For the bulk and top cases of this dimension
      do ibt=1,2
c Because we do not count the boundaries, the count is 2 less than iside.
         icount=iside(nn,ibt)-2
c For all types in prior level, laminate enough together
c At each level there are 2**(nn-1) types in prior level
         do iold=iprior,iprior+2**(nn-1)-1
c            write(*,*)'iold,icount,istride,ktype(iold),inew',
c     $           iold,icount,istride,ktype(iold),inew
            call MPI_TYPE_HVECTOR(icount,ilen,istride,
     $           ktype(iold),ktype(inew),ierr)
c We only commit the top level that we are going to use.
            if(nn.eq.ndims)call MPI_TYPE_COMMIT(ktype(inew),ierr)
            inew=inew+1
         enddo
      enddo

      end
c*********************************************************************
      subroutine bbdycoords(nn,ndims,idims,icoords,ith,iLcoords,ionp)
c Obtain the cartesian coordinates of nn, in ndims dimensions, idims
c Return it in icoords. Return the type index (zero-based), i.e.
c whether we are in bulk on on boundary in ith.
c Also the iorig index, ionp, for this block.
      integer nn,ndims
      integer icoords(ndims),idims(ndims)
      integer ith
      integer iLcoords(ndims+1)
      in=nn-1
      ith=0
      ionp=1
      do nd=1,ndims
         iquot=in/idims(nd)
         icoords(nd)=in-iquot*idims(nd)
         if(icoords(nd)+1.eq.idims(nd)) ith=ith+2**(nd-1)
c         write(*,*)'nd,icoords(nd),in,iquot',nd,icoords(nd),in,iquot
         in=iquot
c Since iorig has dimensions 1+idims this is needed:
         ionp=ionp+icoords(nd)*iLcoords(nd)
      enddo
c      write(*,*)'nn,ith,ndims,idims',nn,ith,ndims,idims
      end
