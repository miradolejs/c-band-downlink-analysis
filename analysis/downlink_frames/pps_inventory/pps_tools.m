function varargout = pps_tools(action,varargin)
% Shared PPS inventory functions. This utility does not synchronize pairs of RAW files.
switch char(action)
    case 'config', varargout{1} = defaultConfig();
    case 'empty', varargout{1} = resultTable(0);
    case 'blank', varargout{1} = resultTable(1);
    case 'analyze'
        [varargout{1:nargout}] = analyzeFile(varargin{:});
    case 'detect'
        [varargout{1:nargout}] = detectMarker(varargin{:});
    case 'reports', writeReports(varargin{:});
    case 'plot', plotSummary(varargin{:});
    case 'plot_file', plotFile(varargin{:});
    case 'save', saveAtomic(varargin{:});
    otherwise, error('PPS:Action','Unknown action: %s',char(action));
end
end

function C = defaultConfig()
C.algorithm_version = 'pps_if_pulse_train_v1_2_double_dsp_diagnostics';
C.sample_rate_hz = 10e6;
C.center_frequency_if_hz = 1312e6;
C.nominal_marker_if_hz = 1315e6;
C.search_halfwidth_hz = 50e3;
C.inspect_duration_s = 5;
C.iq_scale = 32767;
C.raw_chunk_samples = 1000000;
C.decimation = 50;
C.channel_passband_hz = 60e3;
C.channel_stopband_hz = 90e3;
C.channel_attenuation_db = 70;
C.stft_length = 4096;
C.stft_window = 'hann_periodic';
C.stft_hop_samples = 1000;
C.candidate_count = 20;
C.candidate_separation_hz = 300;
C.competing_candidate_power_margin_db = 12;
C.line_halfwidth_bins = 1;
C.noise_inner_hz = 500;
C.noise_outer_hz = 5000;
C.min_temporal_contrast_db = 10;
C.min_line_snr_db = 10;
C.expected_period_s = 1;
C.period_tolerance_s = 0.035;
C.max_gap_periods = 4;
C.minimum_pulses = 2;
C.expected_pulse_width_s = 0.100;
C.min_pulse_width_s = 0.040;
C.max_pulse_width_s = 0.250;
C.fill_holes_s = 0.010;
C.fine_decimation = 100;
C.fine_lowpass_hz = 150;
C.fine_edge_guard_s = 0.020;
C.validate_json_if_present = true;
C.json_frequency_tolerance_hz = 1;
C.absolute_frequency_reference_verified = false;
C.frequency_spread_definition = '1.4826*MAD of per-pulse frequencies; not absolute uncertainty';
C.fine_frequency_method = 'Phase slope in each pulse, separate intercepts, median across pulses';
end

function T = resultTable(n)
% Each row represents one RAW file. A table also retains files with invalid filename timestamps.
T = table(strings(n,1),strings(n,1),strings(n,1),strings(n,1), ...
    NaT(n,1),false(n,1),zeros(n,1),zeros(n,1),false(n,1), ...
    repmat("not_processed",n,1),false(n,1),zeros(n,1),zeros(n,1), ...
    NaN(n,1),NaN(n,1),NaN(n,1),NaN(n,1),NaN(n,1),NaN(n,1), ...
    NaN(n,1),NaN(n,1),NaN(n,1),strings(n,1),strings(n,1), ...
    cell(n,1),cell(n,1),cell(n,1),cell(n,1), ...
    'VariableNames',{'Measurement_ID','Source_File','File_Name','Day_Folder', ...
    'File_Start_Time','Filename_Time_Valid','File_Size_Bytes','Analyzed_Duration_s', ...
    'Complete_First5s','Status','PPS_Detected','Pulse_Count','Candidate_Pulse_Count', ...
    'Marker_IF_Hz','Marker_Offset_Hz','Pulse_Frequency_Spread_Hz', ...
    'Coarse_Candidate_IF_Hz','FFT_Bin_Width_Hz','Max_Period_Residual_s', ...
    'Median_Line_SNR_dB','Median_Temporal_Contrast_dB','Clipped_Sample_Fraction', ...
    'Metadata_Status','Message','Pulse_Onsets_s','Pulse_Ends_s', ...
    'Pulse_Frequencies_IF_Hz','Pulse_Line_SNR_dB'});
end

function [R,detail] = analyzeFile(file,C,wantDetail)
if nargin<3, wantDetail = false; end
R = resultTable(1);
R.Measurement_ID = string(file.Measurement_ID);
R.Source_File = string(file.Source_File);
R.File_Name = string(file.File_Name);
R.Day_Folder = string(file.Day_Folder);
R.File_Start_Time = file.File_Start_Time;
R.Filename_Time_Valid = file.Filename_Time_Valid;
R.File_Size_Bytes = file.File_Size_Bytes;
detail = struct;
try
    R.Metadata_Status = checkMetadata(char(R.Source_File),C);
    assert(mod(R.File_Size_Bytes,4)==0,'PPS:InvalidFormat', ...
        'RAW file size is not a multiple of 4 bytes (int16 I,Q).');
    if R.File_Size_Bytes==0
        R.Status = "empty_file"; R.Message = "Empty RAW file."; return;
    end
    count = min(round(C.inspect_duration_s*C.sample_rate_hz),R.File_Size_Bytes/4);
    duration = count/C.sample_rate_hz;
    R.Analyzed_Duration_s = duration;
    R.Complete_First5s = count==round(C.inspect_duration_s*C.sample_rate_hz);
    [iq,fs,delay,clipped] = readChannel(char(R.Source_File),count,C);
    R.Clipped_Sample_Fraction = clipped;
    [D,detail] = detectMarker(iq,fs,delay,duration,C,wantDetail);
    fields = fieldnames(D);
    for k = 1:numel(fields)
        key = fields{k};
        if ismember(key,R.Properties.VariableNames)
            if iscell(R.(key)), R.(key){1} = D.(key); else, R.(key)(1,:) = D.(key); end
        end
    end
    if ~R.Complete_First5s && R.Status=="not_detected"
        R.Status = "incomplete_window";
        R.Message = "PPS not confirmed; the file does not cover the entire requested initial interval.";
    elseif ~R.Complete_First5s
        R.Message = R.Message+" Only the available shorter interval was analyzed.";
    end
    if ~R.Filename_Time_Valid
        R.Message = R.Message+" The filename timestamp is invalid; the file was retained.";
    end
catch ME
    R.PPS_Detected = false;
    switch ME.identifier
        case 'PPS:MetadataMismatch', R.Status = "metadata_mismatch";
        case 'PPS:InvalidMetadata', R.Status = "invalid_metadata";
        case 'PPS:InvalidFormat', R.Status = "invalid_format";
        case 'PPS:Read', R.Status = "read_error";
        otherwise, R.Status = "error";
    end
    R.Message = string(ME.identifier)+": "+string(ME.message);
    detail.error_identifier = ME.identifier;
    detail.error_report = getReport(ME,'extended','hyperlinks','off');
    detail.error_stack = ME.stack;
    if ~isempty(ME.stack)
        R.Message = R.Message+sprintf(' [%s, line %d]',ME.stack(1).name,ME.stack(1).line);
    end
end
end

function state = checkMetadata(path,C)
state = "not_available";
if ~C.validate_json_if_present, state = "not_checked"; return; end
[folder,name] = fileparts(path);
jsonPath = fullfile(folder,[name '.json']);
if ~isfile(jsonPath), return; end
try
    J = jsondecode(fileread(jsonPath));
catch
    error('PPS:InvalidMetadata','Cannot read companion JSON: %s',jsonPath);
end
state = "available_no_fs_fc";
if isfield(J,'sample_rate')
    assert(isnumeric(J.sample_rate) && isscalar(J.sample_rate) && ...
        isfinite(J.sample_rate) && abs(J.sample_rate-C.sample_rate_hz)<=1e-6, ...
        'PPS:MetadataMismatch','JSON sample_rate does not match the configuration.');
    state = "checked";
end
if isfield(J,'center_freq')
    assert(isnumeric(J.center_freq) && isscalar(J.center_freq) && ...
        isfinite(J.center_freq) && ...
        abs(J.center_freq-C.center_frequency_if_hz)<=C.json_frequency_tolerance_hz, ...
        'PPS:MetadataMismatch','JSON center_freq does not match the configured IF center frequency.');
    state = "checked";
end
end

function [iq,fs,delay,clipped] = readChannel(path,count,C)
% Causal polyphase decimation. The retained overlap is a multiple of the decimation factor,
% so successive blocks retain the same sampling phase without independent block resampling.
D = C.decimation;
fs = C.sample_rate_hz/D;
assert(D==round(D) && D>=1,'PPS:Config','The decimation factor must be a positive integer.');
assert(C.channel_stopband_hz<fs/2 && ...
    C.channel_passband_hz>C.search_halfwidth_hz, ...
    'PPS:Config','Invalid decimation filter band.');
[n,Wn,beta,ftype] = kaiserord( ...
    [C.channel_passband_hz C.channel_stopband_hz],[1 0], ...
    [0.005 10^(-C.channel_attenuation_db/20)],C.sample_rate_hz);
n = n+mod(n,2);
h = single(fir1(n,Wn,ftype,kaiser(n+1,beta),'noscale'));
h = h/sum(h);
historyLength = ceil((numel(h)-1)/D)*D;
history = complex(zeros(historyLength,1,'single'));
iq = complex(zeros(ceil(count/D),1,'single'));
chunkLength = max(D,floor(C.raw_chunk_samples/D)*D);
fid = fopen(path,'r','ieee-le');
assert(fid>=0,'PPS:Read','Cannot open RAW file: %s',path);
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
readCount = 0; written = 0; numClipped = 0;
mixOffset = C.nominal_marker_if_hz-C.center_frequency_if_hz;
while readCount<count
    k = min(chunkLength,count-readCount);
    raw = fread(fid,[2 k],'int16=>single');
    assert(size(raw,2)==k,'PPS:Read','Unexpected end of file or RAW read error.');
    numClipped = numClipped+nnz(any(abs(raw)>=32767,1));
    x = complex(raw(1,:),raw(2,:)).'/single(C.iq_scale);
    t = (readCount+(0:k-1).')/C.sample_rate_hz;
    x = x.*single(exp(-1j*2*pi*mixOffset*t));
    combined = [history;x];
    % Use double-precision input and coefficients for upfirdn.
    % The remaining channel buffers use single precision.
    filtered = upfirdn(double(combined),double(h),1,D);
    firstOutput = historyLength/D+1;
    nOutput = ceil(k/D);
    iq(written+(1:nOutput)) = filtered(firstOutput:firstOutput+nOutput-1);
    history = combined(end-historyLength+1:end);
    written = written+nOutput; readCount = readCount+k;
end
iq = iq(1:written);
delay = (numel(h)-1)/(2*C.sample_rate_hz);
clipped = numClipped/max(count,1);
end

function [D,detail] = detectMarker(iq,fs,delay,duration,C,wantDetail)
if nargin<6, wantDetail = false; end
D = emptyDetection(); detail = struct;
% Use double precision throughout the subsequent DSP processing.
% Mixed single/double operations can return single-precision results.
iq = double(iq(:));
fs = double(fs); delay = double(delay); duration = double(duration);
if numel(iq)<C.stft_length
    D.Status = "incomplete_window"; D.Message = "Too few samples for time-frequency analysis."; return;
end
if ~all(isfinite(iq)) || mean(abs(double(iq)).^2)==0
    D.Status = "invalid_signal"; D.Message = "Zero or invalid IQ data."; return;
end
win = hann(C.stft_length,'periodic');
[S,f,t] = spectrogram(iq,win,C.stft_length-C.stft_hop_samples, ...
    C.stft_length,fs,'centered');
P = abs(double(S)).^2/(fs*sum(win.^2)); clear S;
t = t(:).'-delay; % STFT window centers, corrected for FIR group delay
valid = t>=0 & t<=duration;
t = t(valid); P = P(:,valid);
step = C.stft_hop_samples/fs;
binWidth = fs/C.stft_length;
D.FFT_Bin_Width_Hz = binWidth;
radius = C.line_halfwidth_bins;
smoothed = conv2(P,ones(2*radius+1,1)/(2*radius+1),'same');
baseline = median(smoothed,2);
nTop = min(size(P,2),max(2,round(C.expected_pulse_width_s/step/4)));
sorted = sort(smoothed,2,'descend');
ranking = 10*log10(max(mean(sorted(:,1:nTop),2),realmin)./max(baseline,realmin));
clear sorted;
eligible = find(abs(f)<=C.search_halfwidth_hz);
[~,rankOrder] = sort(ranking(eligible),'descend');
candidates = zeros(0,1);
for k = 1:numel(rankOrder)
    j = eligible(rankOrder(k));
    if isempty(candidates) || all(abs(f(candidates)-f(j))>=C.candidate_separation_hz)
        candidates(end+1,1) = j; %#ok<AGROW>
    end
    if numel(candidates)>=C.candidate_count, break; end
end
allCandidates = cell(numel(candidates),1);
for k = 1:numel(candidates)
    j = candidates(k);
    noiseBins = find(abs(f-f(j))>=C.noise_inner_hz & abs(f-f(j))<=C.noise_outer_hz);
    noise = median(P(noiseBins,:),1);
    trace = smoothed(j,:);
    timeContrast = 10*log10(max(trace,realmin)/max(baseline(j),realmin));
    snr = 10*log10(max(trace,realmin)./max(noise,realmin));
    gate = timeContrast>=C.min_temporal_contrast_db & snr>=C.min_line_snr_db;
    gate = closeHoles(gate,round(C.fill_holes_s/step));
    [starts,ends] = runs(gate);
    widths = (ends-starts+1)*step;
    keep = widths>=C.min_pulse_width_s & widths<=C.max_pulse_width_s;
    starts = starts(keep); ends = ends(keep);
    onsets = max(0,t(starts)-step/2);
    offsets = min(duration,t(ends)+step/2);
    chain = pulseChain(onsets,C);
    selected = chain;
    if isempty(selected), selected = 1:numel(starts); end
    pulseSNR = zeros(numel(selected),1); pulseContrast = pulseSNR;
    for q = 1:numel(selected)
        a = selected(q);
        pulseSNR(q) = median(snr(starts(a):ends(a)));
        pulseContrast(q) = median(timeContrast(starts(a):ends(a)));
    end
    item = struct('bin',j,'frequency',f(j),'allCount',numel(starts), ...
        'chainCount',numel(chain),'onsets',onsets(selected).', ...
        'ends',offsets(selected).','pulseSNR',pulseSNR,'pulseContrast',pulseContrast, ...
        'trace',trace,'noise',noise,'timeContrast',timeContrast,'snr',snr);
    item.onPower = finiteMedian(trace(gate));
    allCandidates{k} = item;
end
counts = cellfun(@(x) x.chainCount,allCandidates);
contrasts = cellfun(@(x) finiteMedian(x.pulseContrast),allCandidates);
contrasts(~isfinite(contrasts)) = -Inf;
[~,bestOrder] = sortrows([-counts(:) -contrasts(:)],[1 2]);
best = allCandidates{bestOrder(1)};
qualifying = find(counts>=C.minimum_pulses);
% Sidelobes of a strong intermittent tone are not independent generators.
% Only sufficiently strong periodic candidates are treated as competitors.
if ~isempty(qualifying)
    strengths = cellfun(@(x) x.onPower,allCandidates(qualifying));
    strongest = max(strengths);
    comparable = strengths>=strongest*10^(-C.competing_candidate_power_margin_db/10);
    qualifying = qualifying(comparable);
    if ~ismember(bestOrder(1),qualifying)
        [~,q] = max(strengths(comparable));
        best = allCandidates{qualifying(q)};
    end
end
D.Coarse_Candidate_IF_Hz = C.nominal_marker_if_hz+best.frequency;
D.Candidate_Pulse_Count = best.allCount;
D.Pulse_Count = best.chainCount;
D.Pulse_Onsets_s = best.onsets;
D.Pulse_Ends_s = best.ends;
D.Pulse_Line_SNR_dB = best.pulseSNR;
D.Median_Line_SNR_dB = finiteMedian(best.pulseSNR);
D.Median_Temporal_Contrast_dB = finiteMedian(best.pulseContrast);
if numel(best.onsets)>=2
    residuals = diff(best.onsets)-round(diff(best.onsets)/C.expected_period_s)*C.expected_period_s;
    D.Max_Period_Residual_s = max(abs(residuals));
end
if numel(qualifying)==1
    D.Status = "present"; D.PPS_Detected = true;
    D.Message = "Narrow intermittent line; the required number of pulses matches the PPS period.";
elseif numel(qualifying)>1
    D.Status = "ambiguous";
    D.Message = "Multiple distinct frequencies match the PPS model; review is required.";
elseif best.allCount>0
    D.Status = "ambiguous";
    D.Message = "An isolated pulse or pulses without a confirmed PPS period were found.";
else
    D.Status = "not_detected";
    D.Message = "PPS was not confirmed in the selected band at the configured thresholds.";
end
if ~isempty(best.onsets)
    frequencies = refineFrequency(iq,fs,delay,best,C);
    D.Pulse_Frequencies_IF_Hz = frequencies;
    good = frequencies(isfinite(frequencies));
    if ~isempty(good)
        estimate = median(good);
        % Output rounding defines storage resolution, not guaranteed accuracy.
        D.Marker_IF_Hz = round(estimate*1000)/1000;
        D.Marker_Offset_Hz = D.Marker_IF_Hz-C.nominal_marker_if_hz;
        if numel(good)>1
            D.Pulse_Frequency_Spread_Hz = 1.4826*median(abs(good-median(good)));
        end
    end
end
if wantDetail
    detail = struct('times_s',t,'frequency_offsets_hz',f, ...
        'power_db',10*log10(max(P,realmin)),'candidate',best, ...
        'candidate_frequencies_if_hz',C.nominal_marker_if_hz+f(candidates), ...
        'candidate_chain_counts',counts,'nominal_if_hz',C.nominal_marker_if_hz);
end
% Round stored values consistently across computers.
% Storage rounding does not represent physical measurement uncertainty.
fields3 = {'Marker_IF_Hz','Marker_Offset_Hz','Pulse_Frequency_Spread_Hz', ...
    'Median_Line_SNR_dB','Median_Temporal_Contrast_dB', ...
    'Pulse_Frequencies_IF_Hz','Pulse_Line_SNR_dB'};
for k = 1:numel(fields3)
    D.(fields3{k}) = round(D.(fields3{k})*1000)/1000;
end
D.Pulse_Onsets_s = round(D.Pulse_Onsets_s*1e6)/1e6;
D.Pulse_Ends_s = round(D.Pulse_Ends_s*1e6)/1e6;
D.Max_Period_Residual_s = round(D.Max_Period_Residual_s*1e6)/1e6;
end

function D = emptyDetection()
D = struct('Status',"not_detected",'PPS_Detected',false,'Pulse_Count',0, ...
    'Candidate_Pulse_Count',0,'Marker_IF_Hz',NaN,'Marker_Offset_Hz',NaN, ...
    'Pulse_Frequency_Spread_Hz',NaN,'Coarse_Candidate_IF_Hz',NaN, ...
    'FFT_Bin_Width_Hz',NaN,'Max_Period_Residual_s',NaN, ...
    'Median_Line_SNR_dB',NaN,'Median_Temporal_Contrast_dB',NaN, ...
    'Message',"",'Pulse_Onsets_s',zeros(0,1),'Pulse_Ends_s',zeros(0,1), ...
    'Pulse_Frequencies_IF_Hz',zeros(0,1),'Pulse_Line_SNR_dB',zeros(0,1));
end

function values = refineFrequency(iq,fs,delay,best,C)
fs = double(fs);
t = (0:numel(iq)-1).'/fs;
mixed = double(iq(:)).*exp(-1j*2*pi*double(best.frequency)*t);
slow = resample(double(mixed),1,double(C.fine_decimation));
fsSlow = fs/C.fine_decimation;
assert(C.fine_lowpass_hz<fsSlow/2,'PPS:Config','Invalid fine-estimation filter.');
[b,a] = butter(3,C.fine_lowpass_hz/(fsSlow/2));
slow = filtfilt(b,a,slow);
ts = (0:numel(slow)-1).'/fsSlow-delay;
values = NaN(numel(best.onsets),1);
for k = 1:numel(values)
    width = best.ends(k)-best.onsets(k);
    guard = min(C.fine_edge_guard_s,0.2*width);
    ix = ts>=best.onsets(k)+guard & ts<=best.ends(k)-guard;
    if nnz(ix)<10, continue; end
    x = ts(ix); x = x-mean(x);
    fit = polyfit(x,unwrap(angle(slow(ix))),1);
    values(k) = C.nominal_marker_if_hz+best.frequency+fit(1)/(2*pi);
end
end

function selected = pulseChain(times,C)
n = numel(times);
if n==0, selected = zeros(0,1); return; end
lengths = ones(n,1); costs = zeros(n,1); previous = zeros(n,1);
for i = 2:n
    for j = 1:i-1
        delta = times(i)-times(j);
        cycles = round(delta/C.expected_period_s);
        residual = abs(delta-cycles*C.expected_period_s);
        if cycles<1 || cycles>C.max_gap_periods || residual>C.period_tolerance_s, continue; end
        candidateLength = lengths(j)+1;
        candidateCost = costs(j)+residual;
        if candidateLength>lengths(i) || ...
                (candidateLength==lengths(i) && candidateCost<costs(i))
            lengths(i) = candidateLength; costs(i) = candidateCost; previous(i) = j;
        end
    end
end
[~,order] = sortrows([-lengths costs],[1 2]);
i = order(1); selected = i;
while previous(i)>0, i = previous(i); selected = [i;selected]; end %#ok<AGROW>
end

function gate = closeHoles(gate,maxHole)
[a,b] = runs(~gate);
for k = 1:numel(a)
    if a(k)>1 && b(k)<numel(gate) && b(k)-a(k)+1<=maxHole
        gate(a(k):b(k)) = true;
    end
end
end

function [a,b] = runs(x)
edges = diff([false logical(x(:).') false]);
a = find(edges==1); b = find(edges==-1)-1;
end

function v = finiteMedian(x)
x = x(isfinite(x));
if isempty(x), v = NaN; else, v = median(x); end
end

function saveAtomic(path,pps_results)
folder = fileparts(path);
if ~isfolder(folder), mkdir(folder); end
temp = [tempname(folder) '.mat'];
save(temp,'pps_results','-v7.3');
[ok,message] = movefile(temp,path,'f');
assert(ok,'PPS:Save','Cannot complete save operation: %s',message);
end

function writeReports(R,folder)
locations = {'city','village'};
all = table;
folderInventory = table;
fid = fopen(fullfile(folder,'PPS_summary.txt'),'w','n','UTF-8');
assert(fid>=0,'PPS:Save','Cannot create summary.');
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'PPS INVENTORY - first %.3f s of RAW data\n',R.metadata.detector.inspect_duration_s);
fprintf(fid,'Expected IF %.6f MHz; search range +/- %.3f kHz\n', ...
    R.metadata.detector.nominal_marker_if_hz/1e6,R.metadata.detector.search_halfwidth_hz/1e3);
fprintf(fid,'PPS not detected != proof of physical absence. Thresholds are stored in the MAT metadata.\n');
fprintf(fid,'Timing estimates are coarse STFT edges, not precise PPS timestamps.\n');
fprintf(fid,'Fine frequency is estimated relative to the SDR reference; absolute frequency accuracy is not guaranteed.\n\n');
for k = 1:2
    loc = locations{k}; T = R.(loc).data;
    present = nnz(T.Status=="present"); absent = nnz(T.Status=="not_detected");
    ambiguous = nnz(T.Status=="ambiguous"); other = height(T)-present-absent-ambiguous;
    fprintf(fid,'%s: evaluated files %d; PPS present %d; not detected %d; ambiguous %d; other/errors %d.\n', ...
        loc,height(T),present,absent,ambiguous,other);
    if isfield(R.(loc),'discovery')
        fprintf(fid,'  Files discovered in folders: %d; not processed in this dataset: %d.\n', ...
            height(R.(loc).discovery),height(R.(loc).discovery)- ...
            nnz(ismember(R.(loc).discovery.Measurement_ID,T.Measurement_ID)));
    end
    inventories = {R.(loc).days};
    if isfield(R.(loc),'days_per_input'), inventories = R.(loc).days_per_input; end
    for inputIndex = 1:numel(inventories)
        dayRows = inventories{inputIndex};
        if isempty(dayRows), continue; end
        dayRows.Location = repmat(string(loc),height(dayRows),1);
        dayRows.Input_Index = repmat(inputIndex,height(dayRows),1);
        if isempty(folderInventory)
            folderInventory = dayRows;
        else
            folderInventory = [folderInventory;dayRows]; %#ok<AGROW>
        end
        fprintf(fid,'  Input %d: requested daily folders %d, missing %d.\n', ...
            inputIndex,height(dayRows),nnz(~dayRows.Folder_Found));
    end
    frequencies = T.Marker_IF_Hz(T.Status=="present" & isfinite(T.Marker_IF_Hz));
    if ~isempty(frequencies)
        fprintf(fid,'  Estimated IF: median %.3f Hz, range %.3f to %.3f Hz.\n', ...
            median(frequencies),min(frequencies),max(frequencies));
    end
    flat = T;
    flat(:,{'Pulse_Onsets_s','Pulse_Ends_s','Pulse_Frequencies_IF_Hz','Pulse_Line_SNR_dB'}) = [];
    flat.Location = repmat(string(loc),height(flat),1);
    if isempty(all), all = flat; else, all = [all;flat]; end %#ok<AGROW>
    missingFid = fopen(fullfile(folder,['PPS_not_detected_' loc '.txt']),'w','n','UTF-8');
    assert(missingFid>=0,'PPS:Save','Cannot create file list.');
    fprintf(missingFid,'PPS was not detected at the configured thresholds in the first %.3f s.\n', ...
        R.metadata.detector.inspect_duration_s);
    missing = T(T.Status=="not_detected",:);
    for j = 1:height(missing)
        fprintf(missingFid,'%s\t%s\n',char(missing.Measurement_ID(j)),char(missing.Source_File(j)));
    end
    fclose(missingFid);
end
writetable(all,fullfile(folder,'PPS_all_files.csv'),'Encoding','UTF-8');
writetable(all(~ismember(all.Status,["present" "not_detected"]),:), ...
    fullfile(folder,'PPS_ambiguous_and_errors.csv'),'Encoding','UTF-8');
if ~isempty(folderInventory)
    writetable(folderInventory,fullfile(folder,'PPS_folder_coverage.csv'),'Encoding','UTF-8');
end
end

function plotSummary(R,folder)
figure('Name','PPS inventory','NumberTitle','off');
subplot(2,1,1); hold on;
names = {'city','village'}; colors = {'r.','b.'}; labels = {'City','Village'};
counts = zeros(2,4);
for k = 1:2
    T = R.(names{k}).data;
    ix = T.Status=="present" & ~isnat(T.File_Start_Time) & isfinite(T.Marker_IF_Hz);
    plot(T.File_Start_Time(ix),(T.Marker_IF_Hz(ix)-R.metadata.detector.nominal_marker_if_hz)/1e3, ...
        colors{k},'DisplayName',labels{k});
    counts(k,:) = [nnz(T.Status=="present") nnz(T.Status=="not_detected") ...
        nnz(T.Status=="ambiguous") nnz(~ismember(T.Status,["present" "not_detected" "ambiguous"]))];
end
grid on; legend('show'); ylabel('IF offset from nominal (kHz)');
title('Fine frequency estimates for confirmed PPS detections');
subplot(2,1,2); bar(counts,'stacked'); xticklabels(labels); grid on;
ylabel('File count'); legend({'Present','Not detected','Ambiguous','Error/short/other'},'Location','best');
savefig(gcf,fullfile(folder,'PPS_overview.fig'));
print(gcf,fullfile(folder,'PPS_overview.png'),'-dpng','-r130');
end

function plotFile(detail,row,C,path)
if ~isfield(detail,'times_s'), return; end
fig = figure('Visible','off','Name','PPS diagnostics');
cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
subplot(2,1,1);
ix = abs(detail.frequency_offsets_hz)<=C.search_halfwidth_hz;
imagesc(detail.times_s,detail.frequency_offsets_hz(ix)/1e3,detail.power_db(ix,:));
axis xy; colorbar; ylabel(sprintf('Offset from %.6f MHz (kHz)',C.nominal_marker_if_hz/1e6));
title(char(row.File_Name+" - "+row.Status),'Interpreter','none');
subplot(2,1,2); plot(detail.times_s,detail.candidate.timeContrast); hold on;
plot(detail.times_s,detail.candidate.snr);
yline(C.min_temporal_contrast_db,'--'); grid on;
xlabel('Time from RAW recording start (s)'); ylabel('dB');
legend({'Temporal contrast','Line / local spectral background'},'Location','best');
print(fig,path,'-dpng','-r120');
end
