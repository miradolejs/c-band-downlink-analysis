function varargout=frame_sync_probe(action,varargin)
switch action
    case 'probe', varargout{1}=probe(varargin{:});
    case 'wide', varargout{1}=wide(varargin{:});
    case 'bounds', [varargout{1:nargout}]=bounds(varargin{:});
    otherwise, error('SatJump:Action','Unknown action.');
end
end

function [lo,hi,fs]=bounds(tx,center,radius,durationB,C)
cut=C.channel_bandwidth_hz/2+C.cfo_search_hz;
D=max(1,floor(C.raw_fs_hz/(3*cut))); fs=C.raw_fs_hz/D;
g=ceil(C.channel_guard_s*C.raw_fs_hz/D)*D/C.raw_fs_hz;
margin=10/fs;
lo=max(tx+center-radius,g+margin);
hi=min(tx+center+radius,durationB-g-C.reference_duration_s-margin);
assert(hi-lo>4/fs,'SatJump:Overlap','No search window is available.');
end

function P=probe(city,village,t,center,radius,durationB,C,keepIQ)
P=struct('resolved',false,'status','probe_error','reason','');
P.requested_city_time_s=t;
try
    [x,tx,fs]=frame_sync_dsp('read_channel',city,t,C.reference_duration_s,1,C);
    [lo,hi,~]=bounds(tx,center,radius,durationB,C);
    [y,ty,fy]=frame_sync_dsp('read_channel',village,lo, ...
        hi-lo+C.reference_duration_s+4/fs,2,C);
    assert(fs==fy,'SatJump:Rate','Sample rates do not match.');
    E=C; E.max_start_samples=floor((hi-ty)*fs);
    assert(numel(y)>=E.max_start_samples+numel(x),'SatJump:Length','Insufficient window length.');
    P=frame_sync_dsp('estimate',x,y,fs,E);
    P.requested_city_time_s=t; P.city_start_s=tx; P.village_start_s=ty;
    P.analysis_fs_hz=fs; P.search_delta_range_s=[ty-tx,ty+E.max_start_samples/fs-tx];
    P.requested_center_delta_s=center; P.requested_radius_s=radius;
    P.channel_bandwidth_hz=C.channel_bandwidth_hz;
    P.city_power_db=10*log10(max(mean(abs(x).^2),realmin));
    P.village_search_power_db=10*log10(max(mean(abs(y).^2),realmin));
    if isfield(P,'combined_lag_samples')
        P.total_delta_s=ty+P.combined_lag_samples/fs-tx;
    end
    if keepIQ, P.city_iq=single(x); P.village_iq=single(y); end
catch ME
    P.status='probe_error'; P.reason=ME.message;
    P.error_report=getReport(ME,'extended','hyperlinks','off');
end
end

function W=wide(city,village,t,coarse,durationB,C,J)
% Use the narrow channel for candidate discovery; always confirm at the full 2 MHz bandwidth.
K=C; K.channel_bandwidth_hz=J.discovery_bandwidth_hz;
W=struct('requested_city_time_s',t,'resolved',false,'status','wide_unresolved', ...
    'reason','Candidate not confirmed at full bandwidth.');
W.discovery=probe(city,village,t,coarse,J.wide_radius_s,durationB,K,false);
D=W.discovery;
if ~isfield(D,'total_delta_s') || ~isfinite(D.total_delta_s) || ...
        D.train_correlation<J.discovery_min_correlation
    W.reason='No adequate narrow-channel candidate; this does not establish absence of a match.';
    return
end
% Use the best candidate even if it failed coarse validation.
% Acceptance requires full-channel searching and separate validation.
W.full_confirmation=probe(city,village,t,D.total_delta_s,J.confirm_radius_s,durationB,C,false);
F=W.full_confirmation;
if F.resolved && D.resolved
    W.resolved=true; W.status='wide_confirmed';
    W.total_delta_s=F.total_delta_s;
    W.reason='Narrow-channel candidate confirmed at full bandwidth and on separate content.';
else
    W.reason=['Narrow search: ' D.reason ' Full channel: ' F.reason];
end
end

