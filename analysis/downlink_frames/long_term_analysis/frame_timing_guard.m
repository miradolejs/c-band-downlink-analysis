function I=frame_timing_guard(action,actual,inputSamples,sps,cfg,isFirst)
% Consistency guard, not a proof of symbol lock. Count includes synchronizer
% startup and is checked before initial/final symbol trimming.
if nargin<6, isFirst=false; end
nominal=double(inputSamples)/sps;
I=struct('actual_symbols',double(actual),'nominal_symbols',nominal, ...
 'difference_symbols',double(actual)-nominal,'allowed_difference_symbols',NaN);
switch action
 case 'chunk'
  cap=ceil(nominal*1.1);
  if actual>=cap
   error('Frame:TimingOutputLimit', ...
    'Symbol output %d reaches MATLAB limit %d for %d input samples; reject this decode window.',actual,cap,inputSamples);
  end
  allowance=setting(cfg,'timingChunkAllowanceSymbols',8);
  if isFirst, allowance=setting(cfg,'timingStartupAllowanceSymbols',32); end
  I.allowed_difference_symbols=allowance;
  if abs(I.difference_symbols)>allowance
   error('Frame:TimingChunkCount', ...
    'Symbol count %d vs nominal %.3f in one chunk (allowed difference %.3f).',actual,nominal,allowance);
  end
 case 'total'
  ppm=setting(cfg,'maxTimingDriftPpm',100);
  allowance=ceil(nominal*ppm*1e-6)+setting(cfg,'timingStartupAllowanceSymbols',32);
  I.allowed_difference_symbols=allowance;
  I.max_allowed_rate_difference_ppm=ppm;
  if abs(I.difference_symbols)>allowance
   error('Frame:TimingTotalCount', ...
    'Total symbol count %d vs nominal %.3f (allowed difference %.3f symbols).',actual,nominal,allowance);
  end
 otherwise, error('Frame:Action','Unknown timing guard action.');
end
I.accepted=true;
end
function v=setting(C,k,fallback)
if isfield(C,k), v=C.(k); else, v=fallback; end
end
