function [reportMask,decodeMask]=frame_interval_selection(B,C,selectedSeconds)
% Keep complete synchronization runs. Decode adjacent windows for the same
% overlap reconciliation as a full run, but report only the requested seconds.
interval=[];
if isfield(C,'analysisIntervalS'), interval=C.analysisIntervalS; end
assert(isnumeric(interval) && isreal(interval) && (isempty(interval) || ...
 (isvector(interval) && numel(interval)==2 && all(isfinite(interval)) && ...
 all(interval==fix(interval)) && interval(1)>=0 && interval(2)>interval(1))), ...
 'Frame:Interval','analysisIntervalS must be [] or integer [start end), e.g. [5 15].');
seconds=[B.second]; reportMask=true(size(seconds));
if nargin>=3
 reportMask=ismember(seconds,selectedSeconds);
else
if ~isempty(interval)
 reportMask=seconds>=interval(1) & seconds<interval(2);
end
end
decodeMask=reportMask;
if (nargin<3 && isempty(interval)) || isempty(B), return; end
assert(isfinite(C.decodeContextS) && C.decodeContextS>=0, ...
 'Frame:Interval','decodeContextS must be finite and nonnegative.');
% Extra margin covers time bounds and contextual counterparts at a boundary.
halo=ceil(C.decodeContextS+C.matchToleranceS+C.boundaryGuardS+.01);
runs=[B.run]; decodeMask=reportMask;
for j=find(reportMask & runs>0)
 decodeMask=decodeMask | (abs(seconds-seconds(j))<=halo & runs==runs(j));
end
end
