% Batch PPS inventory. Configure sections 1 and 2, then run the entire script.
% Each RAW file produces ONE result row; at most the first five seconds are read.
clear; clc; close all;

%% 1. MODE AND DATA FOLDERS -- same directory layout as the noise analysis
test_mode = false;
max_test_files = 5; % per location, including files that produce errors
dir_city = 'E:\iq_data\mesto_1_2509_3009_2026';
dir_village = 'E:\iq_data\vesnice_1_2509_3009_2026';
analysis_start_date = datetime('25.09.2026','InputFormat','dd.MM.yyyy');
analysis_end_date = datetime('30.09.2026','InputFormat','dd.MM.yyyy');
output_dir = 'C:\Users\m_dolejs\Desktop\C_PASMO_A\vystupy\pps_inventar';
checkpoint_every_files = 25;
save_summary_figures = true;
save_test_file_diagnostics = true; % individual PNG diagnostics only in test mode

%% 2. DETECTOR AND RECORDING
C = pps_tools('config');
C.sample_rate_hz = 10e6;
C.center_frequency_if_hz = 1312e6;
C.nominal_marker_if_hz = 1315e6; % frequency directly in the recorded IF band
C.search_halfwidth_hz = 50e3;
C.inspect_duration_s = 5;
% Expected pulses: approximately 100 ms once per second. Use an initial test to
% adjust accepted widths, thresholds, and minimum pulse count. PPS identification
% requires more than a spectral line. The full configuration is saved in the MAT file.
C.expected_pulse_width_s = 0.100;
C.min_pulse_width_s = 0.040;
C.max_pulse_width_s = 0.250;
C.minimum_pulses = 2;
C.min_temporal_contrast_db = 10;
C.min_line_snr_db = 10;

%% 3. VALIDATION, DAILY FOLDER SELECTION, AND FILE DISCOVERY
assert(analysis_end_date>=analysis_start_date,'The end date precedes the start date.');
validateattributes(max_test_files,{'numeric'},{'scalar','integer','positive'});
validateattributes(checkpoint_every_files,{'numeric'},{'scalar','integer','positive'});
assert(C.minimum_pulses>=2,'At least two pulses are required to confirm periodicity.');
assert(C.search_halfwidth_hz+C.noise_outer_hz<C.channel_passband_hz, ...
    'The search band, including background estimation, must lie within the filter passband.');
assert(abs(C.nominal_marker_if_hz-C.center_frequency_if_hz) ...
    +C.channel_stopband_hz<C.sample_rate_hz/2, ...
    'The PPS search band lies outside the recorded IF band.');
functions_required = {'spectrogram','upfirdn','kaiserord','resample','butter','filtfilt'};
for k = 1:numel(functions_required)
    assert(exist(functions_required{k},'file')~=0, ...
        'Missing %s from Signal Processing Toolbox.',functions_required{k});
end
days = (analysis_start_date:caldays(1):analysis_end_date).';
days_to_process = cellstr(string(days,'ddMMyy'));
run_id = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
mode_label = 'FULL'; file_limit = Inf;
if test_mode, mode_label = 'TEST'; file_limit = max_test_files; end
run_folder = fullfile(output_dir,['PPS_' mode_label '_' run_id]);
assert(~isfolder(run_folder),'The output folder already exists.');
[ok,message] = mkdir(run_folder); assert(ok,'%s',message);
fprintf('Period %s to %s; mode %s.\n',char(string(analysis_start_date)), ...
    char(string(analysis_end_date)),mode_label);
fprintf('IF %.6f MHz +/- %.3f kHz; first %.3f s of each RAW file.\n', ...
    C.nominal_marker_if_hz/1e6,C.search_halfwidth_hz/1e3,C.inspect_duration_s);

pps_results = struct('format_version',1,'schema_name','iq_analysis_results', ...
    'schema_version',1,'analysis_type','pps_marker_inventory', ...
    'analysis_name','Inventory of injected PPS markers','created_at',datetime('now'), ...
    'run_id',run_id);
pps_results.metadata = struct('analysis_start',analysis_start_date, ...
    'analysis_end_exclusive',analysis_end_date+caldays(1),'detector',C, ...
    'test_mode',test_mode,'file_limit_per_location',file_limit, ...
    'is_complete_run',false,'row_definition','One attempted RAW file', ...
    'table_type','table, not timetable; invalid filename times are retained as NaT', ...
    'timestamp_timezone','Unspecified; filename clock preserved without conversion', ...
    'measurement_identity','Location + day-folder + RAW filename; root path excluded', ...
    'frequency_reference','Estimated IF relative to nominal SDR frequency/sample reference', ...
    'timing_reference','Coarse STFT threshold crossings; not sample-accurate PPS edges', ...
    'not_detected_policy','No pulse train confirmed under these thresholds; not proof of physical absence');
locations = {'city','village'}; roots = {dir_city,dir_village};
for loc = 1:2
    [inventory,day_inventory] = discoverFiles(roots{loc},days_to_process);
    pps_results.(locations{loc}) = struct('source_directory',roots{loc}, ...
        'data',pps_tools('empty'),'discovery',inventory,'days',day_inventory);
end
checkpoint_path = fullfile(run_folder,'PPS_checkpoint.mat');
timer = tic;

%% 4. ANALYSIS; INDIVIDUAL FILE ERRORS DO NOT STOP THE REMAINING FILES
for loc = 1:2
    label = locations{loc}; files = pps_results.(label).discovery;
    n = min(height(files),file_limit);
    rows = cell(n,1);
    fprintf('\n=== %s: found %d RAW files; selected %d ===\n',label,height(files),n);
    for k = 1:n
        info = table2struct(files(k,:));
        wantDetail = test_mode && save_test_file_diagnostics;
        [row,detail] = pps_tools('analyze',info,C,wantDetail);
        rows{k} = row;
        fprintf('%s %d/%d: %s | %s | pulses %d',label,k,n, ...
            char(row.File_Name),char(row.Status),row.Pulse_Count);
        if isfinite(row.Marker_IF_Hz), fprintf(' | IF %.3f Hz',row.Marker_IF_Hz); end
        fprintf('\n');
        if wantDetail && isfield(detail,'times_s')
            imagePath = fullfile(run_folder,sprintf('test_%s_%03d.png',label,k));
            try
                pps_tools('plot_file',detail,row,C,imagePath);
            catch ME
                warning('PPS:Plot','Cannot save diagnostic plot: %s',ME.message);
            end
        end
        if mod(k,checkpoint_every_files)==0 || k==n
            pps_results.(label).data = vertcat(rows{1:k});
            pps_results.metadata.analysis_elapsed_s = toc(timer);
            pps_tools('save',checkpoint_path,pps_results);
        end
    end
end

%% 5. FINAL DATASET, REPORTS, AND SUMMARY
pps_results.metadata.is_complete_run = true;
pps_results.metadata.analysis_elapsed_s = toc(timer);
stem = sprintf('PPSInventory_%s_%s_%s_%s', ...
    char(string(analysis_start_date,'yyyyMMdd')), ...
    char(string(analysis_end_date,'yyyyMMdd')),mode_label,run_id);
output_path = fullfile(run_folder,[stem '.mat']);
pps_tools('save',output_path,pps_results);
pps_tools('reports',pps_results,run_folder);
if save_summary_figures
    pps_tools('plot',pps_results,run_folder);
end
fprintf('\nSaved: %s\n',output_path);
fprintf('The PPS_not_detected_city.txt and PPS_not_detected_village.txt lists are in the same folder.\n');
fprintf('Ambiguous detections and errors are listed separately in PPS_ambiguous_and_errors.csv.\n');
fprintf('Analysis time: %.1f min. The checkpoint is not an additional independent dataset.\n',toc(timer)/60);

%% LOCAL FUNCTIONS
function [files,dayInfo] = discoverFiles(root,days)
files = table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    NaT(0,1),false(0,1),zeros(0,1),'VariableNames', ...
    {'Measurement_ID','Source_File','File_Name','Day_Folder', ...
    'File_Start_Time','Filename_Time_Valid','File_Size_Bytes'});
dayInfo = table(string(days(:)),false(numel(days),1),zeros(numel(days),1), ...
    'VariableNames',{'Day_Folder','Folder_Found','RAW_Files_Found'});
for d = 1:numel(days)
    folder = fullfile(root,days{d});
    dayInfo.Folder_Found(d) = isfolder(folder);
    if ~isfolder(folder)
        warning('PPS:MissingFolder','Folder not found: %s',folder); continue;
    end
    listing = dir(fullfile(folder,'*.raw'));
    listing = listing(~[listing.isdir]);
    dayInfo.RAW_Files_Found(d) = numel(listing);
    fprintf('%s: %d RAW.\n',folder,numel(listing));
    for k = 1:numel(listing)
        name = listing(k).name;
        parts = regexp(name,'(?i)^[^_]+_(\d{6})_(\d{6})\.raw$','tokens','once');
        time = NaT; valid = false;
        if ~isempty(parts)
            dateToken = parts{2}; clockToken = parts{1};
            try
                time = datetime(['20' dateToken(5:6) dateToken(3:4) dateToken(1:2) clockToken], ...
                    'InputFormat','yyyyMMddHHmmss');
                valid = strcmp(dateToken,days{d}) && ~isnat(time);
                if ~valid, time = NaT; end
            catch
                time = NaT;
            end
        end
        files(end+1,:) = {string([days{d} '/' name]), ...
            string(fullfile(folder,name)),string(name),string(days{d}), ...
            time,valid,double(listing(k).bytes)}; %#ok<AGROW>
    end
end
if ~isempty(files)
    files = sortrows(files,{'File_Start_Time','Day_Folder','File_Name'},'MissingPlacement','last');
end
end
