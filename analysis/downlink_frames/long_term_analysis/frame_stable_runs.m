function B=frame_stable_runs(B,C)
% Classify a COPY of synchronization results, also usable while scanning.
run=0;
for j=1:numel(B)
 if B(j).status~="locally_stable", continue; end
 linked=false;
 if j>1 && B(j-1).status=="locally_stable" && B(j).second==B(j-1).second+1
  t=B(j).second;
  linked=abs(delay(B(j).model,t)-delay(B(j-1).model,t))<=C.neighborToleranceS;
 end
 if ~linked, run=run+1; end
 B(j).run=run;
end
for r=1:run
 ix=find([B.run]==r);
 for j=ix(:).'
  if numel(ix)>=C.minStableBlocks, B(j).status="accepted";
  else, B(j).status="unconfirmed_short_run";
  end
 end
end
end
function d=delay(M,t)
d=M.delta_at_reference_s+M.slope_s_per_s*(t-M.reference_city_time_s);
end
