function P=frame_reconcile(P)
% Merge CRC-valid observations across overlapping decode windows, within a
% stable run only. Stored village frame times are already on the city axis.
% Preserve physical repetitions: never merge two observations from one window.
if isfield(P,'reconciliation')
 assert(strcmp(P.reconciliation.version,'overlap_union_v1'),'Unknown reconciliation version.');
 return;
end
C=P.identity;
assert(isfield(C,'saveFrameBytes') && C.saveFrameBytes, ...
 'Frame:Reconcile','Reconciliation requires saved frame arrays (saveFrameBytes=true).');
P.window_counts_original={P.blocks.counts};
usable=find(string({P.blocks.status})=="analyzed");
assert(~isempty(usable),'Frame:Reconcile','No analyzed seconds to reconcile.');
runs=unique([P.blocks(usable).run]);
audit=struct('run',{},'city_pool',{},'village_pool',{}, ...
 'ambiguous_removed_city',{},'ambiguous_removed_village',{});
for r=runs(:).'
 ix=usable([P.blocks(usable).run]==r);
 A=mergePool(P.window_counts_original,ix,'city_frames');
 B=mergePool(P.window_counts_original,ix,'village_frames');
 [A,B,qa,qb]=quarantine(A,B,C);
 allRun=find([P.blocks.run]==r);
 bounds=[P.blocks(allRun(1)).second,P.blocks(allRun(end)).second+1];
 for j=ix(:).'
  t=P.blocks(j).second;
  % Include counterparts immediately outside ownership interval so a
  % boundary pair is quarantined jointly by frame_compare, not called lost.
  margin=C.matchToleranceS+C.boundaryGuardS+.005;
  AA=near(A,t,margin); BB=near(B,t,margin);
  P.blocks(j).counts=frame_compare(AA,BB,t,bounds,0,0,C);
 end
 audit(end+1)=struct('run',r,'city_pool',A,'village_pool',B, ...
  'ambiguous_removed_city',qa,'ambiguous_removed_village',qb); %#ok<AGROW>
end
P.reconciliation=struct('version','overlap_union_v1', ...
 'method','Exact bytes, intersecting start-time intervals, at most one observation per source window', ...
 'time_axis','City RAW seconds; village times already mapped by original per-window model', ...
 'runs',audit);
end
function F=mergePool(windows,ix,field)
F=windows{ix(1)}.(field); F=F([]);
byKey=containers.Map('KeyType','char','ValueType','any');
for w=ix(:).'
 G=windows{w}.(field);
 for k=1:numel(G)
  x=G(k); key=char(x.key);
  x.merge_windows=w; x.merge_indices=k;
  x.merge_intersection_lo_s=x.start_lo_s;
  x.merge_intersection_hi_s=x.start_hi_s;
  x.merge_ambiguous=false;
  ids=[]; if isKey(byKey,key), ids=byKey(key); end
  candidates=[];
  for q=ids(:).'
   if ~ismember(w,F(q).merge_windows) && ...
     x.start_lo_s<=F(q).merge_intersection_hi_s && ...
     x.start_hi_s>=F(q).merge_intersection_lo_s
    candidates(end+1)=q; %#ok<AGROW>
   end
  end
  if numel(candidates)==1
   q=candidates(1); assert(isequal(F(q).bytes,x.bytes),'Byte key mismatch.');
   F(q).merge_windows(end+1)=w; F(q).merge_indices(end+1)=k;
   F(q).merge_intersection_lo_s=max(F(q).merge_intersection_lo_s,x.start_lo_s);
   F(q).merge_intersection_hi_s=min(F(q).merge_intersection_hi_s,x.start_hi_s);
   % Keep the conservative outer bounds for second ownership.
   F(q).start_lo_s=min(F(q).start_lo_s,x.start_lo_s);
   F(q).start_hi_s=max(F(q).start_hi_s,x.start_hi_s);
   F(q).end_hi_s=max(F(q).end_hi_s,x.end_hi_s);
  else
   if numel(candidates)>1
    x.merge_ambiguous=true;
    for q=candidates(:).', F(q).merge_ambiguous=true; end
   end
   if isempty(F), F=x; else, F(end+1)=x; end %#ok<AGROW>
   byKey(key)=[ids numel(F)];
  end
 end
end
end
function [A,B,qa,qb]=quarantine(A,B,C)
keepA=true(size(A)); keepB=true(size(B));
% Ambiguous duplicate association is not interpreted as station loss.
for side=1:2
 if side==1, G=A; else, G=B; end
 for j=1:numel(G)
  if ~G(j).merge_ambiguous, continue; end
  x=G(j);
  for k=1:numel(A)
   if related(A(k),x,C.matchToleranceS), keepA(k)=false; end
  end
  for k=1:numel(B)
   if related(B(k),x,C.matchToleranceS), keepB(k)=false; end
  end
 end
end
qa=sum(~keepA); qb=sum(~keepB); A=A(keepA); B=B(keepB);
end
function yes=related(a,b,tolerance)
yes=strcmp(a.key,b.key) && a.start_hi_s+tolerance>=b.start_lo_s && ...
 b.start_hi_s+tolerance>=a.start_lo_s;
end
function G=near(F,t,margin)
if isempty(F), G=F; return; end
G=F([F.start_lo_s]<t+1+margin & [F.start_hi_s]>=t-margin);
end
