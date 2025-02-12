function [Fx,Fy,Currtot] = InternalCurrent(filename,electron)

%function [Fx,Fy] = InternalCurrent(filename,electron)
% Calculates the internal Lorentz force from SCEPTIC's output for ion
% collection, entirely balanced by electron collection.
%   filename: SCEPTIC3D output file
%   electron: 1: Assumes isotropic collection
%             2: Assumes 1D collection along the field lines
%             3: Assumes a delta function collection at x=-1
%             4: Uses the correct strongly mag expression (formula from my
%                thesis)
%             5: Idem 4, but using the formula from my last SCEPTIC3D Paper
%                (Ian's idea)
%   Fx,Fy:    Forces in unit of N_\infty R_p^2 T_e. electron=2 and 3 should
%             give the same answer, except for roundoff errors.
%   Currtot:  Total ion current normalized to N_\infty c_s0


% Read output file
short=true;
readoutput();

clear cang Curr fluxofangle cang2 Curr2 fluxofangle2

% Set angle arrays, because the option "short" does not read them.
for j=1:nthused
    tcc(j)=1-2*double(j-1)/double(nthused-1);
end
for i=1:npsiused
    pcc(i)=0.+double(i-1)*2*pi/double(npsiused);
end

% Cosine of interpolation angle along the three axis. angsize is the size of cang. Better if odd
angsize=min(npsiused,nthused);
if(mod(angsize,2)==0)
    angsize=angsize-1;
end




for j=1:angsize
    cang(j)=1-2*double(j-1)/double(angsize-1);
end


fluxofangle=zeros(3,angsize);
aweight=zeros(3,angsize);


%Test1. This should give a force 4/3*pi r_p^3, since the internal current is
%homogeneous
%for j=1:nthused
%    for k=1:npsiused
%        nincell(j,k)=(4*pi)/double(npsiused*(nthused-1)) *sqrt(1-tcc(j)^2)*sin(pcc(k));
%        if(or(j==1,j==nthused))
%            nincell(j,k)=0.5*nincell(j,k);
%        end
%    end
%end

%Test2. Isotropic ion collection
%for j=1:nthused
%    for k=1:npsiused
%        nincell(j,k)=(4*pi)/double(npsiused*(nthused-1));
%        if(or(j==1,j==nthused))
%            nincell(j,k)=0.5*nincell(j,k);
%        end
%    end
%end


% Backward interpolation theta/psi->cang
for j=1:nthused
    for k=1:npsiused
        
        cangle(1)=sqrt(1-tcc(j)^2)*cos(pcc(k));  % x
        cangle(2)=sqrt(1-tcc(j)^2)*sin(pcc(k));  % y
        cangle(3)=tcc(j);                        % z
        
        for i=1:3
            for ialt=2:angsize
                if(cang(ialt)<=cangle(i))
                    ialt=ialt-1;
                    break
                end
            end
            ial(i)=ialt;
        end
        
        for i=1:3
            if(ial(i)<angsize)
                af(i)=(cangle(i)-cang(ial(i)))/(cang(ial(i)+1)-cang(ial(i)));
            else
                af(i)=1;ial(i)=angsize-1;
            end
        end
        
        for i=1:3
            fluxofangle(i,ial(i))=fluxofangle(i,ial(i))+nincell(j,k)*(1-af(i));
            fluxofangle(i,ial(i)+1)=fluxofangle(i,ial(i)+1)+nincell(j,k)*af(i);     
            aweight(i,ial(i))=aweight(i,ial(i))+(1-af(i));
            aweight(i,ial(i)+1)=aweight(i,ial(i)+1)+af(i);
            if(or(j==1,j==nthused))
                aweight(i,ial(i))=aweight(i,ial(i))-0.5*(1-af(i));
                aweight(i,ial(i)+1)=aweight(i,ial(i)+1)-0.5*af(i);
            end  
        end

        
    end
end


% Average ion flux to the sphere at position cang
fluxofangle=fluxofangle.*double(npsiused*(nthused-1))./(aweight+1e-5)/(4*pi*rhoinf*dt*double(nastep));
%If test, uncomment
%fluxofangle=fluxofangle.*double(npsiused*(nthused-1))./(aweight+1e-5)/(4*pi);


% Total ion current to be balanced by the electrons. Because of the
% interpolation, Currtot is slightly different depending on the axis.
Currtot1=-2*pi*trapz(cang,fluxofangle(1,:));
Currtot2=-2*pi*trapz(cang,fluxofangle(2,:));
Currtot3=-2*pi*trapz(cang,fluxofangle(3,:));
% Make sure Currtot/(4*pi*flux0) is equal to fluxtot
flux0=sqrt(2*Ti)/(2*sqrt(pi));
fluxtot=sum(sum(nincell))/(4*pi*rhoinf*dt*double(nastep))/flux0;
Currtot=4*pi*flux0*fluxtot;


% Refine cang to get better trapz integration
angsize2=201;
for j=1:angsize2
    cang2(j)=1-2*double(j-1)/double(angsize2-1);
end
for i=1:3
    fluxofangle2(i,:)=interp1(cang,fluxofangle(i,:),cang2,'pchip');
end
cang=cang2;
fluxofangle=fluxofangle2;
angsize=angsize2;

% Need a double, otherwise Matlab is not happy
angsize=double(angsize);

% Internal ion current as a function of cang, before balancing it with the electron current. This only works if cang is symmetric with respect to 0
for i=1:3
    Curr(i,:)=2*pi*cumtrapz(cang,fluxofangle(i,:));
end
CurrE=zeros(size(Curr,1),size(Curr,2));

%Electron term balancing the ion internal current
if(electron==1)
    % The external circuit providing electrons is located at z=0, y=0 and say
    % x=-1
    CurrE(1,end)=2*  2*pi*Currtot1/(cang(2)-cang(3))/(2*pi);
    CurrE(2,ceil(angsize/2))=2*pi*Currtot2/(cang(2)-cang(3))/(2*pi);
    CurrE(3,ceil(angsize/2))=2*pi*Currtot3/(cang(2)-cang(3))/(2*pi);
    
    for i=1:3
        Curr(i,:)=Curr(i,:)-cumtrapz(cang,CurrE(i,:));
    end
    
elseif(electron==2)
    % We have a dust particle. Let's say isotropic electron collection
    
    % Remove the same everywhere
    CurrE(1,:)=2*pi*Currtot1/(cang(2)-cang(3))/(angsize-1)/(2*pi);
    CurrE(2,:)=2*pi*Currtot2/(cang(2)-cang(3))/(angsize-1)/(2*pi);
    CurrE(3,:)=2*pi*Currtot3/(cang(2)-cang(3))/(angsize-1)/(2*pi);
    
    for i=1:3
        Curr(i,:)=Curr(i,:)-cumtrapz(cang,CurrE(i,:));
    end
    
elseif(electron==3)
    % We have a dust particle. Let's say strongly magnetized electron collection
    
    % Remove depending on 1- x and y slices
    CurrE(1,:)=2*  4*Currtot1/(cang(2)-cang(3))/(angsize-1).*sqrt(1-cang.^2)/(2*pi);
    CurrE(2,:)=2*  4*Currtot2/(cang(2)-cang(3))/(angsize-1).*sqrt(1-cang.^2)/(2*pi);
    
    % Remove depending on abs(cos\theta) on the z slice
    CurrE(3,:)=2*  4*Currtot3/(cang(2)-cang(3))/(angsize-1).*abs(cang)/(2*pi);
    
    for i=1:3
        Curr(i,:)=Curr(i,:)-cumtrapz(cang,CurrE(i,:));
    end
    
elseif(electron==4)
    % Try to account for the strongly magnetized electron expression
    efac=Bz*vd*sqrt(1-c_d^2)+1e-8;
    
    CurrE(1,:)=2*exp(-cang*efac)/(2*besseli(1,efac)/efac)   *4*Currtot1/(cang(2)-cang(3))/(angsize-1).*sqrt(1-cang.^2)/(2*pi);
    
    alpha=linspace(0,2*pi,500);
    s=size(alpha,2);
    for k=1:size(alpha,2);
        CurrE(2,:)=CurrE(2,:)+ ...
                    2*abs(sin(alpha(k)))*exp(sqrt(1-cang.^2)*cos(alpha(k))*efac)/(2*besseli(1,efac)/efac)*(2*pi)/s ...
                    *Currtot2/(cang(2)-cang(3))/(angsize-1).*sqrt(1-cang.^2)/(2*pi);
    end
    
    % Remove depending on abs(cos\theta) on the z slice
    CurrE(3,:)=2*  Currtot3/(cang(2)-cang(3))/(angsize-1).*abs(cang)/(2*pi);
    
    for i=1:3
        Curr(i,:)=Curr(i,:)-cumtrapz(cang,CurrE(i,:));
    end
end
    

% Internal Lorentz force in units of N_\infty R_p^2 T_e
if(electron<=4)
    Fx=trapz(-cang,Curr(2,:))*Bz;
    Fy=-trapz(-cang,Curr(1,:))*Bz;
    Fz=0;
else
    mefac=-Bz*vd*sqrt(1-c_d^2)-1e-8;
    Fx=-Bz*trapz(-cang2,2*pi*cang2.*fluxofangle2(2,:));
    Fy=Bz*(trapz(-cang2,2*pi*cang2.*fluxofangle2(1,:)) ...
           -Currtot*(besseli(0,mefac)/besseli(1,mefac)-2/mefac));
    Fz=0;
end

end
