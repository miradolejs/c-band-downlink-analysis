function varargout=frame_snr(action,varargin)
switch action
 case 'prepare', varargout{1}=prepare(varargin{:});
 case 'window', varargout{1}=window(varargin{:});
 case 'record_pair', varargout{1}=recordPair(varargin{:});
 otherwise, error('Frame:SNR','Unknown SNR action.');
end
end
function G=recordPair(S,name,cityRange,villageRange,C)
assert(isscalar(C.recordNoiseThresholdDb) && isfinite(C.recordNoiseThresholdDb) && ...
 isscalar(C.recordNoiseMinCoverage) && isfinite(C.recordNoiseMinCoverage) && ...
 C.recordNoiseMinCoverage>0 && C.recordNoiseMinCoverage<=1, ...
 'Frame:SNRConfig','Invalid record-noise threshold or minimum coverage.');
A=recordStation(S,'city',name,cityRange,C);
B=recordStation(S,'village',name,villageRange,C);
G=struct('city',A,'village',B,'skip_pair',false, ...
 'threshold_db',C.recordNoiseThresholdDb,'minimum_coverage',C.recordNoiseMinCoverage, ...
 'protect_positive_bins',C.recordNoiseProtectBursts, ...
 'method','Duration-weighted mean of linear SNR; both stations required', ...
 'reason',"retained");
if ~C.skipRecordLikelyNoise
 G.reason="record_filter_disabled";
elseif A.low_record && B.low_record
 G.skip_pair=true; G.reason="both_stations_low_record_snr";
else
 G.reason="city_"+A.reason+"; village_"+B.reason;
end
end
function W=recordStation(S,station,name,range,C)
D=S.(station); a=range(1); b=range(2);
W=struct('range_s',range,'rows',[],'coverage',0,'mean_snr_db',NaN, ...
 'max_snr_db',NaN,'has_positive_bin',false,'low_record',false, ...
 'reason',"missing_or_insufficient_snr");
if ~isfinite(a) || ~isfinite(b) || b<=a, return; end
ix=find(D.name==string(name) & D.start_s<b & D.start_s+S.chunk_s>a);
if isempty(ix), return; end
lo=max(a,D.start_s(ix)); hi=min(b,D.start_s(ix)+S.chunk_s);
[lo,order]=sort(lo); hi=hi(order); ix=ix(order); w=hi-lo;
assert(all(lo(2:end)>=hi(1:end-1)-1e-8),'Frame:SNR','Overlapping SNR bins.');
W.rows=ix(:).';
v=D.value(ix); processed=D.processed(ix);
zeroSignal=isnan(v) & isfinite(D.signal_power(ix)) & D.signal_power(ix)<=0;
valid=processed & (isfinite(v) | zeroSignal);
W.coverage=sum(w(valid))/(b-a);
if ~any(valid), return; end
ratio=zeros(size(v)); finite=isfinite(v) & valid;
ratio(finite)=10.^(v(finite)/10);
meanRatio=sum(w(valid).*ratio(valid))/sum(w(valid));
W.mean_snr_db=10*log10(meanRatio); % zero estimated signal -> -Inf, not missing.
if any(finite), W.max_snr_db=max(v(finite)); else, W.max_snr_db=-Inf; end
W.has_positive_bin=any(v(finite)>C.recordNoiseThresholdDb);
if W.coverage<C.recordNoiseMinCoverage-1e-8, return; end
if ~all(valid)
 W.reason="invalid_or_unprocessed_snr_bin"; return;
end
if C.recordNoiseProtectBursts && W.has_positive_bin
 W.reason="positive_snr_bin_present"; return;
end
if W.mean_snr_db<=C.recordNoiseThresholdDb
 W.low_record=true; W.reason="low_record_snr";
else
 W.reason="mean_above_threshold";
end
end
function S=prepare(input,C)
X=load(input,'snr_results'); assert(isfield(X,'snr_results'),'Missing snr_results.');
X=X.snr_results;
assert(istable(X.metadata.bands),'Missing bands table.');
band=find(abs(double(X.metadata.bands.RF_Center_MHz)-3839)<.001);
assert(isscalar(band),'SNR band 3839 MHz missing or ambiguous.');
assert(ismember('Bandwidth_MHz',X.metadata.bands.Properties.VariableNames), ...
 'Frame:SNRSchema','SNR bands table must contain Bandwidth_MHz.');
assert(abs(double(X.metadata.bands.Bandwidth_MHz(band))-1)<.001,'Expected 1 MHz SNR band.');
assert(abs(double(X.metadata.actual_chunk_duration_s)-5)<1e-9,'Expected five-second SNR bins.');
S=struct('chunk_s',double(X.metadata.actual_chunk_duration_s),'band',band);
for station=["city" "village"]
 T=X.(station).data; assert(istimetable(T),'Expected SNR timetable.');
 name=string(regexprep(cellstr(string(T.Source_File)),'.*[\\/]',''));
 n=height(T); starts=nan(n,1); nominal=NaT(n,1);
 for k=1:n
  nominal(k)=fileTime(name(k));
  starts(k)=seconds(T.Properties.RowTimes(k)-nominal(k));
 end
 value=double(T.SNR_dB(:,band));
 signal=double(T.Estimated_Signal_BinPower(:,band));
 processed=string(T.Status)=="processed";
 ref=nominal>=C.noiseReference(1) & nominal<C.noiseReference(2);
 noise=value(ref & processed & isfinite(value));
 active=value(~ref & processed & isfinite(value));
 threshold=NaN; calibration="disabled_or_insufficient"; edges=[NaN NaN];
 if C.useNoiseCalibration && numel(noise)>=20 && numel(active)>=20
  % No Statistics Toolbox needed; interpolate sorted empirical quantiles.
  edges=[quantileLocal(noise,.99),quantileLocal(active,.01)];
  if edges(2)-edges(1)>=2*C.snrUncertainMarginDb
   threshold=mean(edges); calibration="separated_reference_distributions";
  else
   calibration="overlapping_reference_distributions";
  end
 end
 S.(station)=struct('name',name,'start_s',starts,'value',value, ...
  'signal_power',signal,'processed',processed,'threshold_db',threshold, ...
  'calibration',calibration,'reference_edges_db',edges, ...
  'margin_db',C.snrUncertainMarginDb);
end
end
function W=window(S,station,name,a,b)
D=S.(station); ix=find(D.name==string(name) & D.start_s<b & D.start_s+S.chunk_s>a);
W=struct('class',"unknown",'coverage',0,'weighted_snr_db',NaN, ...
 'min_snr_db',NaN,'max_snr_db',NaN,'threshold_db',D.threshold_db,'rows',ix(:).');
if isempty(ix) || b<=a, return; end
lo=max(a,D.start_s(ix)); hi=min(b,D.start_s(ix)+S.chunk_s);
[lo,order]=sort(lo); hi=hi(order); ix=ix(order);
% Refuse duplicate/overlapping bins instead of double-counting coverage.
assert(all(lo(2:end)>=hi(1:end-1)-1e-8),'Overlapping SNR bins.');
w=hi-lo; W.coverage=sum(w)/(b-a);
v=D.value(ix); good=D.processed(ix);
finite=isfinite(v) & good;
if any(finite)
 W.weighted_snr_db=sum(v(finite).*w(finite))/sum(w(finite));
 W.min_snr_db=min(v(finite)); W.max_snr_db=max(v(finite));
end
if W.coverage<1-1e-6 || ~all(good), return; end
% NaN SNR is evidence only if the estimated signal power was nonpositive.
nonpositive=~isfinite(v) & isfinite(D.signal_power(ix)) & D.signal_power(ix)<=0;
if ~isfinite(D.threshold_db)
 if all(nonpositive), W.class="likely_noise"; else, W.class="uncertain"; end
 return;
end
low=(isfinite(v) & v<D.threshold_db-D.margin_db) | nonpositive;
high=isfinite(v) & v>D.threshold_db+D.margin_db;
if all(low), W.class="likely_noise";
elseif all(high), W.class="signal_likely";
else, W.class="uncertain";
end
end
function t=fileTime(name)
p=regexp(char(name),'^\d+_(\d{6})_(\d{6})\.raw$','tokens','once');
assert(~isempty(p),'Unrecognized SNR filename: %s',char(name));
d=p{2}; t=datetime([d(1:4) '20' d(5:6) ' ' p{1}],'InputFormat','ddMMuuuu HHmmss');
end
function q=quantileLocal(v,p)
v=sort(v(:)); x=1+(numel(v)-1)*p; a=floor(x); b=ceil(x);
q=v(a)+(x-a)*(v(b)-v(a));
end
