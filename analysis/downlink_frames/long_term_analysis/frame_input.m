function varargout=frame_input(action,varargin)
switch action
    case 'lookup', varargout{1}=lookup(varargin{:});
    case 'validate_raw', varargout{1}=validateRaw(varargin{:});
    case 'four_pps', [varargout{1:nargout}]=fourPulses(varargin{:});
    otherwise, error('SatBatch:Input','Unknown action.');
end
end
function row=lookup(T,name)
i=find(string(T.File_Name)==string(name));
assert(numel(i)==1,'SatSync:Inventory','Ambiguous or missing inventory entry.'); row=T(i,:);
end

function info=validateRaw(path,row,C)
d=dir(path); assert(numel(d)==1 && ~d.isdir,'SatSync:File','RAW file unavailable: %s',path);
assert(d.bytes==double(row.File_Size_Bytes) && mod(d.bytes,4)==0, ...
    'SatSync:File','RAW file size does not match the inventory or format.');
info=struct('bytes',d.bytes,'samples',d.bytes/4,'modified_datenum',d.datenum,'json_status','missing');
[folder,name]=fileparts(path); jp=fullfile(folder,[name '.json']);
if isfile(jp)
    J=jsondecode(fileread(jp)); info.json=J;
    assert(isfield(J,'sample_rate') && isfield(J,'center_freq') && ...
        isnumeric(J.sample_rate) && isscalar(J.sample_rate) && J.sample_rate==C.raw_fs_hz && ...
        isnumeric(J.center_freq) && isscalar(J.center_freq) && ...
        abs(J.center_freq-C.raw_center_if_hz)<1,'SatSync:Metadata','JSON sample rate or center frequency does not match.');
    info.json_status='checked';
end
end

function [s,e]=fourPulses(row)
s=double(row.Pulse_Onsets_s{1}(:)); e=double(row.Pulse_Ends_s{1}(:));
assert(numel(s)==numel(e) && numel(s)>=4,'SatSync:PPS','Four PPS pulses are required.');
s=s(end-3:end); e=e(end-3:end);
assert(all(isfinite([s;e])) && all(s>0.04) && ...
    all(e<double(row.Analyzed_Duration_s)-0.04) && ...
    all(e-s>=0.04 & e-s<=0.25) && ...
    all(abs(diff(s)-1)<=0.035+1e-9) && all(abs(diff(e)-1)<=0.035+1e-9), ...
    'SatSync:PPS','The last four PPS pulses are not complete and consecutive.');
end



