% Long-term peak detector; normalized mean FFT-bin power in dBFS.
% Reference: recorder digital scale, P_FS=1; physical ADC full scale has not been verified.
% MATLAB R2020b + Signal Processing Toolbox.
clear; clc; close all;
total_time_timer = tic;

%% 1. SETTINGS
test_mode = false;
max_test_files = 5;
dir_city = 'D:\iq_data\mesto_1_1809_2409_2026';
dir_village = 'D:\iq_data\vesnice_1_1809_2409_2026';
output_dir = 'G:\UTB\doktorát\ESA2026\ESA_vystupy\mesicni data\peaks_long_term_a';
analysis_start_date = datetime('18.09.2026', 'InputFormat', 'dd.MM.yyyy');
analysis_end_date = datetime('24.09.2026', 'InputFormat', 'dd.MM.yyyy');
assert(analysis_end_date >= analysis_start_date, 'Invalid analysis period.');
days_to_process = cellstr(string( ...
    (analysis_start_date:caldays(1):analysis_end_date).', 'ddMMyy'));

fs = 10e6;
fc = 1312e6;        % Recorded IF center frequency
lnb_lo_hz = 5.15e9;
noise_bands_rf_mhz = [3836.5, 3837.5]; % [lower RF limit, upper RF limit]
% [] automatically converts the unnormalized threshold; alternatively, specify a threshold directly in dBFS.
threshold_dbfs = [];
legacy_threshold_db = -24.0;
legacy_iq_scale = 32768;
iq_scale = 32767;       % Recorder: clip(CF32,-1,1)*32767 -> int16
reference_power = 1;   % A complex tone with |IQ|=1 has a total power of 0 dBFS
min_peak_distance_bins = 3; % In spectrogram time steps, not IQ samples
chunk_duration = 5.0; % Output: one peak count per five-second chunk
start_offset_s = 0.0;% Analysis offset from the start of each file
num_chunks = 11;
window_length = 8192;
noverlap = window_length/2;
nfft = 8192;
window_beta = 5;

validateattributes(noise_bands_rf_mhz, {'numeric'}, ...
    {'2d','real','finite','positive','nonempty'});
assert(size(noise_bands_rf_mhz,2) == 2 && ...
    all(noise_bands_rf_mhz(:,1) < noise_bands_rf_mhz(:,2)), 'Invalid RF band limits.');
assert(all(noise_bands_rf_mhz(:,2)*1e6 < lnb_lo_hz), 'RF bands must be below the LO frequency.');
validateattributes(start_offset_s, {'numeric'}, {'scalar','real','finite','nonnegative'});
validateattributes(num_chunks, {'numeric'}, {'scalar','finite','integer','positive'});
validateattributes(min_peak_distance_bins, {'numeric'}, {'scalar','finite','integer','positive'});
if ~isempty(threshold_dbfs)
    validateattributes(threshold_dbfs, {'numeric'}, {'scalar','real','finite'});
end
assert(chunk_duration == 5, 'Peaks_per_5s requires five-second chunks.');
noise_bands_mhz = [lnb_lo_hz/1e6-noise_bands_rf_mhz(:,2), ...
                   lnb_lo_hz/1e6-noise_bands_rf_mhz(:,1)];
assert(all(noise_bands_mhz(:,1) >= (fc-fs/2)/1e6 & ...
    noise_bands_mhz(:,2) <= (fc+fs/2)/1e6), 'The band is outside the recorded frequency range.');
num_complex_samples = round(fs*chunk_duration);
values_per_chunk = 2*num_complex_samples;
if test_mode, file_limit = max_test_files; else, file_limit = Inf; end

cfg.fs = fs; cfg.fc = fc; cfg.window = kaiser(window_length,window_beta);
cfg.overlap = noverlap; cfg.nfft = nfft;
window_energy = sum(abs(cfg.window).^2);
normalization_shift_db = 20*log10(legacy_iq_scale/iq_scale) - ...
    10*log10(nfft*window_energy*reference_power);
if isempty(threshold_dbfs)
    threshold_dbfs = legacy_threshold_db + normalization_shift_db;
    threshold_source = 'automatic_legacy_conversion';
else
    threshold_source = 'manual_dbfs';
end
validateattributes(threshold_dbfs, {'numeric'}, {'scalar','real','finite'});
fprintf('Detection threshold: %.6f dBFS (mean FFT-bin power).\n', threshold_dbfs);
cfg.iq_scale = iq_scale;
cfg.reference_power = reference_power;
cfg.window_energy = window_energy;
cfg.threshold = threshold_dbfs; cfg.min_peak_distance_bins = min_peak_distance_bins;
cfg.noise_bands_mhz = noise_bands_mhz;
cfg.offset_samples = round(start_offset_s*fs);
cfg.chunk_samples = num_complex_samples; cfg.num_chunks = num_chunks;
cfg.max_files = file_limit;
fprintf('Analyzing %.3f to %.3f s in each file.\n', ...
    cfg.offset_samples/fs, (cfg.offset_samples+num_chunks*num_complex_samples)/fs);

%% 2. ANALYSIS
city = analyze_impulses(dir_city, days_to_process, cfg);
village = analyze_impulses(dir_village, days_to_process, cfg);

%% 3. STANDARD DATASET FOR MERGING
impulse_results = struct();
impulse_results.format_version = 1;
impulse_results.schema_name = 'iq_analysis_results';
impulse_results.schema_version = 1;
impulse_results.analysis_type = 'broadband_impulses';
impulse_results.analysis_name = 'Broadband impulse detector';
impulse_results.created_at = datetime('now');
m.analysis_start = analysis_start_date;
m.analysis_end_exclusive = analysis_end_date+caldays(1);
m.sample_rate_hz = fs;
m.center_frequency_hz = fc; % IF, consistent with the other analysis scripts
m.center_frequency_if_hz = fc;
m.center_frequency_rf_hz = lnb_lo_hz-fc;
m.lnb_lo_hz = lnb_lo_hz;
m.frequency_conversion = 'RF = LO - IF';
m.noise_bands_mhz = noise_bands_mhz; % IF bands used for compatibility checks
m.noise_bands_if_mhz = noise_bands_mhz;
m.noise_bands_rf_mhz = noise_bands_rf_mhz;
m.chunk_duration_s = chunk_duration;
m.actual_chunk_duration_s = num_complex_samples/fs;
m.chunks_per_file = num_chunks;
m.requested_start_offset_s = start_offset_s;
m.actual_start_offset_s = cfg.offset_samples/fs;
m.requested_end_offset_s = (cfg.offset_samples+num_chunks*num_complex_samples)/fs;
m.window_type = 'Kaiser'; m.window_beta = window_beta;
m.window_length = window_length; m.overlap_samples = noverlap; m.nfft = nfft;
m.iq_format = 'Interleaved int16 I,Q; normalized by 32767';
m.iq_scale = iq_scale;
m.reference_power = reference_power;
m.power_reference = 'Recorder scale; complex constant-envelope tone |IQ|=1 -> 0 dBFS total power';
m.adc_full_scale_verified = false;
m.window_energy = window_energy;
m.bin_width_hz = fs/nfft;
m.spectral_quantity = 'Two-sided PSD multiplied by FFT bin width';
m.noise_units = 'dBFS mean FFT-bin power, recorder reference; not dBFS/Hz';
m.noise_definition = ...
    '10*log10(mean(abs(STFT).^2/(nfft*sum(abs(window).^2)) over selected frequency bins)/reference_power)';
m.time_reference = 'Chunk start; file start time parsed from filename';
m.timestamp_timezone = 'Unspecified; filename time preserved without timezone conversion';
m.row_time_definition = 'Start of analyzed chunk';
m.test_mode = test_mode; m.file_limit_per_location = file_limit;
m.threshold_db = threshold_dbfs; % Field required for compatibility with the result-merging utility
m.threshold_dbfs = threshold_dbfs;
m.threshold_units = 'dBFS';
m.threshold_quantity = 'Mean FFT-bin power over the union of selected RF bands';
m.threshold_source = threshold_source;
m.legacy_threshold_db = legacy_threshold_db;
m.legacy_iq_scale = legacy_iq_scale;
m.normalization_shift_db = normalization_shift_db;
m.min_peak_distance_bins = min_peak_distance_bins;
m.stft_time_step_s = (window_length-noverlap)/fs;
m.min_peak_distance_s = min_peak_distance_bins*m.stft_time_step_s;
m.detector_definition = ...
    'findpeaks of mean FFT-bin power in dBFS; MinPeakHeight=threshold_dbfs, MinPeakDistance=min_peak_distance_bins; independently in each chunk';
m.boundary_policy = ...
    'Chunks independent; boundary samples are not internal local maxima; no cross-chunk suppression';
m.metric_names = {'Peaks_per_5s'};
m.metric_units = {'count per 5 s'};
m.analysis_elapsed_s = toc(total_time_timer);
impulse_results.metadata = m;
impulse_results.city.source_directory = dir_city;
impulse_results.city.data = city;
impulse_results.city.coverage = coverage_summary(city,chunk_duration);
impulse_results.village.source_directory = dir_village;
impulse_results.village.data = village;
impulse_results.village.coverage = coverage_summary(village,chunk_duration);
run_id = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
impulse_results.run_id = run_id;
if test_mode, mode_label = 'TEST'; else, mode_label = 'FULL'; end
bands_label = arrayfun(@(b) sprintf('RF%g-%gMHz',noise_bands_rf_mhz(b,1), ...
    noise_bands_rf_mhz(b,2)),1:size(noise_bands_rf_mhz,1),'UniformOutput',false);
stem = sprintf('ImpulsesDBFS_%s_%s_%s_offset%gs_%dx5s_%s_%s', ...
    char(string(analysis_start_date,'yyyyMMdd')),char(string(analysis_end_date,'yyyyMMdd')), ...
    strjoin(bands_label,'_'),start_offset_s,num_chunks,mode_label,run_id);
if ~isfolder(output_dir), mkdir(output_dir); end
save(fullfile(output_dir,[stem '.mat']),'impulse_results','-v7.3');
fprintf('Saved: %s\n',fullfile(output_dir,[stem '.mat']));

%% 4. PLOT
if isempty(city) && isempty(village)
    warning('No complete chunks available; the saved dataset is empty.'); return;
end
fig = figure('Name','Peak occurrence over time','NumberTitle','off','Position',[100 100 1400 600]);
ax = axes(fig); hold(ax,'on');
if ~isempty(city)
    plot(ax,city.Properties.RowTimes,city.Peaks_per_5s,'r.','MarkerSize',8,'DisplayName','City');
end
if ~isempty(village)
    plot(ax,village.Properties.RowTimes,village.Peaks_per_5s,'b.','MarkerSize',8,'DisplayName','Village');
end
hold(ax,'off'); grid(ax,'on'); legend(ax,'show','Location','best');
title(ax,sprintf('Impulse detector, threshold %.3f dBFS (recorder scale)',threshold_dbfs));
xlabel(ax,'Date and time'); ylabel(ax,'Number of peaks per 5 seconds');
ax.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';
savefig(fig,fullfile(output_dir,[stem '.fig']));
exportgraphics(ax,fullfile(output_dir,[stem '.png']),'Resolution',150);
fprintf('Completed in %.1f minutes.\n',toc(total_time_timer)/60);

%% LOCAL FUNCTIONS
function out = analyze_impulses(base_dir,days,cfg)
    times = NaT(45000,1); counts = zeros(45000,1); row = 0; files_done = 0;
    for d = 1:numel(days)
        if files_done >= cfg.max_files, break; end
        folder = fullfile(base_dir,days{d});
        if ~isfolder(folder), warning('Missing directory: %s',folder); continue; end
        files = dir(fullfile(folder,'*.raw'));
        fprintf('%s: %d files.\n',folder,numel(files));
        for fi = 1:numel(files)
            if files_done >= cfg.max_files, break; end
            path = fullfile(folder,files(fi).name);
            tok = regexp(files(fi).name,'^\d+_(\d{6})_(\d{6})\.raw$','tokens','once');
            if isempty(tok), warning('Invalid filename: %s',path); continue; end
            try
                t0 = datetime([tok{2} tok{1}],'InputFormat','ddMMyyHHmmss');
            catch
                warning('Invalid date in filename: %s',path); continue;
            end
            fid = fopen(path,'r','ieee-le');
            if fid < 0, warning('Cannot open file: %s',path); continue; end
            guard = onCleanup(@() fclose(fid));
            if fseek(fid,4*cfg.offset_samples,'bof') ~= 0
                warning('Cannot seek to the requested offset: %s',path); clear guard; continue;
            end
            for chunk = 1:cfg.num_chunks
                raw = fread(fid,2*cfg.chunk_samples,'int16');
                if numel(raw) < 2*cfg.chunk_samples, break; end
                iq = complex(raw(1:2:end),raw(2:2:end))/cfg.iq_scale;
                [s,f] = spectrogram(iq,cfg.window,cfg.overlap,cfg.nfft,cfg.fs,'centered');
                f_mhz = (f+cfg.fc)/1e6;
                mask = false(size(f));
                for b = 1:size(cfg.noise_bands_mhz,1)
                    band_mask = f_mhz >= cfg.noise_bands_mhz(b,1) & ...
                        f_mhz <= cfg.noise_bands_mhz(b,2);
                    assert(any(band_mask),'Noise band %d contains no frequency bins.',b);
                    mask = mask | band_mask;
                end
                assert(any(mask),'The selected bands contain no frequency bins.');
                % Same normalization as in the short-interval dBFS detector.
                power_bin = abs(s(mask,:)).^2/(cfg.nfft*cfg.window_energy);
                level_lin = mean(power_bin,1)/cfg.reference_power;
                level_db = 10*log10(max(level_lin,realmin));
                clear raw iq s power_bin;
                if max(level_db) < cfg.threshold
                    locs = [];
                else
                    [~,locs] = findpeaks(level_db,'MinPeakHeight',cfg.threshold, ...
                        'MinPeakDistance',cfg.min_peak_distance_bins);
                end
                row = row+1;
                times(row) = t0+seconds((cfg.offset_samples+(chunk-1)*cfg.chunk_samples)/cfg.fs);
                counts(row) = numel(locs);
            end
            clear guard;
            files_done = files_done+1;
        end
    end
    out = timetable(times(1:row),counts(1:row),'VariableNames',{'Peaks_per_5s'});
    out.Properties.DimensionNames{1} = 'Time';
    out.Properties.VariableUnits = {'count per 5 s'};
    out.Properties.VariableDescriptions = {'Number of detected local maxima in a five-second chunk'};
    out = sortrows(out);
end

function summary = coverage_summary(tt,duration_s)
    summary.row_count = height(tt);
    summary.first_chunk_start = NaT; summary.last_chunk_start = NaT;
    summary.last_chunk_end_exclusive = NaT;
    if ~isempty(tt)
        summary.first_chunk_start = min(tt.Properties.RowTimes);
        summary.last_chunk_start = max(tt.Properties.RowTimes);
        summary.last_chunk_end_exclusive = summary.last_chunk_start+seconds(duration_s);
    end
end