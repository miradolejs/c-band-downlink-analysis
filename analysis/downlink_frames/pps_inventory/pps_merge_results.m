% Merge PPS inventories without rereading RAW data; independent of computer-specific root paths.
clear; clc; close all;

%% 1. SETTINGS
output_dir = 'D:\iq_analysis_results\Merged_PPS';
save_figures = true;
input_files = {}; % or {'D:\vysledky\part1.mat';'F:\vysledky\part2.mat'}
if isempty(input_files)
    [names,folder] = uigetfile('*.mat','Select partial PPSInventory MAT files', ...
        'MultiSelect','on');
    if isequal(names,0), return; end
    if ischar(names), names = {names}; end
    input_files = cellfun(@(x) fullfile(folder,x),names,'UniformOutput',false);
end
input_files = cellstr(string(input_files(:)));
assert(~isempty(input_files),'No inputs selected.');
assert(numel(unique(input_files))==numel(input_files),'The same MAT file was selected more than once.');

%% 2. VALIDATE DATA SCHEMA AND DETECTOR PARAMETERS
parts = cell(numel(input_files),1);
for k = 1:numel(input_files)
    loaded = load(input_files{k},'pps_results');
    assert(isfield(loaded,'pps_results'),'Missing pps_results: %s',input_files{k});
    R = loaded.pps_results;
    assert(R.format_version==1 && R.schema_version==1 && ...
        strcmp(R.schema_name,'iq_analysis_results') && ...
        strcmp(R.analysis_type,'pps_marker_inventory'), ...
        'Unsupported PPS data schema: %s',input_files{k});
    if k==1
        reference = R.metadata.detector; merged = R;
    else
        assert(isequaln(reference,R.metadata.detector), ...
            'Detector parameters differ. These results cannot be merged: %s',input_files{k});
        assert(strcmp(R.metadata.timestamp_timezone,merged.metadata.timestamp_timezone), ...
            'Timestamp conventions differ: %s',input_files{k});
    end
    for location = {'city','village'}
        L = location{1}; T = R.(L).data; E = pps_tools('empty');
        assert(istable(T) && isequal(T.Properties.VariableNames,E.Properties.VariableNames), ...
            'Invalid columns for %s: %s',L,input_files{k});
        assert(numel(unique(T.Measurement_ID))==height(T), ...
            'Duplicate Measurement_ID within input: %s',input_files{k});
    end
    parts{k} = R;
    fprintf('Loaded %d/%d: %s\n',k,numel(input_files),input_files{k});
end

%% 3. MERGE BY MEASUREMENT ID RATHER THAN PATH OR TIMESTAMP ALONE
for location = {'city','village'}
    L = location{1}; tables = cellfun(@(r) r.(L).data,parts,'UniformOutput',false);
    T = vertcat(tables{:});
    [T,removed] = deduplicate(T,L,{'Source_File'});
    if ~isempty(T)
        T = sortrows(T,{'File_Start_Time','Measurement_ID'},'MissingPlacement','last');
    end
    discoveries = cellfun(@(r) r.(L).discovery,parts,'UniformOutput',false);
    discovery = vertcat(discoveries{:});
    [discovery,~] = deduplicate(discovery,[L ' discovery'],{'Source_File'});
    roots = strings(numel(parts),1);
    for k = 1:numel(parts), roots(k) = string(parts{k}.(L).source_directory); end
    merged.(L).source_directories = unique(roots);
    merged.(L).data = T;
    merged.(L).discovery = discovery;
    % Retain daily inventories per input; overlapping days are not summed.
    merged.(L).days_per_input = cellfun(@(r) r.(L).days,parts,'UniformOutput',false);
    merged.(L).days = table;
    merged.metadata.merge.(['identical_duplicates_removed_' L]) = removed;
end

%% 4. INPUT METADATA, MERGED DATASET, AND SUMMARIES OF UNIQUE FILES
starts = NaT(numel(parts),1); ends = starts;
for k = 1:numel(parts)
    starts(k) = parts{k}.metadata.analysis_start;
    ends(k) = parts{k}.metadata.analysis_end_exclusive;
end
merged.created_at = datetime('now');
merged.run_id = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
merged.metadata.analysis_start = min(starts);
merged.metadata.analysis_end_exclusive = max(ends);
merged.metadata.test_mode = any(cellfun(@(r) r.metadata.test_mode,parts));
merged.metadata.file_limit_per_location = NaN;
merged.metadata.is_complete_run = all(cellfun(@(r) r.metadata.is_complete_run,parts));
if isfield(merged.metadata,'analysis_elapsed_s')
    merged.metadata = rmfield(merged.metadata,'analysis_elapsed_s');
end
merged.metadata.merge.input_files = input_files;
merged.metadata.merge.input_metadata = cellfun(@(r) r.metadata,parts,'UniformOutput',false);
merged.metadata.merge.duplicate_policy = ...
    'Same location + Measurement_ID and same values: keep once. Conflicting values: stop. Root paths ignored.';
merged.metadata.merge.coverage_note = ...
    'Requested date extent is not proof of full coverage; use discovery, attempted rows and per-input metadata.';
run_folder = fullfile(output_dir,['PPS_MERGED_' merged.run_id]);
assert(~isfolder(run_folder),'The output folder already exists.');
[ok,message] = mkdir(run_folder); assert(ok,'%s',message);
pps_results = merged;
path = fullfile(run_folder,['PPSInventory_MERGED_' merged.run_id '.mat']);
pps_tools('save',path,pps_results);
pps_tools('reports',pps_results,run_folder);
if save_figures, pps_tools('plot',pps_results,run_folder); end
fprintf('Merged unique files: city %d, village %d.\n', ...
    height(pps_results.city.data),height(pps_results.village.data));
fprintf('Saved: %s\n',path);

function [T,removed] = deduplicate(T,location,ignored)
removed = 0;
if isempty(T), return; end
T = sortrows(T,'Measurement_ID');
variables = setdiff(T.Properties.VariableNames,ignored,'stable');
keep = true(height(T),1); previous = 1;
for r = 2:height(T)
    if T.Measurement_ID(r)==T.Measurement_ID(previous)
        same = true;
        for k = 1:numel(variables)
            key = variables{k};
            same = same && isequaln(T.(key)(r,:),T.(key)(previous,:));
        end
        assert(same, ...
            'Conflicting results for %s, ID %s. Merge stopped; check RAW copies and configuration.', ...
            location,char(T.Measurement_ID(r)));
        keep(r) = false; removed = removed+1;
    else
        previous = r;
    end
end
T = T(keep,:);
end
