function varargout=frame_sync_dsp(action,varargin)
% Delay convention: the same content occurs in the village at tB=tA+delta(tA).
switch action
    case 'defaults', varargout{1}=defaults();
    case 'estimate', varargout{1}=estimate(varargin{:});
    case 'read_channel', [varargout{1:nargout}]=readChannel(varargin{:});
    case 'fit_model', varargout{1}=fitModel(varargin{:});
    otherwise, error('SatSync:Action','Unknown action.');
end
end

function C=defaults()
C.version='satellite_joint_delay_frequency_v0.2';
C.raw_fs_hz=10e6; C.raw_center_if_hz=1312e6;
C.channel_center_if_hz=[NaN NaN]; % city, village; must be configured
C.channel_bandwidth_hz=NaN; % full occupied bandwidth, not half-bandwidth
C.cfo_search_hz=20e3;
C.probe_city_times_s=[6 16 26 36 46]; % for PSD preview only
C.block_duration_s=5;
C.pps_exclusion_end_s=5; % at least the first 5 s; extended according to the inventory
C.pps_exclusion_margin_s=0.050;
C.minimum_probe_span_s=0.020;
C.reference_duration_s=0.020;
C.pilot_duration_s=0.001;
C.validation_offset_s=0.010; C.validation_duration_s=0.008;
C.delay_search_radius_s=0.020; % around the COARSE PPS-based delay
C.validation_radius_s=0.0002;
C.max_train_validation_disagreement_s=20e-6;
C.min_correlation=0.20; C.min_peak_ratio=1.30;
C.min_valid_probes=3; C.max_model_residual_s=20e-6;
C.max_abs_drift_ppm=100;
C.channel_guard_s=0.010;
C.conjugate_village=false;
end

function P=estimate(x,y,fs,C)
% x: complete 20 ms city reference segment.
% y: longer village segment starting delay_search_radius_s before the PPS prediction.
% The lag is the number of analyzed samples from the start of y to the content of x(1).
% Use one fixed reference pilot with full pilot overlap at every lag.
P=struct('resolved',false,'status','unresolved_target_sync','reason','');
try
    x=double(x(:)); y=double(y(:));
    assert(all(isfinite(x)) && all(isfinite(y)),'SatSync:Data','Invalid IQ data.');
    L=round(C.pilot_duration_s*fs); maxStart=2*round(C.delay_search_radius_s*fs);
    if isfield(C,'max_start_samples'), maxStart=C.max_start_samples; end
    assert(isscalar(maxStart) && isfinite(maxStart) && maxStart>=4 && maxStart==floor(maxStart), ...
        'SatSync:Range','Invalid reference position range.');
    assert(numel(x)>=round(C.reference_duration_s*fs) && numel(y)>=maxStart+numel(x), ...
        'SatSync:Length','The input segment is too short or incorrectly constructed.');
    assert(L>=32 && L<numel(x),'SatSync:Length','Invalid pilot length.');
    a=x(1:L); a=a-mean(a); energy=sum(abs(a).^2);
    assert(energy>eps*max(1,sum(abs(x(1:L)).^2)), ...
        'SatSync:Excitation','The reference has insufficient signal variation.');
    % Doppler bin spacing <=1/(4*T) limits mismatch between frequency grid points.
    step=1/(4*(L/fs)); nf=max(1,ceil(2*C.cfo_search_hz/step));
    freqs=linspace(-C.cfo_search_hz,C.cfo_search_hz,nf+1);
    n=(0:numel(y)-1)'/fs; nfft=2^nextpow2(numel(y)+L-1);
    kernelFFT=fft(conj(flipud(a)),nfft);
    idx=(0:maxStart)'; bestByLag=zeros(numel(idx),1);
    maxByFrequency=zeros(numel(freqs),1); best=-inf; bestF=NaN; bestK=NaN;
    for j=1:numel(freqs)
        scores=scoreRow(y.*exp(-1i*2*pi*freqs(j)*n),a,kernelFFT,nfft,idx);
        bestByLag=max(bestByLag,scores);
        [value,k]=max(scores); maxByFrequency(j)=value;
        if value>best, best=value; bestF=j; bestK=k; end
    end
    coarseLag=idx(bestK); coarseFreq=freqs(bestF);
    % Fine CFO correction using the matched content; a phase difference is allowed.
    product=y(coarseLag+(1:L)).*conj(a);
    lo=max(-C.cfo_search_hz,coarseFreq-step);
    hi=min(C.cfo_search_hz,coarseFreq+step);
    freq=fminbnd(@(f)-abs(sum(product.*exp(-1i*2*pi*f*(0:L-1)'/fs))), ...
        lo,hi,optimset('Display','off','TolX',0.01));
    scores=scoreRow(y.*exp(-1i*2*pi*freq*n),a,kernelFFT,nfft,idx);
    [peak,k]=max(scores); lag=idx(k)+parabolic(scores,k);
    bestByLag=max(bestByLag,scores);
    exclusion=max(4,ceil(2*fs/C.channel_bandwidth_hz));
    competitors=abs(idx-idx(k))>exclusion;
    if any(competitors), runner=max(bestByLag(competitors)); else, runner=NaN; end
    ratio=peak/max(runner,eps);
    timeBoundary=k<=2 || k>=numel(idx)-1;
    freqBoundary=bestF==1 || bestF==numel(freqs) || ...
        abs(freq)>C.cfo_search_hz-0.05*step;
    % Separate validation content: keep CFO fixed and check a small residual delay.
    off=round(C.validation_offset_s*fs); Lv=round(C.validation_duration_s*fs);
    assert(off>=L && off+Lv<=numel(x),'SatSync:Config','Pilot and validation segments overlap.');
    av=x(off+(1:Lv)); av=av-mean(av);
    center=round(lag)+off; radius=round(C.validation_radius_s*fs);
    starts=(center-radius:center+radius)';
    assert(min(starts)>=0 && max(starts)+Lv<=numel(y),'SatSync:Validation','Validation segment lies outside the input window.');
    rotated=y.*exp(-1i*2*pi*freq*n);
    vfft=2^nextpow2(numel(y)+Lv-1);
    vscores=scoreRow(rotated,av,fft(conj(flipud(av)),vfft),vfft,starts);
    [vp,vk]=max(vscores); validationLag=starts(vk)+parabolic(vscores,vk)-off;
    disagreement=(validationLag-lag)/fs;
    validationBoundary=vk<=2 || vk>=numel(starts)-1;
    reasons=strings(0,1);
    if peak<C.min_correlation, reasons(end+1)="Weak training-segment correlation."; end
    if ~isfinite(ratio) || ratio<C.min_peak_ratio, reasons(end+1)="Ambiguous delay peak."; end
    if timeBoundary || freqBoundary, reasons(end+1)="Maximum at the delay or frequency search boundary."; end
    if vp<C.min_correlation || validationBoundary, reasons(end+1)="Independent validation failed."; end
    tolerance=max(C.max_train_validation_disagreement_s,2/fs);
    if abs(disagreement)>tolerance, reasons(end+1)="Training and validation segments produce inconsistent delays."; end
    P.lag_from_y_start_samples=lag;
    P.validation_lag_from_y_start_samples=validationLag;
    P.combined_lag_samples=(lag+validationLag)/2;
    P.residual_cfo_hz=freq;
    P.train_correlation=peak; P.validation_correlation=vp;
    P.peak_ratio=ratio; P.runner_up=runner;
    P.train_validation_disagreement_s=disagreement;
    P.search_at_boundary=timeBoundary || freqBoundary || validationBoundary;
    P.frequency_grid_hz=freqs; P.max_score_per_frequency=maxByFrequency;
    % Retain a sparse diagnostic curve; the calculation uses all lags.
    stride=max(1,ceil(numel(idx)/10000));
    P.lag_grid_samples=idx(1:stride:end);
    P.max_score_per_lag=single(bestByLag(1:stride:end));
    P.resolved=isempty(reasons);
    if P.resolved, P.status='resolved_target_probe'; P.reason='Pilot and separate validation segment agree.';
    else, P.reason=char(strjoin(reasons,' ')); end
catch ME
    P.status='probe_error'; P.reason=ME.message;
    P.error_report=getReport(ME,'extended','hyperlinks','off');
end
end

function scores=scoreRow(y,a,kernelFFT,nfft,starts)
% Magnitude of complex Pearson correlation over a fixed full overlap.
% starts contains zero-based positions of the complete reference a in y; correlation is linear.
L=numel(a); a=a(:); y=y(:);
z=ifft(fft(y,nfft).*kernelFFT);
dot=z(starts+L);
sy=[0;cumsum(y)]; sy2=[0;cumsum(abs(y).^2)];
s=sy(starts+L+1)-sy(starts+1);
rawEnergy=sy2(starts+L+1)-sy2(starts+1);
e=rawEnergy-abs(s).^2/L;
den=sqrt(sum(abs(a).^2).*max(e,0));
% Guard against catastrophic cancellation for nearly constant y after derotation.
scores=zeros(size(starts)); valid=e>1e-12*max(rawEnergy,realmin) & den>0;
scores(valid)=min(1,abs(dot(valid))./den(valid));
end

function d=parabolic(c,k)
d=0;
if k>1 && k<numel(c)
    den=c(k-1)-2*c(k)+c(k+1);
    if den<0, d=0.5*(c(k-1)-c(k+1))/den; end
end
end

function [iq,t0,fsOut]=readChannel(path,startSeconds,durationSeconds,site,C)
% Use the same filter, decimation, and format for both stations, without AGC.
cut=C.channel_bandwidth_hz/2+C.cfo_search_hz;
D=max(1,floor(C.raw_fs_hz/(3*cut))); fsOut=C.raw_fs_hz/D;
guard=ceil(C.channel_guard_s*C.raw_fs_hz/D)*D;
first=floor(startSeconds*C.raw_fs_hz/D)*D-guard;
N=ceil(durationSeconds*fsOut); count=N*D+2*guard;
assert(first>=0,'SatSync:Read','The requested segment starts before the RAW recording.');
fid=fopen(path,'rb','ieee-le'); assert(fid>=0,'SatSync:Read','Cannot open RAW file.'); cleanup=onCleanup(@()fclose(fid));
assert(fseek(fid,first*4,'bof')==0,'SatSync:Read','File seek failed.');
a=fread(fid,[2 count],'int16=>double'); assert(size(a,2)==count,'SatSync:Read','Incomplete RAW segment.');
x=complex(a(1,:).',a(2,:).')/32767;
n=(0:count-1)'/C.raw_fs_hz;
x=x.*exp(-1i*2*pi*(C.channel_center_if_hz(site)-C.raw_center_if_hz)*n);
[z,p,k]=butter(5,cut/(C.raw_fs_hz/2)); [sos,g]=zp2sos(z,p,k);
x=filtfilt(double(sos),double(g),double(x));
x=resample(double(x),1,double(D));
skip=guard/D; iq=x(skip+(1:N));
t0=(first+guard)/C.raw_fs_hz;
if site==2 && C.conjugate_village, iq=conj(iq); end
end

function M=fitModel(times,delays,C)
% Theil-Sen fit using validated probes only; no automatic resampling is applied.
M=struct('usable',false,'status','insufficient_valid_probes');
t=double(times(:)); d=double(delays(:));
if numel(t)<C.min_valid_probes, return; end
slopes=[];
for a=1:numel(t)-1
    for b=a+1:numel(t)
        if t(a)~=t(b), slopes(end+1,1)=(d(b)-d(a))/(t(b)-t(a)); end %#ok<AGROW>
    end
end
assert(~isempty(slopes),'SatSync:Model','Distinct probe times are required.');
slope=median(slopes); tref=median(t); delta=median(d-slope*(t-tref));
res=d-(delta+slope*(t-tref));
M.reference_city_time_s=tref; M.delta_at_reference_s=delta;
M.slope_s_per_s=slope; M.apparent_drift_ppm=slope*1e6;
M.residual_s=res; M.max_abs_residual_s=max(abs(res));
M.validated_city_range_s=[min(t) max(t)];
M.convention='t_village = t_city + delta_at_reference_s + slope_s_per_s*(t_city-reference_city_time_s)';
M.usable=max(abs(res))<=C.max_model_residual_s && abs(slope)*1e6<=C.max_abs_drift_ppm;
if M.usable, M.status='consistent_target_model'; else, M.status='nonlinear_or_discontinuous_timing'; end
M.applied_to_raw=false;
M.scope='Valid only between verified probes; continuity between them and UTC calibration are not established.';
end

