function T=frame_result_table(action,varargin)
switch action
 case 'seconds'
  P=varargin{1}; T=blockTable(P);
  if isfield(P,'selection') && P.selection.mode=="first_stable"
   reportMask=frame_interval_selection(P.blocks,P.identity,P.selection.report_seconds);
  else
   reportMask=frame_interval_selection(P.blocks,P.identity);
  end
  T=T(reportMask(:),:);
 case 'all_seconds', T=blockTable(varargin{:});
 case 'summary', T=summarize(varargin{:});
 otherwise, error('Frame:Table','Unknown result table action.');
end
end
function T=blockTable(P)
n=numel(P.blocks); File_Name=repmat(P.name,n,1);
Second=zeros(n,1); Status=strings(n,1); Stable_Run=zeros(n,1);
City_Total=nan(n,1); Village_Total=City_Total; Common=City_Total;
City_Only=City_Total; Village_Only=City_Total; Common_Over_Village=City_Total;
Delta_Center_s=City_Total; Drift_ppm=City_Total;
City_SNR_dB=City_Total; Village_SNR_dB=City_Total;
City_SNR_Class=strings(n,1); Village_SNR_Class=City_SNR_Class;
Excluded_Context_Or_Boundary_City=City_Total; Excluded_Context_Or_Boundary_Village=City_Total;
Ambiguous_Repeated_Matches=City_Total;
Counted_Start_Interval_Lo_s=City_Total; Counted_Start_Interval_Hi_s=City_Total;
for j=1:n
 Q=P.blocks(j); Second(j)=Q.second; Status(j)=Q.status; Stable_Run(j)=Q.run;
 if isfield(Q.model,'reference_city_time_s')
  % Explicit affine delay: do not dispatch to a toolbox function named predict.
  Delta_Center_s(j)=Q.model.delta_at_reference_s+Q.model.slope_s_per_s* ...
      (Q.second+.5-Q.model.reference_city_time_s);
  Drift_ppm(j)=Q.model.slope_s_per_s*1e6;
 end
 if isfield(Q.snr_city,'class')
  City_SNR_dB(j)=Q.snr_city.weighted_snr_db; City_SNR_Class(j)=Q.snr_city.class;
  Village_SNR_dB(j)=Q.snr_village.weighted_snr_db; Village_SNR_Class(j)=Q.snr_village.class;
 end
 if Q.status=="analyzed"
  same=find([P.blocks.run]==Q.run);
  Counted_Start_Interval_Lo_s(j)=max(Q.second+Cboundary(P), ...
      P.blocks(same(1)).second+P.identity.decodeStartupGuardS);
  Counted_Start_Interval_Hi_s(j)=min(Q.second+1-Cboundary(P), ...
      P.blocks(same(end)).second+1-P.identity.decodeTailGuardS);
  N=Q.counts; City_Total(j)=N.city_total; Village_Total(j)=N.village_total;
  Common(j)=N.common; City_Only(j)=N.city_only; Village_Only(j)=N.village_only;
  Common_Over_Village(j)=N.common_over_village;
  Excluded_Context_Or_Boundary_City(j)=N.excluded_city;
  Excluded_Context_Or_Boundary_Village(j)=N.excluded_village;
  Ambiguous_Repeated_Matches(j)=N.ambiguous_repeated_matches;
 end
end
T=table(File_Name,Second,Status,Stable_Run,Delta_Center_s,Drift_ppm, ...
 City_Total,Village_Total,Common,City_Only,Village_Only,Common_Over_Village, ...
 City_SNR_dB,Village_SNR_dB,City_SNR_Class,Village_SNR_Class, ...
 Excluded_Context_Or_Boundary_City,Excluded_Context_Or_Boundary_Village,Ambiguous_Repeated_Matches, ...
 Counted_Start_Interval_Lo_s,Counted_Start_Interval_Hi_s);
end
function v=Cboundary(P)
v=P.identity.boundaryGuardS;
end
function T=summarize(B)
Analyzed_Seconds=0; City_Total=0; Village_Total=0; Common=0; City_Only=0; Village_Only=0;
Common_Over_Village=NaN; Excluded_Seconds=height(B);
if ~isempty(B)
 ix=B.Status=="analyzed"; Analyzed_Seconds=sum(ix); Excluded_Seconds=sum(~ix);
 City_Total=sum(B.City_Total(ix)); Village_Total=sum(B.Village_Total(ix));
 Common=sum(B.Common(ix)); City_Only=sum(B.City_Only(ix)); Village_Only=sum(B.Village_Only(ix));
 if Village_Total>0, Common_Over_Village=Common/Village_Total; end
end
T=table(Analyzed_Seconds,Excluded_Seconds,City_Total,Village_Total,Common, ...
 City_Only,Village_Only,Common_Over_Village);
end
