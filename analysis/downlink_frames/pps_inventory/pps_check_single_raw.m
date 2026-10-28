% Check PPS detection in one RAW file using the default thresholds.
% Keep pps_tools.m in the same folder when running this script.
clear; clc; close all;
C = pps_tools('config'); % default configuration, first 5 s
fprintf('Resolved pps_tools paths:\n');
disp(which('pps_tools','-all'));
runtime_info = struct;
runtime_info.matlab_version = version;
runtime_info.pps_paths = which('pps_tools','-all');
runtime_info.upfirdn_paths = which('upfirdn','-all');
runtime_info.resample_paths = which('resample','-all');
runtime_info.spectrogram_paths = which('spectrogram','-all');
try
    probe = upfirdn(complex(ones(64,1),zeros(64,1)),ones(5,1),1,2);
    runtime_info.upfirdn_double_probe = ['OK: ' class(probe)];
catch ME
    runtime_info.upfirdn_double_probe = getReport(ME,'extended','hyperlinks','off');
end
[name,folder] = uigetfile('*.raw','Select a RAW recording containing PPS markers');
if isequal(name,0), return; end
path = fullfile(folder,name); F = dir(path);
info = struct('Measurement_ID',string(name),'Source_File',string(path), ...
    'File_Name',string(name),'Day_Folder',"diagnostic", ...
    'File_Start_Time',NaT,'Filename_Time_Valid',false,'File_Size_Bytes',double(F.bytes));
[row,detail] = pps_tools('analyze',info,C,true);
disp(row(:,{'File_Name','Status','PPS_Detected','Pulse_Count', ...
    'Marker_IF_Hz','Marker_Offset_Hz','Metadata_Status','Message'}));
fprintf('Full message: %s\n',char(row.Message));
if isfield(detail,'error_report'), fprintf('%s\n',detail.error_report); end
fprintf('Configuration: Fs %.0f Hz, IF center %.0f Hz, nominal PPS %.0f Hz.\n', ...
    C.sample_rate_hz,C.center_frequency_if_hz,C.nominal_marker_if_hz);
[outName,outFolder] = uiputfile('*.mat','Save diagnostics', ...
    fullfile(folder,'PPS_single_raw_diagnostics.mat'));
if isequal(outName,0), return; end
row_plain = table2struct(row);
keys = fieldnames(row_plain);
for k = 1:numel(keys)
    value = row_plain.(keys{k});
    if isdatetime(value)
        if isnat(value)
            row_plain.(keys{k}) = 'NaT';
        else
            row_plain.(keys{k}) = char(string(value));
        end
    elseif isstring(value)
        value(ismissing(value)) = "";
        row_plain.(keys{k}) = char(value);
    end
end
save(fullfile(outFolder,outName),'row','row_plain','detail','C','runtime_info','-v7');
[~,stem] = fileparts(outName);
flat = row;
flat(:,{'Pulse_Onsets_s','Pulse_Ends_s','Pulse_Frequencies_IF_Hz','Pulse_Line_SNR_dB'}) = [];
writetable(flat,fullfile(outFolder,[stem '.csv']));
if isfield(detail,'times_s')
    pps_tools('plot_file',detail,row,C,fullfile(outFolder,[stem '.png']));
end
fprintf('Diagnostics saved to %s\n',outFolder);
