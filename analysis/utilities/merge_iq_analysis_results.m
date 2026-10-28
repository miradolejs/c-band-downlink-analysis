% Merge NOISE, SNR, IMPULSE, or TEMPERATURE AND NOISE datasets without reading RAW IQ data.
% MATLAB R2020b. Select only one dataset type per run.
clear; clc; close all;

%% 1. SETTINGS
output_dir = 'D:\iq_analysis_results\Merged';
save_figures = true;

% Empty list -> dialog for selecting multiple MAT files (Ctrl / Shift).
% For files in different folders, specify absolute paths, for example:
% input_files = {'D:\results\part1.mat'; 'F:\results\part2.mat'};
input_files = {};

if isempty(input_files)
    [names, folder] = uigetfile('*.mat', ...
        'Select partial results of one type (NOISE / SNR / IMPULSES / TEMPERATURE)', 'MultiSelect', 'on');
    if isequal(names, 0), disp('Selection canceled.'); return; end
    if ischar(names), names = {names}; end
    input_files = cellfun(@(n) fullfile(folder, n), names, 'UniformOutput', false);
end
input_files = cellstr(string(input_files(:)));
assert(numel(unique(input_files)) == numel(input_files), ...
    'The same input file appears more than once in the list.');

%% 2. LOAD, VALIDATE PARAMETERS, AND COMBINE
parts_city = cell(numel(input_files), 1);
parts_village = parts_city;
input_metadata = parts_city;
source_dirs_city = strings(numel(input_files), 1);
source_dirs_village = source_dirs_city;
starts = NaT(numel(input_files), 1);
ends_exclusive = starts;
summary_file = strings(0,1); summary_location = strings(0,1);
summary_rows = zeros(0,1); summary_first = NaT(0,1); summary_last = NaT(0,1);

for k = 1:numel(input_files)
    path = input_files{k};
    assert(isfile(path), 'Input file does not exist: %s', path);
    content = load(path, 'noise_results', 'snr_results', 'impulse_results', 'temp_noise_results');
    is_noise = isfield(content, 'noise_results');
    is_snr = isfield(content, 'snr_results');
    is_impulse = isfield(content, 'impulse_results');
    is_temp = isfield(content, 'temp_noise_results');
    assert(sum([is_noise is_snr is_impulse is_temp]) == 1, ...
        'The file must contain exactly one supported dataset: %s', path);
    if is_noise
        type = 'noise'; data = content.noise_results;
        base_meta = data.metadata;
    elseif is_impulse
        type = 'impulses'; data = content.impulse_results;
        base_meta = data.metadata;
    elseif is_temp
        data = content.temp_noise_results;
        if isfield(data,'analysis_type'), type = data.analysis_type;
        else, type = 'temperature_noise_city'; end
        assert(ismember(type,{'temperature_noise_city','temperature_noise_village'}), ...
            'Unsupported temperature analysis type: %s',path);
        base_meta = data.metadata.noise_metadata;
    else
        type = 'snr'; data = content.snr_results;
        base_meta = data.metadata.noise_metadata;
    end
    assert(data.format_version == 1, 'Unsupported format version: %s', path);
    if k == 1
        dataset_type = type;
        template = data;
        reference_meta = base_meta;
    else
        assert(strcmp(dataset_type, type), 'Different analysis types cannot be combined in a single run.');
        check_base_metadata(reference_meta, base_meta, path);
        if strcmp(type, 'snr')
            check_fields(template.metadata, data.metadata, ...
                {'lnb_lo_hz','frequency_conversion','record_center_if_hz', ...
                'record_center_rf_hz','snr_definition','invalid_policy','assumption'}, path);
            % Require identical bands in the same order so that corresponding columns have the same meaning.
            assert(isequaln(template.metadata.bands, data.metadata.bands), ...
                'SNR bands or their order differ: %s', path);
        end
        if strcmp(type, 'impulses')
            check_fields(template.metadata, data.metadata, ...
                {'threshold_db','min_peak_distance_bins','detector_definition', ...
                'boundary_policy','stft_time_step_s'}, path);
        end
        if ismember(type, {'temperature_noise_city','temperature_noise_village'})
            check_fields(template.metadata, data.metadata, ...
                {'temperature_field','temperature_units','temperature_matching', ...
                'temperature_validation','invalid_policy','temperature_time_definition'}, path);
        end
    end
    input_metadata{k} = data.metadata;
    starts(k) = base_meta.analysis_start;
    ends_exclusive(k) = base_meta.analysis_end_exclusive;
    source_dirs_city(k) = string(data.city.source_directory);
    source_dirs_village(k) = string(data.village.source_directory);
    parts_city{k} = normalize_table(data.city.data, type, data);
    parts_village{k} = normalize_table(data.village.data, type, data);
    for loc = 1:2
        if loc == 1, tt = parts_city{k}; label = "city";
        else, tt = parts_village{k}; label = "village"; end
        summary_file(end+1,1) = string(path);
        summary_location(end+1,1) = label;
        summary_rows(end+1,1) = height(tt);
        if isempty(tt)
            summary_first(end+1,1) = NaT;
            summary_last(end+1,1) = NaT;
        else
            summary_first(end+1,1) = min(tt.Properties.RowTimes);
            summary_last(end+1,1) = max(tt.Properties.RowTimes);
        end
    end
    fprintf('Loaded %d/%d: %s\n', k, numel(input_files), path);
end

[city, duplicate_city] = merge_tables(parts_city, 'city');
[village, duplicate_village] = merge_tables(parts_village, 'village');
assert(~isempty(city) || ~isempty(village), 'All input tables are empty.');
summary = table(summary_file, summary_location, summary_rows, summary_first, summary_last, ...
    'VariableNames', {'Input_File','Location','Rows','First_Chunk_Start','Last_Chunk_Start'});
disp(summary);
fprintf('Merged: city %d chunks; village %d chunks.\n', height(city), height(village));

%% 3. METADATA AND SAVE MERGED DATASET
merged = template;
merged.created_at = datetime('now');
merged.city.data = city;
merged.village.data = village;
% Compute coverage summaries from the merged data.
merged.city.coverage = merged_coverage(city, reference_meta.chunk_duration_s);
merged.village.coverage = merged_coverage(village, reference_meta.chunk_duration_s);
if isfield(merged.metadata, 'analysis_elapsed_s')
    merged.metadata = rmfield(merged.metadata, 'analysis_elapsed_s');
end
merged.city.source_directories = unique(source_dirs_city);
merged.village.source_directories = unique(source_dirs_village);
% source_directory is retained for compatibility; source_directories lists all input directories.
merged.metadata.merge.input_files = input_files;
merged.metadata.merge.input_metadata = input_metadata;
merged.metadata.merge.input_summary = summary;
merged.metadata.merge.identical_duplicates_removed_city = duplicate_city;
merged.metadata.merge.identical_duplicates_removed_village = duplicate_village;
merged.metadata.merge.duplicate_policy = ...
    'Same timestamp and same values: keep once. Conflicting values: stop.';
merged.metadata.merge.actual_first_chunk_start = min([city.Properties.RowTimes; village.Properties.RowTimes]);
merged.metadata.merge.actual_last_chunk_start = max([city.Properties.RowTimes; village.Properties.RowTimes]);

% Combined requested analysis interval; this alone does not establish complete measurement coverage.
if ~ismember(dataset_type, {'snr','temperature_noise_city','temperature_noise_village'})
    merged.metadata.analysis_start = min(starts);
    merged.metadata.analysis_end_exclusive = max(ends_exclusive);
    merged.metadata.test_mode = any(cellfun(@(x) x.test_mode, input_metadata));
    merged.metadata.file_limit_per_location = NaN; % Individual input limits are retained in input_metadata.
else
    merged.metadata.noise_metadata.analysis_start = min(starts);
    merged.metadata.noise_metadata.analysis_end_exclusive = max(ends_exclusive);
    merged.metadata.noise_files = cellfun(@(x) x.noise_file, input_metadata, 'UniformOutput', false);
    merged.metadata.noise_file = ''; % Multiple reference datasets; see noise_files.
    % An individual run duration does not represent the duration of the merged analysis.
    if isfield(merged.metadata, 'elapsed_seconds')
        merged.metadata = rmfield(merged.metadata, 'elapsed_seconds');
    end
end

if ~isfolder(output_dir), mkdir(output_dir); end
run_id = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
merged.run_id = run_id;
stem = sprintf('Merged_%s_%s_%s_%s', dataset_type, ...
    char(string(min(starts), 'yyyyMMdd')), ...
    char(string(max(ends_exclusive)-caldays(1), 'yyyyMMdd')), run_id);
out_path = fullfile(output_dir, [stem '.mat']);
if strcmp(dataset_type, 'noise')
    noise_results = merged;
    save(out_path, 'noise_results', '-v7.3');
elseif strcmp(dataset_type, 'impulses')
    impulse_results = merged;
    save(out_path, 'impulse_results', '-v7.3');
elseif ismember(dataset_type, {'temperature_noise_city','temperature_noise_village'})
    temp_noise_results = merged;
    save(out_path, 'temp_noise_results', '-v7.3');
else
    snr_results = merged;
    save(out_path, 'snr_results', '-v7.3');
end
fprintf('Saved: %s\n', out_path);

%% 4. PLOTS FOR THE FULL PERIOD
noise_unit = 'dB';
if isfield(reference_meta,'normalization_mode') && ...
        strcmp(reference_meta.normalization_mode,'mean_bin_dbfs_v1')
    noise_unit = 'dBFS';
end
if strcmp(dataset_type, 'noise')
    fig = figure('Name', 'Merged noise floor', 'NumberTitle', 'off', ...
        'Position', [100 100 1400 900]);
    ax1 = subplot(2,1,1);
    plot_locations(ax1, city, village, 'Median_Noise_dB', 1);
    title(ax1, 'Median noise floor'); ylabel(ax1, sprintf('Median noise level (%s)',noise_unit));
    ax2 = subplot(2,1,2);
    plot_locations(ax2, city, village, 'Noise_Std_dB', 1);
    title(ax2, 'Noise floor standard deviation'); ylabel(ax2, 'Standard deviation (dB)');
    linkaxes([ax1 ax2], 'x');
    if save_figures, save_plot(fig, output_dir, stem); end
elseif strcmp(dataset_type, 'impulses')
    fig = figure('Name', 'Merged impulse detection results', 'NumberTitle', 'off', ...
        'Position', [100 100 1400 600]);
    ax = axes(fig);
    plot_locations(ax, city, village, 'Peaks_per_5s', 1);
    if isfield(merged.metadata,'threshold_units')
        threshold_units = merged.metadata.threshold_units;
    else
        threshold_units = 'dB'; % Legacy unnormalized datasets
    end
    title(ax, sprintf('Impulse detection: threshold %.3f %s', ...
        merged.metadata.threshold_db, threshold_units));
    ylabel(ax, 'Peak count per 5 seconds');
    if save_figures, save_plot(fig, output_dir, stem); end
elseif ismember(dataset_type, {'temperature_noise_city','temperature_noise_village'})
    if strcmp(dataset_type,'temperature_noise_village')
        tt = village; location_label = 'village'; noise_color = 'b.'; temp_color = 'r.';
    else
        tt = city; location_label = 'city'; noise_color = 'r.'; temp_color = 'k.';
    end
    assert(~isempty(tt), 'The temperature analysis contains no rows.');
    fig = figure('Name',['Merged temperature and noise - ' location_label],'NumberTitle','off', ...
        'Position',[100 100 1400 600]);
    ax = axes(fig);
    yyaxis(ax,'left');
    h1 = plot(ax,tt.Properties.RowTimes,tt.Median_Noise_dB,noise_color,'MarkerSize',5);
    ylabel(ax,sprintf('Median noise floor (%s)',noise_unit));
    if isfield(merged.metadata,'plot') && isfield(merged.metadata.plot,'noise_ylim') ...
            && ~isempty(merged.metadata.plot.noise_ylim)
        ylim(ax,merged.metadata.plot.noise_ylim);
    end
    yyaxis(ax,'right');
    h2 = plot(ax,tt.Properties.RowTimes,tt.Temperature_C,temp_color,'MarkerSize',5);
    ylabel(ax,'Temperature from metadata (degC)');
    title(ax,['Median noise level and temperature over time - ' location_label]);
    xlabel(ax,'Date and time'); grid(ax,'on');
    legend(ax,[h1 h2],{'Median noise level','Temperature'},'Location','best');
    ax.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';
    if save_figures, save_plot(fig,output_dir,stem); end
else
    bands = merged.metadata.bands;
    for b = 1:height(bands)
        fig = figure('Name', sprintf('Merged SNR - band %d', b), ...
            'NumberTitle', 'off', 'Position', [100 100 1400 600]);
        ax = axes(fig);
        plot_locations(ax, city, village, 'SNR_dB', b);
        title(ax, sprintf('SNR: RF %.6f MHz, bandwidth %.6f MHz', ...
            bands.RF_Center_MHz(b), bands.Bandwidth_MHz(b)));
        ylabel(ax, 'SNR (dB)');
        if save_figures
            save_plot(fig, output_dir, sprintf('%s_band%02d', stem, b));
        end
    end
end

%% LOCAL FUNCTIONS
function check_base_metadata(a, b, path)
    fields = {'sample_rate_hz','center_frequency_hz','chunk_duration_s', ...
        'chunks_per_file','actual_start_offset_s','window_type','window_beta', ...
        'window_length','overlap_samples','nfft','iq_format','noise_definition', ...
        'noise_units','time_reference'};
    check_fields(a, b, fields, path);
    % The order of the noise bands does not affect their union.
    assert(isequaln(sortrows(a.noise_bands_mhz), sortrows(b.noise_bands_mhz)), ...
        'IF noise bands do not match: %s', path);
    optional = {'lnb_lo_hz','frequency_conversion','iq_scale','reference_power', ...
        'power_reference','adc_full_scale_verified','window_energy', ...
        'spectral_quantity','normalization_mode','threshold_units','threshold_quantity'};
    for j = 1:numel(optional)
        key = optional{j};
        assert(isfield(a,key) == isfield(b,key), ...
            'Metadata field %s is missing from one input: %s', key, path);
        if isfield(a,key), check_fields(a,b,{key},path); end
    end
end

function check_fields(a, b, fields, path)
    for j = 1:numel(fields)
        key = fields{j};
        assert(isfield(a,key) && isfield(b,key), 'Missing metadata field %s: %s', key, path);
        assert(isequaln(a.(key), b.(key)), 'Parameter %s differs: %s', key, path);
    end
end

function tt = normalize_table(tt, type, data)
    assert(istimetable(tt), 'Results must be a timetable.');
    % Normalize empty timetables without columns to the expected dataset schema.
    if isempty(tt) && width(tt) == 0
        if strcmp(type, 'noise')
            tt = timetable(NaT(0,1), zeros(0,1), zeros(0,1), ...
                'VariableNames', {'Median_Noise_dB','Noise_Std_dB'});
        elseif strcmp(type, 'impulses')
            tt = timetable(NaT(0,1), zeros(0,1), 'VariableNames', {'Peaks_per_5s'});
        elseif ismember(type, {'temperature_noise_city','temperature_noise_village'})
            tt = timetable(NaT(0,1),zeros(0,1),zeros(0,1),NaT(0,1), ...
                false(0,1),strings(0,1),strings(0,1),'VariableNames', ...
                {'Median_Noise_dB','Temperature_C','Temperature_Metadata_Time', ...
                'Temperature_Valid','Temperature_Source_File','Temperature_Status'});
        else
            nb = height(data.metadata.bands);
            z = zeros(0,nb);
            tt = timetable(NaT(0,1), z,z,z,z,z,strings(0,1),strings(0,1), ...
                'VariableNames', {'SNR_dB','Median_Total_BinPower', ...
                'Estimated_Noise_BinPower','Estimated_Signal_BinPower', ...
                'Fraction_Windows_Above_Noise','Source_File','Status'});
        end
    end
    tt.Properties.DimensionNames{1} = 'Time';
    assert(isdatetime(tt.Properties.RowTimes) && ~any(isnat(tt.Properties.RowTimes)), ...
        'Timestamps must be valid datetime values.');
    if strcmp(type, 'noise')
        required = {'Median_Noise_dB','Noise_Std_dB'};
    elseif strcmp(type, 'impulses')
        required = {'Peaks_per_5s'};
    elseif ismember(type, {'temperature_noise_city','temperature_noise_village'})
        required = {'Median_Noise_dB','Temperature_C','Temperature_Metadata_Time', ...
            'Temperature_Valid','Temperature_Source_File','Temperature_Status'};
    else
        required = {'SNR_dB','Median_Total_BinPower','Estimated_Noise_BinPower', ...
            'Estimated_Signal_BinPower','Fraction_Windows_Above_Noise','Source_File','Status'};
    end
    assert(isequal(tt.Properties.VariableNames, required), 'Unexpected table columns.');
    if strcmp(type, 'snr')
        for j = 1:5
            assert(size(tt.(required{j}),2) == height(data.metadata.bands), ...
                'The number of columns does not match the number of SNR bands.');
        end
    end
end

function [tt, removed] = merge_tables(parts, location)
    nonempty = ~cellfun(@isempty, parts);
    if ~any(nonempty), tt = parts{1}; removed = 0; return; end
    tt = sortrows(vertcat(parts{nonempty}));
    times = tt.Properties.RowTimes;
    keep = true(height(tt),1); removed = 0;
    compare_vars = tt.Properties.VariableNames;
    % Paths to the same RAW file may differ between computers.
    compare_vars(ismember(compare_vars, {'Source_File','Temperature_Source_File'})) = [];
    previous_kept = 1;
    for r = 2:height(tt)
        if times(r) == times(previous_kept)
            equal = true;
            for j = 1:numel(compare_vars)
                v = compare_vars{j};
                equal = equal && isequaln(tt.(v)(r,:), tt.(v)(previous_kept,:));
            end
            assert(equal, ...
                'Conflict at location %s at time %s. Overlapping results differ.', ...
                location, char(string(times(r), 'dd.MM.yyyy HH:mm:ss.SSS')));
            keep(r) = false; removed = removed+1;
        else
            previous_kept = r;
        end
    end
    tt = tt(keep,:);
    fprintf('%s: removed %d identical duplicates.\n', location, removed);
end

function plot_locations(ax, city, village, variable, band)
    % Plot points without connecting across gaps between recordings or missing days.
    hold(ax,'on');
    if ~isempty(city)
        plot(ax,city.Properties.RowTimes,city.(variable)(:,band), ...
            'r.', 'MarkerSize', 6, 'DisplayName','City');
    end
    if ~isempty(village)
        plot(ax,village.Properties.RowTimes,village.(variable)(:,band), ...
            'b.', 'MarkerSize', 6, 'DisplayName','Village');
    end
    hold(ax,'off'); grid(ax,'on'); legend(ax,'show','Location','best');
    xlabel(ax,'Date and time'); ax.XAxis.TickLabelFormat = 'dd.MM.yyyy HH:mm';
end

function save_plot(fig, folder, stem)
    savefig(fig, fullfile(folder,[stem '.fig']));
    print(fig, fullfile(folder,[stem '.png']), '-dpng', '-r150');
end

function coverage = merged_coverage(tt, duration_s)
    coverage.row_count = height(tt);
    coverage.first_chunk_start = NaT;
    coverage.last_chunk_start = NaT;
    coverage.last_chunk_end_exclusive = NaT;
    coverage.unique_timestamp_count = numel(unique(tt.Properties.RowTimes));
    coverage.duplicate_timestamp_count = height(tt)-coverage.unique_timestamp_count;
    if ~isempty(tt)
        coverage.first_chunk_start = min(tt.Properties.RowTimes);
        coverage.last_chunk_start = max(tt.Properties.RowTimes);
        coverage.last_chunk_end_exclusive = coverage.last_chunk_start+seconds(duration_s);
    end
    if ismember('Median_Noise_dB',tt.Properties.VariableNames)
        coverage.finite_median_count = nnz(isfinite(tt.Median_Noise_dB));
        if ismember('Noise_Std_dB',tt.Properties.VariableNames)
            coverage.finite_std_count = nnz(isfinite(tt.Noise_Std_dB));
        end
    elseif ismember('SNR_dB',tt.Properties.VariableNames)
        coverage.finite_snr_count_per_band = sum(isfinite(tt.SNR_dB),1);
    elseif ismember('Peaks_per_5s',tt.Properties.VariableNames)
        coverage.total_detected_peaks = sum(tt.Peaks_per_5s);
    end
    if ismember('Temperature_Valid',tt.Properties.VariableNames)
        coverage.valid_temperature_count = nnz(tt.Temperature_Valid);
        coverage.unique_temperature_recordings = ...
            numel(unique(tt.Temperature_Metadata_Time(tt.Temperature_Valid)));
    end
end