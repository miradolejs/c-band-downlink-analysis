% Batch analysis of the median and standard deviation of noise levels
clear; clc; close all;

%% 1. ANALYSIS MODE
test_mode = false; % true = limited test; false = the full specified period
max_test_files = 5;     % Maximum number of files per site when test_mode = true

%% 2. PARAMETERS AND DIRECTORIES
dir_city = 'D:\iq_data\mesto_1_1809_2409_2026';
dir_village = 'D:\iq_data\vesnice_1_1809_2409_2026';

% Analysis period, including the entire first and last days
analysis_start_date = datetime('18.09.2026', 'InputFormat', 'dd.MM.yyyy');
analysis_end_date   = datetime('24.09.2026', 'InputFormat', 'dd.MM.yyyy');

% Validate the analysis period
if analysis_end_date < analysis_start_date
    error('The analysis end date must not precede the start date.');
end

% Generate daily directory names in ddMMyy format
analysis_days = (analysis_start_date:caldays(1):analysis_end_date).';
days_to_process = cellstr(string(analysis_days, 'ddMMyy'));

fprintf('Analysis period: %s to %s (%d days).\n', ...
    char(string(analysis_start_date, 'dd.MM.yyyy')), ...
    char(string(analysis_end_date, 'dd.MM.yyyy')), ...
    numel(days_to_process));

fs = 10e6;           % Sampling rate: 10 MS/s
fc = 1312e6;       % Recording center frequency after LNB conversion (IF)
lnb_lo_hz = 5.15e9;  % LNB local oscillator frequency

% RF center frequency of the received band
fc_rf_hz = lnb_lo_hz - fc;

% Specify noise bands using RF frequencies before LNB conversion.
% Each row: [lower limit, upper limit] in MHz.
noise_bands_rf_mhz = [
    3836.5, 3837.5
];

% Validate the selected bands
validateattributes(noise_bands_rf_mhz, {'numeric'}, ...
    {'2d', 'real', 'finite', 'positive', 'nonempty'});

if size(noise_bands_rf_mhz, 2) ~= 2
    error('Each noise band must have a lower and an upper limit.');
end

if any(noise_bands_rf_mhz(:, 1) >= noise_bands_rf_mhz(:, 2))
    error('The lower RF band limit must be less than the upper limit.');
end

if any(noise_bands_rf_mhz(:, 2) * 1e6 >= lnb_lo_hz)
    error('RF bands must be below the LO frequency for RF = LO - IF conversion.');
end

% Convert RF bands to IF; band-edge order is reversed.
lnb_lo_mhz = lnb_lo_hz / 1e6;

noise_bands_mhz = [
    lnb_lo_mhz - noise_bands_rf_mhz(:, 2), ...
    lnb_lo_mhz - noise_bands_rf_mhz(:, 1)
];

% Verify that each band is fully within the recorded frequency range
record_if_low_mhz = (fc - fs/2) / 1e6;
record_if_high_mhz = (fc + fs/2) / 1e6;

if any(noise_bands_mhz(:, 1) < record_if_low_mhz | ...
       noise_bands_mhz(:, 2) > record_if_high_mhz)
    error('At least one noise band is outside the recorded frequency range.');
end

fprintf('Recording center: IF %.6f MHz -> RF %.6f MHz.\n', ...
    fc / 1e6, fc_rf_hz / 1e6);

disp('RF noise bands [MHz]:');
disp(noise_bands_rf_mhz);

disp('Corresponding IF noise bands [MHz]:');
disp(noise_bands_mhz);

% Results output directory
output_dir = 'C:\Users\m_dolejs\Desktop\PASMO_C_ANALYZA\vystupy\noise_analyze_1809_2409';

chunk_duration = 5.0;   % Duration of each chunk in seconds
start_offset_s = 5.0;   % Analysis offset in seconds from the start of each file
num_chunks = 10;        % Number of analyzed chunks per file

% Validate settings
validateattributes(start_offset_s, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'nonnegative'});

validateattributes(num_chunks, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});

num_complex_samples = round(fs * chunk_duration);
values_per_chunk = 2 * num_complex_samples;

fprintf('Analyzing the interval from %.3f to %.3f s in each file.\n', ...
    start_offset_s, start_offset_s + num_chunks * chunk_duration);

window_length = 8192;               
noverlap = window_length / 2;       
nfft = 8192;
iq_scale = 32767;   % Recorder: clip(CF32,-1,1)*32767 -> int16
reference_power = 1; % A complex tone with |IQ|=1 has a total power of 0 dBFS                        

if test_mode
    file_limit = max_test_files;
    disp(['--- TEST MODE (Limit: ', num2str(file_limit), ' files per site) ---']);
else
    file_limit = Inf; 
    disp('--- FULL MODE (Analyze all data in the specified period) ---');
end

% Track elapsed time
total_time_timer = tic;

%% 3. RUN ANALYSIS FOR BOTH SITES
disp('=== Starting CITY analysis ===');
timetable_city = analyze_noise( ...
    dir_city, days_to_process, values_per_chunk, num_chunks, ...
    fs, fc, window_length, noverlap, nfft, file_limit, ...
    noise_bands_mhz, start_offset_s, iq_scale, reference_power);

disp('=== Starting VILLAGE analysis ===');
timetable_village = analyze_noise( ...
    dir_village, days_to_process, values_per_chunk, num_chunks, ...
    fs, fc, window_length, noverlap, nfft, file_limit, ...
    noise_bands_mhz, start_offset_s, iq_scale, reference_power);

%% SAVE NOISE BACKGROUND FOR SUBSEQUENT SNR ANALYSIS

if ~isfolder(output_dir)
    mkdir(output_dir);
end

noise_results = struct();
% Dataset schema: structure and column names ensure compatibility with downstream scripts.
noise_results.format_version = 1;
noise_results.schema_name = 'iq_analysis_results';
noise_results.schema_version = 1;
noise_results.analysis_type = 'noise_statistics';
noise_results.analysis_name = 'Median and standard deviation of noise background levels';
noise_results.created_at = datetime('now');

% Requested period; the end boundary is exclusive
noise_results.metadata.analysis_start = analysis_start_date;
noise_results.metadata.analysis_end_exclusive = ...
    analysis_end_date + caldays(1);

% Recording and analysis parameters
noise_results.metadata.sample_rate_hz = fs;
noise_results.metadata.lnb_lo_hz = lnb_lo_hz;
noise_results.metadata.frequency_conversion = 'RF = LO - IF';

% These fields specify IF values used by the SNR script.
noise_results.metadata.center_frequency_hz = fc;
noise_results.metadata.noise_bands_mhz = noise_bands_mhz;

% Explicitly labeled IF and RF frequencies
noise_results.metadata.center_frequency_if_hz = fc;
noise_results.metadata.center_frequency_rf_hz = fc_rf_hz;
noise_results.metadata.noise_bands_if_mhz = noise_bands_mhz;
noise_results.metadata.noise_bands_rf_mhz = noise_bands_rf_mhz;

noise_results.metadata.chunk_duration_s = chunk_duration;
noise_results.metadata.chunks_per_file = num_chunks;

noise_results.metadata.window_type = 'Kaiser';
noise_results.metadata.window_beta = 5;
noise_results.metadata.window_length = window_length;
noise_results.metadata.overlap_samples = noverlap;
noise_results.metadata.nfft = nfft;

noise_results.metadata.iq_format = ...
    'Interleaved int16 I,Q; normalized by 32767';

noise_results.metadata.normalization_mode = 'mean_bin_dbfs_v1';
noise_results.metadata.iq_scale = iq_scale;
noise_results.metadata.reference_power = reference_power;
noise_results.metadata.power_reference = 'Recorder scale; complex constant-envelope tone |IQ|=1 -> 0 dBFS total power';
noise_results.metadata.adc_full_scale_verified = false;
noise_results.metadata.window_energy = sum(abs(kaiser(window_length,5)).^2);
noise_results.metadata.bin_width_hz = fs/nfft;
noise_results.metadata.spectral_quantity = 'Two-sided PSD multiplied by FFT bin width';
noise_results.metadata.noise_definition = ...
    'Median over time of 10*log10(mean(abs(STFT).^2/(nfft*window_energy) over selected bins)/reference_power)';

noise_results.metadata.noise_units = ...
    'dBFS mean FFT-bin power, recorder reference; not dBFS/Hz';

noise_results.metadata.time_reference = ...
    'Chunk start; file start time parsed from filename';

noise_results.metadata.test_mode = test_mode;
noise_results.metadata.file_limit_per_location = file_limit;

% Definitions of the stored metrics
noise_results.metadata.metric_names = {'Median_Noise_dB', 'Noise_Std_dB'};
noise_results.metadata.metric_units = {'dBFS', 'dB'};
noise_results.metadata.metric_definitions = {
    'Median of mean normalized FFT-bin power expressed in dBFS relative to recorder scale';
    'Sample standard deviation over time of that same dB series (MATLAB std flag 0)'
};
noise_results.metadata.noise_std_normalization = 'N-1';
noise_results.metadata.actual_chunk_duration_s = num_complex_samples / fs;
noise_results.metadata.timestamp_timezone = ...
    'Unspecified; filename time preserved without timezone conversion';
noise_results.metadata.row_time_definition = 'Start of analyzed chunk';

%Offset parameters
noise_results.metadata.requested_start_offset_s = start_offset_s;

noise_results.metadata.actual_start_offset_s = ...
    round(start_offset_s * fs) / fs;

noise_results.metadata.requested_end_offset_s = ...
    noise_results.metadata.actual_start_offset_s + ...
    num_chunks * num_complex_samples / fs;

% Results for each site
% Actual processed timestamps are stored in the timetables.
noise_results.city.source_directory = dir_city;
noise_results.city.data = timetable_city;
noise_results.city.coverage = describe_coverage( ...
    timetable_city, num_complex_samples / fs);

noise_results.village.source_directory = dir_village;
noise_results.village.data = timetable_village;
noise_results.village.coverage = describe_coverage( ...
    timetable_village, num_complex_samples / fs);

% The output filename includes the period and selected frequency bands
bands_label = arrayfun(@(k) sprintf('RF%g-%gMHz', ...
    noise_bands_rf_mhz(k, 1), noise_bands_rf_mhz(k, 2)), ...
    1:size(noise_bands_rf_mhz, 1), 'UniformOutput', false);

mode_label = 'FULL';
if test_mode
    mode_label = 'TEST';
end

% Unique run identifiers prevent overwriting results from repeated runs.
run_id = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
noise_results.run_id = run_id;

output_filename = sprintf('NoiseDBFS_%s_%s_%s_offset%gs_%dx%gs_%s_%s.mat', ...
    char(string(analysis_start_date, 'yyyyMMdd')), ...
    char(string(analysis_end_date, 'yyyyMMdd')), ...
    strjoin(bands_label, '_'), ...
    start_offset_s, num_chunks, chunk_duration, mode_label, run_id);

output_path = fullfile(output_dir, output_filename);

% Elapsed analysis time recorded before saving and subsequent plotting
noise_results.metadata.analysis_elapsed_s = toc(total_time_timer);
save(output_path, 'noise_results', '-v7.3');

fprintf('Noise analysis results saved to:\n%s\n', output_path);

if isempty(timetable_city) && isempty(timetable_village)
    warning(['No data were processed. ', ...
             'The saved file contains empty results.']);
    return;
end
%% 4. PLOT RESULTS
figure('Name', 'Noise background level and stability analysis', 'NumberTitle', 'off', 'Position', [100, 100, 1400, 900]);

% --- Subplot 1: MEDIAN NOISE LEVEL ---
ax1 = subplot(2, 1, 1);
hold on;
if ~isempty(timetable_city)
    plot(timetable_city.Properties.RowTimes, timetable_city.Median_Noise_dB, 'r.', 'MarkerSize', 6, 'DisplayName', 'City (5G)');
end
if ~isempty(timetable_village)
    plot(timetable_village.Properties.RowTimes, timetable_village.Median_Noise_dB, 'b.', 'MarkerSize', 6, 'DisplayName', 'Village (Reference)');
end
hold off;
title('Median noise background level (selected noise-reference bands)');
ylabel('Median mean FFT-bin power (dBFS, recorder scale)');
legend('show', 'Location', 'best');
grid on;
ax1.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm'; 

% --- Subplot 2: STANDARD DEVIATION OF NOISE LEVEL ---
ax2 = subplot(2, 1, 2);
hold on;
if ~isempty(timetable_city)
    plot(timetable_city.Properties.RowTimes, timetable_city.Noise_Std_dB, 'r.', 'MarkerSize', 6, 'DisplayName', 'City (5G)');
end
if ~isempty(timetable_village)
    plot(timetable_village.Properties.RowTimes, timetable_village.Noise_Std_dB, 'b.', 'MarkerSize', 6, 'DisplayName', 'Village (Reference)');
end
hold off;
title('Standard deviation of noise background level (indicator of instability and interference)');
xlabel('Date and time');
ylabel('Standard deviation (dB)'); % Standard deviation of the logarithmic noise-level time series
legend('show', 'Location', 'best');
grid on;
ax2.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';

% Link the X axes for synchronized zooming
linkaxes([ax1, ax2], 'x');

%% 5. REPORT ELAPSED TIME
elapsed_time_s = toc(total_time_timer); 
elapsed_min = floor(elapsed_time_s / 60); 
elapsed_sec = mod(elapsed_time_s, 60);    
fprintf('\n======================================================\n');
fprintf('Total analysis completed in %d minutes and %.1f seconds.\n', elapsed_min, elapsed_sec);
fprintf('======================================================\n\n');


%% --- LOCAL FUNCTIONS FOR DIRECTORY PROCESSING ---
function results = analyze_noise(base_dir, days_list, val_per_chunk, num_chunks, fs, fc, window, noverlap, nfft, max_files, noise_bands_mhz, start_offset_s, iq_scale, reference_power)

    w = kaiser(window,5);
    power_denominator = nfft*sum(abs(w).^2);
    % One complex sample: int16 I + int16 Q = 4 bytes
    start_sample = round(start_offset_s * fs);
    start_byte_offset = start_sample * 4;

    % Actual offset after rounding to a whole sample
    actual_start_offset_s = start_sample / fs;
    
    max_expected_rows = 45000;
    time_array = NaT(max_expected_rows, 1);
    median_array = zeros(max_expected_rows, 1);
    std_array = zeros(max_expected_rows, 1);
    row_idx = 1;
    processed_files_count = 0; 
    
    for d = 1:length(days_list)
        if processed_files_count >= max_files, break; end
        
        day_str = days_list{d};
        day_folder = fullfile(base_dir, day_str);
        
        if ~isfolder(day_folder)
            warning('Directory not found: %s', day_folder);
            continue;
        end
        
        files = dir(fullfile(day_folder, '*.raw'));
        fprintf('Directory %s: found %d files.\n', day_str, length(files));
        
        for f = 1:length(files)
            if processed_files_count >= max_files
                fprintf('Reached the limit of %d files. Stopping processing for this site.\n', max_files);
                break;
            end
            
            filename = files(f).name;
            filepath = fullfile(day_folder, filename);
            
            parts = split(filename, '_');
            if length(parts) < 3, continue; end
            
            time_str = parts{2}; 
            date_str = strrep(parts{3}, '.raw', ''); 
            
            try
                file_dt = datetime([date_str, time_str], 'InputFormat', 'ddMMyyHHmmss');
            catch
                continue; 
            end
            
            fid = fopen(filepath, 'r', 'ieee-le');
            if fid == -1
                continue;
            end

            % Skip data preceding the requested analysis start
            seek_status = fseek(fid, start_byte_offset, 'bof');

            if seek_status ~= 0
                fclose(fid);
                warning('Cannot seek to the requested file offset: %s', filepath);
                continue;
            end
            
            for chunk = 1:num_chunks
                raw_data = fread(fid, val_per_chunk, 'int16');
                if length(raw_data) < val_per_chunk, break; end
                
                iq = complex(raw_data(1:2:end), raw_data(2:2:end)) / iq_scale;
                [s_c, f_c, ~] = spectrogram(iq, w, noverlap, nfft, fs, 'centered');
                f_c_mhz = (f_c + fc) / 1e6;
                
                % Select the noise-reference bands
                % Select frequency bins within the configured bands
                idx_safe = false(size(f_c_mhz));

                for band_idx = 1:size(noise_bands_mhz, 1)
                    idx_safe = idx_safe | ...
                        (f_c_mhz >= noise_bands_mhz(band_idx, 1) & ...
                        f_c_mhz <= noise_bands_mhz(band_idx, 2));
                end

                if ~any(idx_safe)
                    error('The selected noise bands contain no frequency bins.');
                end
                power_lin_c = abs(s_c(idx_safe, :)).^2 / power_denominator;
                
                % Mean across frequency bins in the noise-reference bands (1D time series in dB)
                noise_floor_1d_db = 10*log10(max(mean(power_lin_c, 1)/reference_power, realmin));
                clear raw_data iq s_c power_lin_c;
                
                % --- CALCULATE METRICS FOR THE FIVE-SECOND CHUNK ---
                chunk_median = median(noise_floor_1d_db);
                chunk_std = std(noise_floor_1d_db);
                
                time_array(row_idx) = file_dt + seconds( ...
                    actual_start_offset_s + ...
                    (chunk - 1) * val_per_chunk / (2 * fs));
                median_array(row_idx) = chunk_median;
                std_array(row_idx) = chunk_std;
                row_idx = row_idx + 1;
            end
            fclose(fid);
            processed_files_count = processed_files_count + 1;
        end
    end
    
    if row_idx > 1
        time_array = time_array(1:row_idx-1);
        median_array = median_array(1:row_idx-1);
        std_array = std_array(1:row_idx-1);
        
        % Create a timetable containing both metrics
        results = timetable(time_array, median_array, std_array, ...
            'VariableNames', {'Median_Noise_dB', 'Noise_Std_dB'}); % Metric column names
        results = sortrows(results); 
    else
        % An empty site result uses the same column names and types.
        results = timetable(NaT(0, 1), zeros(0, 1), zeros(0, 1), ...
            'VariableNames', {'Median_Noise_dB', 'Noise_Std_dB'}); 
    end
    results.Properties.DimensionNames{1} = 'Time';
    results.Properties.VariableUnits = {'dBFS', 'dB'};
    results.Properties.VariableDescriptions = {
        'Median of temporal mean FFT-bin power in dBFS (recorder reference)';
        'Sample standard deviation of temporal noise level in dB'
    }.';
end

function coverage = describe_coverage(data, chunk_duration_s)
    % The span between the first and last timestamps does not establish complete measurement coverage.
    coverage.row_count = height(data);
    coverage.first_chunk_start = NaT;
    coverage.last_chunk_start = NaT;
    coverage.last_chunk_end_exclusive = NaT;
    coverage.finite_median_count = nnz(isfinite(data.Median_Noise_dB));
    coverage.finite_std_count = nnz(isfinite(data.Noise_Std_dB));
    coverage.unique_timestamp_count = numel(unique(data.Properties.RowTimes));
    coverage.duplicate_timestamp_count = ...
        height(data) - coverage.unique_timestamp_count;
    if ~isempty(data)
        coverage.first_chunk_start = min(data.Properties.RowTimes);
        coverage.last_chunk_start = max(data.Properties.RowTimes);
        coverage.last_chunk_end_exclusive = ...
            coverage.last_chunk_start + seconds(chunk_duration_s);
    end
end