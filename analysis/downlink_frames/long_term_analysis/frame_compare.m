function R=frame_compare(A,B,blockStart,runBounds,deltaIntercept,deltaSlope,C)
% tVillage = (1+slope)*tCity + intercept. Byte equality includes all bytes
% exported by decoder, excluding HDLC FCS. Frame occurrences are not deduped.
for k=1:numel(B)
 B(k).start_lo_s=(B(k).start_lo_s-deltaIntercept)/(1+deltaSlope);
 B(k).start_hi_s=(B(k).start_hi_s-deltaIntercept)/(1+deltaSlope);
 B(k).end_hi_s=(B(k).end_hi_s-deltaIntercept)/(1+deltaSlope);
end
% Both stations use the same conservative start interval. Context frames
% outside a safe second do not enter numerator or denominator.
keepA=owned(A,blockStart,runBounds,C);
keepB=owned(B,blockStart,runBounds,C);
usedA=false(numel(A),1); usedB=false(numel(B),1); pairs=zeros(0,2);
ambiguous=0;
keys=intersect(string({A.key}),string({B.key}));
for key=keys(:).'
 ia=find(string({A.key})==key); ib=find(string({B.key})==key);
 [~,o]=sort([A(ia).start_lo_s]); ia=ia(o);
 [~,o]=sort([B(ib).start_lo_s]); ib=ib(o);
 % Monotone maximum matching for ordered, near-uniform time intervals.
 % Gate compares intervals, not nominal PCAP timestamps.
 i=1; j=1;
 while i<=numel(ia) && j<=numel(ib)
  a=A(ia(i)); b=B(ib(j));
  if a.start_hi_s+C.matchToleranceS<b.start_lo_s, i=i+1; continue; end
  if b.start_hi_s+C.matchToleranceS<a.start_lo_s, j=j+1; continue; end
  if j<numel(ib)
   nxt=B(ib(j+1));
   ambiguous=ambiguous+(nxt.start_lo_s<=a.start_hi_s+C.matchToleranceS);
  end
  assert(isequal(a.bytes,b.bytes),'Key collision or byte mismatch.');
  usedA(ia(i))=true; usedB(ib(j))=true;
  pairs(end+1,:)=[ia(i) ib(j)]; %#ok<AGROW>
  i=i+1; j=j+1;
 end
end
% Match context first: a counterpart on an uncertain boundary must never
% be reported as absent. Quarantine such a pair from both stations.
validPair=false(size(pairs,1),1);
for k=1:size(pairs,1)
 i=pairs(k,1); j=pairs(k,2); validPair(k)=keepA(i) && keepB(j);
 if ~validPair(k), keepA(i)=false; keepB(j)=false; end
end
pairs=pairs(validPair,:);
exA=sum(~keepA); exB=sum(~keepB);
cityOnly=find(keepA(:) & ~usedA); villageOnly=find(keepB(:) & ~usedB);
nv=sum(keepB); nc=size(pairs,1); ratio=NaN;
if nv>0, ratio=nc/nv; end
R=struct('city_total',sum(keepA),'village_total',nv,'common',nc, ...
 'city_only',numel(cityOnly),'village_only',numel(villageOnly),'common_over_village',ratio, ...
 'excluded_city',exA,'excluded_village',exB, ...
 'ambiguous_repeated_matches',ambiguous,'pairs',pairs, ...
 'city_frames',A,'village_frames',B,'counted_city_mask',keepA, ...
 'counted_village_mask',keepB,'city_only_indices',cityOnly,'village_only_indices',villageOnly);
assert(R.common+R.city_only==R.city_total && ...
 R.common+R.village_only==R.village_total,'Count conservation failed.');
end
function keep=owned(F,t,bounds,C)
keep=false(size(F));
for k=1:numel(F)
 % Start must be confidently inside second, with an additional guard.
 % Full closing flag must lie in the accepted stable run.
 keep(k)=F(k).start_lo_s>=t+C.boundaryGuardS && ...
  F(k).start_hi_s<t+1-C.boundaryGuardS && ...
  F(k).start_lo_s>=bounds(1)+C.decodeStartupGuardS && ...
  F(k).end_hi_s<bounds(2)-C.decodeTailGuardS;
end

end
