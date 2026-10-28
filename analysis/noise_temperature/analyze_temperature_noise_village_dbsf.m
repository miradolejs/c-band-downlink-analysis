% Temperature versus median noise level - VILLAGE.
% MATLAB R2020b; median noise levels are loaded from noise_results, not recalculated from IQ.
clear; clc; close all;

%% 1. SETTINGS
noise_file = ''; % Empty -> file selection dialog; otherwise, absolute path to the noise MAT file
dir_village = 'F:\iq_data_vesnice'; % Daily ddMMyy directories containing JSON files
output_dir = 'D:\iq_analysis_results\TemperatureNoiseVillage';
save_figures = true;
noise_ylim = []; % Automatic range; optionally specify limits in the dataset units
if ~isempty(noise_ylim)
    validateattributes(noise_ylim, {'numeric'}, {'vector','numel',2,'real','finite'});
    assert(noise_ylim(1) < noise_ylim(2), 'Invalid noise-axis limits.');
end

if isempty(noise_file)
    [name,folder] = uigetfile('*.mat','Select the median noise dataset');
    if isequal(name,0), disp('Selection canceled.'); return; end
    noise_file = fullfile(folder,name);
end
timer_all = tic;
assert(isfile(noise_file),'Noise dataset not found: %s',noise_file);
loaded = load(noise_file,'noise_results');
assert(isfield(loaded,'noise_results'),'The file does not contain noise_results.');
noise_results = loaded.noise_results;
assert(noise_results.format_version == 1,'Unsupported dataset version.');
if isfield(noise_results,'analysis_type')
    assert(strcmp(noise_results.analysis_type,'noise_statistics'),'The dataset does not contain noise statistics.');
end
m = noise_results.metadata;
if isfield(m,'normalization_mode') && strcmp(m.normalization_mode,'mean_bin_dbfs_v1')
    noise_unit = 'dBFS';
else
    noise_unit = 'dB';
end
noise_tt = noise_results.village.data;
assert(istimetable(noise_tt),'Village results must be a timetable.');
assert(ismember('Median_Noise_dB',noise_tt.Properties.VariableNames), ...
    'The village dataset does not contain Median_Noise_dB.');
times = noise_tt.Properties.RowTimes;
assert(~any(isnat(times)) && numel(unique(times)) == numel(times), ...
    'The noise dataset contains invalid or duplicate timestamps.');
assert(isempty(times.TimeZone),'Timestamps must have an empty TimeZone; no timezone conversion is performed.');
offset_samples = round(m.actual_start_offset_s*m.sample_rate_hz);
chunk_samples = round(m.chunk_duration_s*m.sample_rate_hz);
nr = height(noise_tt);
temperature = nan(nr,1); metadata_time = NaT(nr,1);
valid = false(nr,1); sources = strings(nr,1);
status = repmat("missing_json",nr,1); seen = false(nr,1);

%% 2. EXACT JSON MATCHING TO CHUNKS FROM THE SAME RECORDING
days = m.analysis_start:caldays(1):m.analysis_end_exclusive-caldays(1);
for day = days
    folder = fullfile(dir_village,char(string(day,'ddMMyy')));
    if ~isfolder(folder), warning('Missing directory: %s',folder); continue; end
    files = dir(fullfile(folder,'*.json'));
    fprintf('%s: %d JSON files.\n',folder,numel(files));
    for fi = 1:numel(files)
        path = fullfile(folder,files(fi).name);
        tok = regexp(files(fi).name,'^\d+_(\d{6})_(\d{6})\.json$','tokens','once');
        if isempty(tok), continue; end
        try
            t0 = datetime([tok{2} tok{1}],'InputFormat','ddMMyyHHmmss');
        catch
            warning('Invalid date in JSON filename: %s',path); continue;
        end
        chunk_times = t0 + seconds((offset_samples + ...
            (0:m.chunks_per_file-1).'*chunk_samples)/m.sample_rate_hz);
        [matched,rows] = ismember(chunk_times,times);
        rows = rows(matched);
        if isempty(rows), continue; end
        assert(~any(seen(rows)), ...
            'Multiple JSON files match the same noise timestamp: %s',path);
        seen(rows) = true;
        metadata_time(rows) = t0; sources(rows) = string(path);
        try
            j = jsondecode(fileread(path));
        catch
            status(rows) = "json_error";
            warning('Cannot read JSON: %s',path); continue;
        end
        if ~isstruct(j) || ~isscalar(j)
            status(rows) = "invalid_json_structure"; continue;
        end
        if isfield(j,'env_valid')
            v = j.env_valid;
            if ~(islogical(v) || isnumeric(v)) || ~isscalar(v) || ...
                    ~isfinite(double(v)) || ~(v == 0 || v == 1)
                status(rows) = "invalid_env_flag"; continue;
            end
            if ~logical(v), status(rows) = "env_invalid"; continue; end
        end
        if ~isfield(j,'temperature_c')
            status(rows) = "missing_temperature"; continue;
        end
        t = j.temperature_c;
        if ~isnumeric(t) || ~isscalar(t) || ~isreal(t) || ~isfinite(t)
            status(rows) = "invalid_temperature"; continue;
        end
        % One temperature value in the JSON represents all analyzed chunks from this recording.
        % It is not an independent temperature measurement for each five-second chunk.
        temperature(rows) = t;
        valid(rows) = true; status(rows) = "matched";
    end
end

%% 3. SAVE RESULTS IN THE STANDARD FORMAT
village = timetable(times,noise_tt.Median_Noise_dB,temperature,metadata_time, ...
    valid,sources,status,'VariableNames', ...
    {'Median_Noise_dB','Temperature_C','Temperature_Metadata_Time', ...
     'Temperature_Valid','Temperature_Source_File','Temperature_Status'});
village.Properties.DimensionNames{1} = 'Time';
village.Properties.VariableUnits = {noise_unit,'degC','','','',''};
village = sortrows(village);
% Village-only analysis; city is an empty timetable of the same type.
city = village([],:);

temp_noise_results.format_version = 1;
temp_noise_results.schema_name = 'iq_analysis_results';
temp_noise_results.schema_version = 1;
temp_noise_results.analysis_type = 'temperature_noise_village';
temp_noise_results.analysis_name = 'Temperature and median noise level - village';
temp_noise_results.created_at = datetime('now');
temp_noise_results.metadata.noise_file = noise_file;
temp_noise_results.metadata.noise_metadata = m;
temp_noise_results.metadata.temperature_field = 'temperature_c';
temp_noise_results.metadata.temperature_units = 'degC';
temp_noise_results.metadata.temperature_matching = ...
    'Exact noise chunk timestamp = JSON filename start + stored offset + chunk index; one temperature per recording';
temp_noise_results.metadata.temperature_validation = ...
    'Finite real numeric scalar; reject env_valid=false or invalid flag when present; missing env_valid accepted';
temp_noise_results.metadata.invalid_policy = ...
    'Keep every noise row; unavailable temperature is NaN with status; no interpolation';
temp_noise_results.metadata.row_time_definition = 'Start of analyzed noise chunk';
temp_noise_results.metadata.temperature_time_definition = ...
    'Recording start parsed from JSON filename; not an independently known sensor acquisition time';
temp_noise_results.metadata.metric_names = {'Median_Noise_dB','Temperature_C'};
temp_noise_results.metadata.metric_units = {noise_unit,'degC'};
temp_noise_results.metadata.elapsed_seconds = toc(timer_all);
temp_noise_results.metadata.plot.noise_ylim = noise_ylim;
temp_noise_results.village.source_directory = dir_village;
temp_noise_results.village.data = village;
temp_noise_results.village.coverage = describe_coverage(village,chunk_samples/m.sample_rate_hz);
temp_noise_results.city.source_directory = '';
temp_noise_results.city.data = city;
run_id = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
temp_noise_results.run_id = run_id;
stem = sprintf('TemperatureNoiseVillage_%s_%s_%s', ...
    char(string(m.analysis_start,'yyyyMMdd')), ...
    char(string(m.analysis_end_exclusive-caldays(1),'yyyyMMdd')),run_id);
if ~isfolder(output_dir), mkdir(output_dir); end
save(fullfile(output_dir,[stem '.mat']),'temp_noise_results','-v7.3');
fprintf('Saved: %s\n',fullfile(output_dir,[stem '.mat']));
fprintf('Valid temperature for %d/%d chunks, from %d distinct JSON files.\n', ...
    nnz(valid),nr,numel(unique(sources(valid))));

%% 4. PLOT - TIME SERIES, NOT PROOF OF CAUSATION
if isempty(village), warning('The village dataset is empty.'); return; end
fig = figure('Name','Temperature and noise - village','NumberTitle','off', ...
    'Position',[100 100 1400 600]);
ax = axes(fig);
yyaxis(ax,'left');
h1 = plot(ax,village.Properties.RowTimes,village.Median_Noise_dB,'b.','MarkerSize',5);
ylabel(ax,sprintf('Median noise background level (%s)',noise_unit));
if ~isempty(noise_ylim), ylim(ax,noise_ylim); end
yyaxis(ax,'right');
h2 = plot(ax,village.Properties.RowTimes,village.Temperature_C,'r.','MarkerSize',5);
ylabel(ax,'Temperature from metadata (degC)');
title(ax,'Median noise level and temperature over time - village');
xlabel(ax,'Date and time'); grid(ax,'on');
legend(ax,[h1 h2],{'Median noise level','Temperature'},'Location','best');
ax.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';
if save_figures
    savefig(fig,fullfile(output_dir,[stem '.fig']));
    exportgraphics(ax,fullfile(output_dir,[stem '.png']),'Resolution',150);
end

function coverage = describe_coverage(tt,duration_s)
    coverage.row_count = height(tt);
    coverage.valid_temperature_count = nnz(tt.Temperature_Valid);
    coverage.unique_temperature_recordings = ...
        numel(unique(tt.Temperature_Source_File(tt.Temperature_Valid)));
    coverage.first_chunk_start = NaT; coverage.last_chunk_start = NaT;
    coverage.last_chunk_end_exclusive = NaT;
    if ~isempty(tt)
        coverage.first_chunk_start = min(tt.Properties.RowTimes);
        coverage.last_chunk_start = max(tt.Properties.RowTimes);
        coverage.last_chunk_end_exclusive = coverage.last_chunk_start+seconds(duration_s);
    end
end