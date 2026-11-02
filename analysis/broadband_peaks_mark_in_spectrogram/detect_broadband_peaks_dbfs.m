% Peak detection in RF noise bands; dBFS relative to the recorder scale.
% MATLAB R2020b + Signal Processing Toolbox.
% Reference: P_FS = 1; a complex tone with |IQ| = 1 has a total power of 0 dBFS.
% The spectrogram shows bin power (PSD*df), rather than power spectral density.
clear; clc;

%% 1. PARAMETERS
file_recorded = 'D:\iq_data\vesnice_1_1809_2409_2026\200926\410_193000_200926.raw';
fs = 10e6;
fc = 1312e6;        % IF center frequency after LNB conversion
f_lo = 5150e6;
t_read = 5.0;
start_sec = 0;
noise_bands_rf_mhz = [3836.5, 3837.5]; % [lower RF limit, upper RF limit] MHz

iq_scale = 32767;   % Recorder: clip(CF32,-1,1)*32767 -> int16
reference_power = 1;
window_length = 8192;
noverlap = window_length/2;
nfft = 8192;
window_beta = 5;
min_peak_distance_bins = 3; % STFT time bins, not IQ samples

% [] converts legacy_threshold_db to the mean FFT-bin power scale in dBFS.
% Alternatively, specify the mean bin power threshold directly in dBFS.
threshold_dbfs = [];
legacy_threshold_db = -24;
legacy_iq_scale = 32768;

validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(start_sec,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(t_read,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(noise_bands_rf_mhz,{'numeric'}, ...
    {'2d','real','finite','positive','nonempty'});
assert(size(noise_bands_rf_mhz,2)==2 && ...
    all(noise_bands_rf_mhz(:,1)<noise_bands_rf_mhz(:,2)), ...
    'Each band must have a lower limit smaller than its upper limit.');
rf_low_mhz = (f_lo-fc-fs/2)/1e6;
rf_high_mhz = (f_lo-fc+fs/2)/1e6;
assert(all(noise_bands_rf_mhz(:,1)>=rf_low_mhz & ...
    noise_bands_rf_mhz(:,2)<=rf_high_mhz), 'The RF band lies outside the recorded frequency range.');

num_complex_samples = round(fs*t_read);
start_sample = round(start_sec*fs);
actual_start_sec = start_sample/fs;
assert(num_complex_samples >= window_length,'The segment is shorter than the STFT window.');
w = kaiser(window_length,window_beta);
window_energy = sum(abs(w).^2);
df_hz = fs/nfft;

if isempty(threshold_dbfs)
    % Legacy power definition: |STFT(IQ/32768)|^2.
    % Normalized bin power: |STFT(IQ/32767)|^2 / (nfft*sum(w.^2)).
    threshold_dbfs = legacy_threshold_db + ...
        20*log10(legacy_iq_scale/iq_scale) - ...
        10*log10(nfft*window_energy*reference_power);
end
validateattributes(threshold_dbfs,{'numeric'},{'scalar','real','finite'});
fprintf('Mean FFT-bin power threshold: %.6f dBFS.\n',threshold_dbfs);
fprintf('FFT bin width: %.6f Hz; minimum peak separation: %.6f ms.\n', ...
    df_hz,1000*min_peak_distance_bins*(window_length-noverlap)/fs);

%% 2. RECORDING TIMESTAMP
[~,name,~] = fileparts(file_recorded);
parts = split(name,'_');
dt_title_str = 'Unknown time';
if numel(parts)>=3
    try
        record_dt = datetime([parts{3},parts{2}],'InputFormat','ddMMyyHHmmss');
        analyzed_dt = record_dt+seconds(actual_start_sec);
        dt_title_str = char(string(analyzed_dt,'dd.MM.yyyy HH:mm:ss'));
    catch
        warning('Could not determine the timestamp from the filename.');
    end
end

%% 3. LOAD IQ DATA
disp('Loading data...');
% Station RAW recordings use little-endian int16 values in interleaved I,Q order.
raw = read_iq_values(file_recorded,4*start_sample,2*num_complex_samples);
endpoint_fraction = nnz(abs(raw)>=iq_scale)/numel(raw);
fprintf('Fraction of components at the recorder scale endpoints: %.6f %% (does not establish clipping).\n', ...
    100*endpoint_fraction);
iq_recorded = complex(raw(1:2:end),raw(2:2:end))/iq_scale;
clear raw;

%% 4. NORMALIZED SPECTROGRAM
disp('Computing spectrogram...');
[stft_values,f_if_hz,t_stft] = spectrogram(iq_recorded,w,noverlap,nfft,fs,'centered');
clear iq_recorded;
f_rf_mhz = (f_lo-(fc+f_if_hz))/1e6;

% The two-sided PSD of complex IQ data is |S|^2/(fs*sum(w.^2)).
% Integrating over one bin by multiplying by df=fs/nfft gives:
power_bin = abs(stft_values).^2/(nfft*window_energy);
clear stft_values;
power_bin_dbfs = 10*log10(max(power_bin/reference_power,realmin));

%% 5. MEAN BIN POWER IN SELECTED RF NOISE BANDS
idx_safe = false(size(f_rf_mhz));
for b = 1:size(noise_bands_rf_mhz,1)
    band_mask = f_rf_mhz>=noise_bands_rf_mhz(b,1) & ...
                f_rf_mhz<=noise_bands_rf_mhz(b,2);
    assert(any(band_mask),'RF band %d contains no frequency bins.',b);
    idx_safe = idx_safe | band_mask;
end
noise_floor_1d_lin = mean(power_bin(idx_safe,:),1);
noise_floor_1d_dbfs = 10*log10(max(noise_floor_1d_lin/reference_power,realmin));

% Additional workspace quantity: total power across all selected bins.
% The detector uses mean bin power; this total is provided for reference.
total_safe_band_power_dbfs = ...
    10*log10(max(sum(power_bin(idx_safe,:),1)/reference_power,realmin));
clear power_bin;

%% 6. PEAK DETECTION
if max(noise_floor_1d_dbfs)<threshold_dbfs
    peak_vals = []; peak_locs = [];
else
    [peak_vals,peak_locs] = findpeaks(noise_floor_1d_dbfs, ...
        'MinPeakHeight',threshold_dbfs,'MinPeakDistance',min_peak_distance_bins);
end
time_of_peaks = t_stft(peak_locs)+actual_start_sec;
fprintf('Peaks detected: %d\n',numel(peak_locs));

% Store normalization parameters in the workspace for reproducibility.
normalization.iq_scale = iq_scale;
normalization.reference_power = reference_power;
normalization.reference = 'Recorder scale; complex constant-envelope tone |IQ|=1 -> 0 dBFS total power';
normalization.adc_full_scale_verified = false;
normalization.spectral_quantity = 'Two-sided PSD multiplied by FFT bin width';
normalization.detector_quantity = 'Mean bin power over union of selected RF bands';
normalization.window_energy = window_energy;
normalization.nfft = nfft;
normalization.bin_width_hz = df_hz;
normalization.threshold_dbfs = threshold_dbfs;

%% 7. PLOTS
figure('Name',['Peak detection: ' dt_title_str],'NumberTitle','off', ...
    'Position',[100 100 1200 850]);
sgtitle(sprintf('Broadband pulse detection | Recording time: %s',dt_title_str));
ax1 = subplot(2,1,1);
imagesc(t_stft+actual_start_sec,flipud(f_rf_mhz),flipud(power_bin_dbfs));
axis xy; colormap('turbo');
c = colorbar; c.Label.String = 'Power per FFT bin (dBFS, recorder reference)';
% Set color limits from the 2nd and 99.5th percentiles of the spectrogram values.
sorted_power = sort(power_bin_dbfs(:));
min_c = sorted_power(max(1,round(0.02*numel(sorted_power))));
max_c = sorted_power(min(numel(sorted_power),max(1,round(0.995*numel(sorted_power)))));
if max_c<=min_c, min_c=min_c-1; max_c=max_c+1; end
caxis([min_c max_c]); clear sorted_power;
title('Spectrogram'); xlabel('Time from recording start (s)'); ylabel('RF frequency (MHz)');
hold on;
if ~isempty(time_of_peaks)
    marker_y = max(f_rf_mhz)-0.5;
    plot(time_of_peaks,repmat(marker_y,size(time_of_peaks)),'mv', ...
        'MarkerFaceColor','m','MarkerSize',10);
end
hold off;

ax2 = subplot(2,1,2);
plot(t_stft+actual_start_sec,noise_floor_1d_dbfs,'b-','LineWidth',1); hold on;
yline(threshold_dbfs,'r--','Detection threshold','LineWidth',1.5);
plot(time_of_peaks,peak_vals,'ro','MarkerFaceColor','r','MarkerSize',5); hold off;
title('Mean FFT-bin power in selected RF bands');
xlabel('Time from recording start (s)'); ylabel('Mean bin power (dBFS, recorder reference)');
grid on; xlim([min(t_stft+actual_start_sec),max(t_stft+actual_start_sec)]);
linkaxes([ax1 ax2],'x');

function raw = read_iq_values(path,offset_bytes,count)
    fid = fopen(path,'r','ieee-le');
    assert(fid~=-1,'Cannot open file: %s',path);
    guard = onCleanup(@() fclose(fid));
    assert(fseek(fid,offset_bytes,'bof')==0,'Cannot seek to the read start position.');
    raw = fread(fid,count,'int16');
    assert(numel(raw)==count,'The file does not contain the entire requested time segment.');
end
