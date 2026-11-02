% Time-frequency comparison of city and village recordings.
% MATLAB R2020b + Signal Processing Toolbox.
% FFT bin power in dBFS relative to the recorder digital scale, P_FS = 1.
% This convention does not establish the physical ADC full scale.
clear; clc;

%% 1. PARAMETERS
file_village = 'D:\iq_data\vesnice_1_1809_2409_2026\200926\410_193000_200926.raw';
file_city = 'D:\iq_data\mesto_1_1809_2409_2026\200926\410_193000_200926.raw';
fs = 10e6;
fc = 1312e6;       % IF center frequency after LNB conversion: 1312 MHz
f_lo = 5150e6;
t_read = 5.0;
start_sec = 0;

iq_scale = 32767;  % Recorder: clip(CF32,-1,1)*32767 -> int16
reference_power = 1; % Complex tone with |IQ|=1: total power of 0 dBFS
window_length = 8192;
noverlap = window_length/2;
nfft = 8192;
window_beta = 5;

% [] = automatic color scale based on the village data (shared by both plots).
% Specify [minimum maximum] to use the same color scale across different runs.
color_limits_dbfs = [];

validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(start_sec,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(t_read,{'numeric'},{'scalar','real','finite','positive'});
if ~isempty(color_limits_dbfs)
    validateattributes(color_limits_dbfs,{'numeric'},{'vector','numel',2,'real','finite'});
    assert(color_limits_dbfs(1)<color_limits_dbfs(2),'Invalid color scale limits.');
end
num_complex_samples = round(fs*t_read);
start_sample = round(start_sec*fs);
actual_start_sec = start_sample/fs;
assert(num_complex_samples>=window_length,'The segment is shorter than the STFT window.');
w = kaiser(window_length,window_beta);
window_energy = sum(abs(w).^2);

%% 2. TIMESTAMPS OF BOTH FILES
[record_dt_v,dt_title_v] = file_time(file_village,actual_start_sec);
[record_dt_c,dt_title_c] = file_time(file_city,actual_start_sec);
if ~isnat(record_dt_v) && ~isnat(record_dt_c) && record_dt_v~=record_dt_c
    warning('The files have different start times. Plot time axes are relative to the start of each file.');
end

%% 3. VILLAGE - LOADING, NORMALIZATION, SPECTROGRAM
disp('Loading and processing village data...');
[power_db_v,f_v_mhz,t_v] = normalized_spectrogram( ...
    file_village,start_sample,num_complex_samples,iq_scale, ...
    reference_power,w,noverlap,nfft,fs,fc,f_lo);

if isempty(color_limits_dbfs)
    sorted_power = sort(power_db_v(:));
    low = sorted_power(max(1,round(0.02*numel(sorted_power))));
    high = sorted_power(min(numel(sorted_power),max(1,round(0.995*numel(sorted_power)))));
    if high<=low, low=low-1; high=high+1; end
    color_limits_dbfs = [low high];
    clear sorted_power;
end

figure('Name','Spectrogram comparison in dBFS','NumberTitle','off', ...
    'Position',[100 100 1200 850]);
sgtitle('Time-frequency comparison | dBFS relative to recorder scale');
ax1 = subplot(2,1,1);
imagesc(t_v+actual_start_sec,f_v_mhz,power_db_v);
axis xy; colormap('turbo');
c1 = colorbar; c1.Label.String = 'Power per FFT bin (dBFS, recorder reference)';
caxis(color_limits_dbfs);
title(sprintf('Village | Analyzed segment start: %s',dt_title_v));
xlabel('Time from recording start (s)'); ylabel('RF frequency (MHz)');
clear power_db_v;

%% 4. CITY - SAME CALCULATION AND SHARED COLOR SCALE
disp('Loading and processing city data...');
[power_db_c,f_c_mhz,t_c] = normalized_spectrogram( ...
    file_city,start_sample,num_complex_samples,iq_scale, ...
    reference_power,w,noverlap,nfft,fs,fc,f_lo);
ax2 = subplot(2,1,2);
imagesc(t_c+actual_start_sec,f_c_mhz,power_db_c);
axis xy;
c2 = colorbar; c2.Label.String = 'Power per FFT bin (dBFS, recorder reference)';
caxis(color_limits_dbfs);
title(sprintf('City | Analyzed segment start: %s',dt_title_c));
xlabel('Time from recording start (s)'); ylabel('RF frequency (MHz)');
clear power_db_c;
linkaxes([ax1 ax2],'xy');

% Store normalization parameters in the workspace for reproducibility.
normalization.iq_scale = iq_scale;
normalization.reference_power = reference_power;
normalization.reference = 'Recorder scale; complex constant-envelope tone |IQ|=1 -> 0 dBFS total power';
normalization.adc_full_scale_verified = false;
normalization.spectral_quantity = 'Two-sided PSD multiplied by FFT bin width';
normalization.window_energy = window_energy;
normalization.nfft = nfft;
normalization.bin_width_hz = fs/nfft;
normalization.color_limits_dbfs = color_limits_dbfs;
normalization.actual_start_sec = actual_start_sec;
normalization.actual_duration_s = num_complex_samples/fs;
disp('Done. The shared color scale is available in normalization.color_limits_dbfs.');

%% LOCAL FUNCTIONS
function [p_dbfs,f_rf_mhz,t] = normalized_spectrogram( ...
        path,start_sample,count,scale,p_ref,w,overlap,nfft,fs,fc,lo)
    fid = fopen(path,'r','ieee-le');
    assert(fid~=-1,'Cannot open: %s',path);
    guard = onCleanup(@() fclose(fid));
    assert(fseek(fid,4*start_sample,'bof')==0,'Cannot seek to the read start position: %s',path);
    raw = fread(fid,2*count,'int16');
    assert(numel(raw)==2*count,'The file does not contain the entire requested segment: %s',path);
    clear guard;
    endpoint_fraction = nnz(abs(raw)>=scale)/numel(raw);
    fprintf('Fraction of components at the recorder scale endpoints: %.6f %% (does not establish clipping).\n', ...
        100*endpoint_fraction);
    iq = complex(raw(1:2:end),raw(2:2:end))/scale;
    clear raw;
    [s,f,t] = spectrogram(iq,w,overlap,nfft,fs,'centered');
    clear iq;
    % PSD = |S|^2/(fs*sum(w.^2)); bin power = PSD*(fs/nfft).
    p = abs(s).^2/(nfft*sum(abs(w).^2));
    clear s;
    p_dbfs = flipud(10*log10(max(p/p_ref,realmin)));
    f_rf_mhz = flipud((lo-(fc+f))/1e6);
end

function [record_dt,label] = file_time(path,offset_s)
    record_dt = NaT; label = 'Unknown time';
    [~,name,~] = fileparts(path);
    parts = split(name,'_');
    if numel(parts)<3, return; end
    try
        record_dt = datetime([parts{3},parts{2}],'InputFormat','ddMMyyHHmmss');
        label = char(string(record_dt+seconds(offset_s),'dd.MM.yyyy HH:mm:ss'));
    catch
        warning('Cannot determine the timestamp from the filename: %s',path);
    end
end
