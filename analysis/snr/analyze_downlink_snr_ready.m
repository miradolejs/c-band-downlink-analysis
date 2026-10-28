% Downlink SNR from RAW IQ and previously saved median noise levels.
% MATLAB R2020b + Signal Processing Toolbox.
% RF = LO - IF (LNB local oscillator above the received C-band frequencies).
clear; clc; close all;

%% 1. SETTINGS
% An empty path opens a dialog to select the noise dataset.
% Alternatively, specify the absolute path to the corresponding noise MAT file.
noise_file = 'C:\Users\m_dolejs\Desktop\PASMO_C_ANALYZA\vystupy\noise_analyze_1809_2409\NoiseDBFS_20260918_20260924_RF3836.5-3837.5MHz_offset5s_10x5s_FULL_20261016_021536_715.mat';
dir_city = 'D:\iq_data\mesto_1_1809_2409_2026';
dir_village = 'D:\iq_data\vesnice_1_1809_2409_2026';
output_dir = 'C:\Users\m_dolejs\Desktop\PASMO_C_ANALYZA\vystupy\SNR_1809_2409';

fc = 1312e6;       % Recording center frequency at the LNB output (IF), in Hz
lnb_lo_hz = 5.15e9;  % LNB local oscillator frequency

% Any number of rows: [RF center frequency in MHz, integration bandwidth in MHz].
% Configure the bands below. Additional syntax example:
% downlink_bands_rf_mhz = [3870.0, 0.8; 3869.0, 0.6];
downlink_bands_rf_mhz = [
    3839, 1;
    3842, 0.5
];

batch_windows = 256; % Number of short STFT windows processed per batch
save_figures = true; % Save PNG and editable MATLAB FIG files

%% 2. NOISE DATASET AND VALIDATION
if isempty(noise_file)
    [name, folder] = uigetfile('*.mat', 'Select the median noise dataset');
    if isequal(name, 0), disp('Selection canceled.'); return; end
    noise_file = fullfile(folder, name);
end
timer_all = tic;
assert(isfile(noise_file), 'Median noise file does not exist: %s', noise_file);
loaded = load(noise_file, 'noise_results');
assert(isfield(loaded, 'noise_results'), 'The file does not contain noise_results.');
noise_results = loaded.noise_results;
m = noise_results.metadata;
assert(noise_results.format_version == 1, 'Unsupported noise dataset version.');
assert(~isempty(downlink_bands_rf_mhz) && size(downlink_bands_rf_mhz, 2) == 2, ...
    'Set downlink_bands_rf_mhz: each row is [RF center in MHz, bandwidth in MHz].');
validateattributes(downlink_bands_rf_mhz, {'numeric'}, ...
    {'2d', 'real', 'finite', 'positive'});
validateattributes(batch_windows, {'numeric'}, ...
    {'scalar', 'integer', 'positive', 'finite'});
assert(fc == m.center_frequency_hz, ...
    'fc (IF) must match center_frequency_hz in the noise dataset.');
if isfield(m, 'lnb_lo_hz')
    assert(lnb_lo_hz == m.lnb_lo_hz, ...
        'The LNB LO does not match the noise dataset.');
end
if isfield(m, 'frequency_conversion')
    assert(strcmp(m.frequency_conversion, 'RF = LO - IF'), ...
        'The noise dataset uses a different RF/IF conversion.');
end
if isfield(noise_results, 'analysis_type')
    assert(strcmp(noise_results.analysis_type, 'noise_statistics'), ...
        'The selected dataset does not contain noise background statistics.');
end
assert(strcmp(m.window_type, 'Kaiser'), 'A Kaiser window is required.');
is_dbfs_noise = isfield(m,'normalization_mode') && ...
    strcmp(m.normalization_mode,'mean_bin_dbfs_v1');
if is_dbfs_noise
    assert(strcmp(m.iq_format,'Interleaved int16 I,Q; normalized by 32767') && ...
        m.iq_scale == 32767 && m.reference_power == 1, ...
        'Unexpected power reference definition in the dBFS dataset.');
elseif ~isfield(m,'normalization_mode')
    assert(strcmp(m.iq_format,'Interleaved int16 I,Q; normalized by 32768') && ...
        strcmp(m.noise_units,'dB of unnormalized STFT bin power; not dBm or dB/Hz'), ...
        'Unknown legacy noise power format.');
else
    error('Unsupported noise normalization; power values cannot be combined consistently.');
end
assert(isfield(m, 'actual_start_offset_s'), ...
    'The noise dataset must contain actual_start_offset_s.');

cfg.fs = m.sample_rate_hz;
cfg.fc = fc;
cfg.lo = lnb_lo_hz;
cfg.window = kaiser(m.window_length, m.window_beta);
cfg.overlap = m.overlap_samples;
cfg.nfft = m.nfft;
if is_dbfs_noise
    cfg.iq_scale = m.iq_scale;
    cfg.reference_power = m.reference_power;
    cfg.power_denominator = cfg.nfft*sum(abs(cfg.window).^2);
    assert(abs(sum(abs(cfg.window).^2)-m.window_energy) <= 1e-10*m.window_energy, ...
        'Window energy does not match the noise dataset normalization.');
    power_unit = 'normalized power';
else
    cfg.iq_scale = 32768;
    cfg.reference_power = 1;
    cfg.power_denominator = 1;
    power_unit = 'relative bin power';
end
cfg.chunk_samples = round(m.chunk_duration_s * cfg.fs);
cfg.offset_samples = round(m.actual_start_offset_s * cfg.fs);
cfg.num_chunks = m.chunks_per_file;
cfg.batch_windows = batch_windows;
assert(cfg.chunk_samples >= numel(cfg.window), 'The chunk is shorter than the STFT window.');
assert(cfg.overlap >= 0 && cfg.overlap < numel(cfg.window), 'Invalid overlap.');
assert(mod(cfg.nfft, 2) == 0 && cfg.nfft >= numel(cfg.window), ...
    'The script requires an even nfft greater than or equal to the window length.');

rf_center = downlink_bands_rf_mhz(:, 1) * 1e6;
bw = downlink_bands_rf_mhz(:, 2) * 1e6;
rf_low = rf_center - bw/2;
rf_high = rf_center + bw/2;
if_center = lnb_lo_hz - rf_center;
if_low = lnb_lo_hz - rf_high; % Band-edge order is reversed.
if_high = lnb_lo_hz - rf_low;
assert(all(rf_low > 0 & rf_high < lnb_lo_hz), ...
    'RF bands must be positive and below the LO for RF = LO - IF conversion.');
assert(all(if_low >= fc-cfg.fs/2 & if_high <= fc+cfg.fs/2), ...
    'At least one band is not fully within the recorded IF range.');

% Use frequencies returned by spectrogram, including its Nyquist convention.
[~, cfg.baseband_f] = spectrogram(complex(ones(numel(cfg.window),1)), ...
    cfg.window, cfg.overlap, cfg.nfft, cfg.fs, 'centered');
f_if = fc + cfg.baseband_f;
nb = size(downlink_bands_rf_mhz, 1);
cfg.band_masks = cell(nb, 1);
bin_count = zeros(nb, 1);
for b = 1:nb
    cfg.band_masks{b} = f_if >= if_low(b) & f_if <= if_high(b);
    bin_count(b) = nnz(cfg.band_masks{b});
    assert(bin_count(b) > 0, 'Band %d contains no FFT bins.', b);
    for n = 1:size(m.noise_bands_mhz, 1)
        if if_low(b) <= m.noise_bands_mhz(n,2)*1e6 && ...
                if_high(b) >= m.noise_bands_mhz(n,1)*1e6
            warning('Band %d overlaps a band used for noise estimation.', b);
        end
    end
end
bands = table((1:nb).', rf_center/1e6, bw/1e6, rf_low/1e6, rf_high/1e6, ...
    if_center/1e6, if_low/1e6, if_high/1e6, bin_count, ...
    bin_count*cfg.fs/cfg.nfft, ...
    'VariableNames', {'Band_ID','RF_Center_MHz','Bandwidth_MHz', ...
    'RF_Low_MHz','RF_High_MHz','IF_Center_MHz','IF_Low_MHz', ...
    'IF_High_MHz','Bin_Count','Selected_Bin_Width_Hz'});
disp(bands);
fprintf('Recording center: IF %.6f MHz -> RF %.6f MHz.\n', ...
    fc/1e6, (lnb_lo_hz-fc)/1e6);

%% 3. ANALYSIS OF BOTH SITES
city = analyze_location(dir_city, noise_results.city.data, m, cfg);
village = analyze_location(dir_village, noise_results.village.data, m, cfg);

%% 4. SAVE RESULTS
if ~isfolder(output_dir), mkdir(output_dir); end
snr_results = struct();
snr_results.format_version = 1;
snr_results.schema_name = 'iq_analysis_results';
snr_results.schema_version = 1;
snr_results.analysis_type = 'downlink_snr';
snr_results.analysis_name = 'Satellite downlink SNR estimation';
snr_results.created_at = datetime('now');
snr_results.metadata.noise_file = noise_file;
snr_results.metadata.noise_metadata = m;
snr_results.metadata.lnb_lo_hz = lnb_lo_hz;
snr_results.metadata.frequency_conversion = 'RF = LO - IF';
snr_results.metadata.record_center_if_hz = fc;
snr_results.metadata.record_center_rf_hz = lnb_lo_hz-fc;
snr_results.metadata.bands = bands;
snr_results.metadata.snr_definition = ...
    '10*log10((median_over_time(sum_bin_power)-N)/N), N=K*reference_power*10^(noise_median_dB/10)';
snr_results.metadata.assumption = ...
    'Noise reference bin power represents noise in each downlink band; other in-band interference is not separated.';
snr_results.metadata.invalid_policy = ...
    'Nonpositive estimated signal power -> NaN SNR; no clipping or omission before power median.';
snr_results.metadata.batch_windows = batch_windows;
snr_results.metadata.iq_scale = cfg.iq_scale;
snr_results.metadata.reference_power = cfg.reference_power;
snr_results.metadata.spectral_power_denominator = cfg.power_denominator;
snr_results.metadata.input_noise_normalized_dbfs = is_dbfs_noise;
snr_results.metadata.row_time_definition = 'Start of analyzed chunk';
snr_results.metadata.timestamp_timezone = ...
    'Unspecified; filename time preserved without timezone conversion';
snr_results.metadata.actual_chunk_duration_s = cfg.chunk_samples / cfg.fs;
snr_results.metadata.band_column_definition = ...
    'Column b of each numeric metric corresponds to row b of metadata.bands';
snr_results.metadata.metric_names = {'SNR_dB','Median_Total_BinPower', ...
    'Estimated_Noise_BinPower','Estimated_Signal_BinPower', ...
    'Fraction_Windows_Above_Noise'};
snr_results.metadata.metric_units = {'dB',power_unit,power_unit,power_unit,'dimensionless'};
snr_results.metadata.status_values = ...
    {'processed','missing_raw','open_error','short_raw','read_error'};
snr_results.metadata.status_definition = ...
    'processed confirms RAW processing; a band SNR can still be NaN';
snr_results.city.source_directory = dir_city;
snr_results.city.data = city;
snr_results.village.source_directory = dir_village;
snr_results.village.data = village;
snr_results.metadata.elapsed_seconds = toc(timer_all);

% Unique run identifier prevents overwriting results from analyses with different bands.
run_label = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
snr_results.run_id = run_label;
stem = sprintf('SNR_%s_%s_%dbands_%s', ...
    char(string(m.analysis_start, 'yyyyMMdd')), ...
    char(string(m.analysis_end_exclusive-caldays(1), 'yyyyMMdd')), nb, run_label);
save(fullfile(output_dir, [stem '.mat']), 'snr_results', '-v7.3');
fprintf('Saved: %s\n', fullfile(output_dir, [stem '.mat']));

%% 5. ONE PLOT PER BAND
for b = 1:nb
    fig = figure('Name', sprintf('SNR band %d', b), ...
        'NumberTitle', 'off', 'Position', [100 100 1400 600]);
    ax = axes(fig); hold(ax, 'on');
    plot(ax, city.Properties.RowTimes, city.SNR_dB(:,b), ...
        'r.-', 'MarkerSize', 5, 'DisplayName', 'City');
    plot(ax, village.Properties.RowTimes, village.SNR_dB(:,b), ...
        'b.-', 'MarkerSize', 5, 'DisplayName', 'Village');
    title(ax, sprintf('Estimated SNR: RF %.6f MHz, bandwidth %.6f MHz', ...
        bands.RF_Center_MHz(b), bands.Bandwidth_MHz(b)));
    xlabel(ax, 'Date and time'); ylabel(ax, 'SNR (dB)');
    legend(ax, 'show', 'Location', 'best'); grid(ax, 'on');
    if ~isempty(city) || ~isempty(village)
        ax.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';
    end
    if save_figures
        figure_stem = fullfile(output_dir, sprintf('%s_band%02d', stem, b));
        savefig(fig, [figure_stem '.fig']);
        exportgraphics(ax, [figure_stem '.png'], 'Resolution', 150);
    end
end
fprintf('Completed in %.1f minutes.\n', toc(timer_all)/60);

%% LOCAL FUNCTIONS
function out = analyze_location(base_dir, noise_tt, meta, cfg)
    nb = numel(cfg.band_masks);
    times = noise_tt.Properties.RowTimes;
    assert(~any(isnat(times)), 'The noise dataset contains NaT timestamps.');
    assert(numel(unique(times)) == numel(times), ...
        'Duplicate noise timestamps prevent unique RAW chunk matching.');
    nr = numel(times);
    snr = nan(nr, nb); total = nan(nr, nb);
    noise = nan(nr, nb); signal = nan(nr, nb);
    fraction = nan(nr, nb);
    source = strings(nr, 1); status = repmat("missing_raw", nr, 1);
    seen = false(nr, 1);
    if nr > 0
        assert(ismember('Median_Noise_dB', noise_tt.Properties.VariableNames), ...
            'The Median_Noise_dB column is missing.');
        noise = cfg.reference_power * 10.^(noise_tt.Median_Noise_dB/10) * ...
            cellfun(@nnz, cfg.band_masks).';
    end
    days = meta.analysis_start:caldays(1):meta.analysis_end_exclusive-caldays(1);
    fprintf('\nSite %s: %d reference chunks.\n', base_dir, nr);
    for day = days
        folder = fullfile(base_dir, char(string(day, 'ddMMyy')));
        if ~isfolder(folder), warning('Missing directory: %s', folder); continue; end
        files = dir(fullfile(folder, '*.raw'));
        for fi = 1:numel(files)
            tok = regexp(files(fi).name, '^\d+_(\d{6})_(\d{6})\.raw$', 'tokens', 'once');
            if isempty(tok), continue; end
            try
                file_time = datetime([tok{2} tok{1}], 'InputFormat', 'ddMMyyHHmmss');
            catch
                continue;
            end
            chunk_times = file_time + seconds(cfg.offset_samples/cfg.fs + ...
                (0:cfg.num_chunks-1).' * cfg.chunk_samples/cfg.fs);
            [matched, row] = ismember(chunk_times, times);
            if ~any(matched), continue; end
            path = fullfile(folder, files(fi).name);
            assert(~any(seen(row(matched))), ...
                'Multiple RAW files match the same reference timestamp: %s', path);
            seen(row(matched)) = true;
            fid = fopen(path, 'r', 'ieee-le');
            if fid < 0
                status(row(matched)) = "open_error";
                warning('Cannot open file: %s', path); continue;
            end
            file_guard = onCleanup(@() fclose(fid));
            for chunk = find(matched).'
                r = row(chunk); source(r) = string(path);
                first_sample = cfg.offset_samples + (chunk-1)*cfg.chunk_samples;
                if files(fi).bytes < 4*(first_sample+cfg.chunk_samples)
                    status(r) = "short_raw"; continue;
                end
                [power_time, ok] = read_band_power(fid, first_sample, cfg);
                if ~ok, status(r) = "read_error"; continue; end
                % Median over ALL short windows, before noise subtraction.
                % Retain windows below the estimated noise level to avoid upward bias.
                total(r,:) = median(power_time, 1);
                signal(r,:) = total(r,:) - noise(r,:);
                valid = isfinite(noise(r,:)) & noise(r,:) > 0 & ...
                    isfinite(signal(r,:)) & signal(r,:) > 0;
                snr(r,valid) = 10*log10(signal(r,valid)./noise(r,valid));
                fraction(r,:) = mean(bsxfun(@gt, power_time, noise(r,:)), 1);
                fraction(r,~isfinite(noise(r,:)) | noise(r,:) <= 0) = NaN;
                status(r) = "processed";
            end
            clear file_guard;
            fprintf('%s: processed %d/%d chunks.\n', files(fi).name, ...
                nnz(status == "processed"), nr);
        end
    end
    out = timetable(times, snr, total, noise, signal, fraction, source, status, ...
        'VariableNames', {'SNR_dB','Median_Total_BinPower', ...
        'Estimated_Noise_BinPower','Estimated_Signal_BinPower', ...
        'Fraction_Windows_Above_Noise','Source_File','Status'});
    out.Properties.DimensionNames{1} = 'Time';
    if cfg.power_denominator == 1, unit = 'relative bin power';
    else, unit = 'normalized power'; end
    out.Properties.VariableUnits = {'dB',unit,unit,unit,'dimensionless','',''};
    out = sortrows(out);
    fprintf('Processed %d/%d chunks; %d finite SNR values.\n', ...
        nnz(status == "processed"), nr, nnz(isfinite(snr)));
end

function [power_time, ok] = read_band_power(fid, first_sample, cfg)
    L = numel(cfg.window); hop = L-cfg.overlap;
    nw = floor((cfg.chunk_samples-L)/hop)+1;
    power_time = nan(nw, numel(cfg.band_masks));
    ok = false;
    for first_window = 1:cfg.batch_windows:nw
        count = min(cfg.batch_windows, nw-first_window+1);
        sample = first_sample + (first_window-1)*hop;
        if fseek(fid, 4*sample, 'bof') ~= 0, return; end
        needed = L + (count-1)*hop;
        raw = fread(fid, 2*needed, 'int16');
        if numel(raw) ~= 2*needed, return; end
        iq = complex(raw(1:2:end), raw(2:2:end))/cfg.iq_scale;
        [s, f] = spectrogram(iq, cfg.window, cfg.overlap, ...
            cfg.nfft, cfg.fs, 'centered');
        assert(size(s,2) == count, 'Unexpected number of STFT windows.');
        assert(max(abs(f-cfg.baseband_f)) < cfg.fs/cfg.nfft*1e-6, ...
            'Unexpected frequency-bin ordering returned by spectrogram.');
        for b = 1:numel(cfg.band_masks)
            power_time(first_window:first_window+count-1,b) = ...
                sum(abs(s(cfg.band_masks{b},:)).^2, 1).' / cfg.power_denominator;
        end
    end
    ok = true;
end