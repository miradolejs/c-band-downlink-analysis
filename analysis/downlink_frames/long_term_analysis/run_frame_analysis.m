% Paired frame analysis for a user-selected date range.
% MATLAB R2020b+; Signal Processing Toolbox and Communications Toolbox.
clear; clc;

%% 1. INPUTS AND INCLUSIVE CALENDAR DATE RANGE
C=frame_config();
C.inventoryPath='D:\iq_analysis_results\PPS\PPSInventory.mat';
C.snrPath='D:\iq_analysis_results\SNR\SNR.mat';
C.cityRoot='D:\iq_data\city';
C.villageRoot='D:\iq_data\village';
% Example dates: change both to select any interval covered by the inputs.
C.analysisStartDate=datetime(2026,9,25);
C.analysisEndDate=datetime(2026,9,30);
% Set both dates to [] to use every date available in the inventory.

%% 2. FULL OR LIMITED TEST RUN
test_mode=false;
max_test_pairs=5;
% Optional explicit selection within the date range, e.g.:
% C.fileNames=["1119_174000_250926.raw";"1234_125000_260926.raw"];
C.fileNames=strings(0,1);
C.maxPairs=Inf;
mode_label='FULL';
if test_mode
 validateattributes(max_test_pairs,{'numeric'},{'scalar','integer','positive','finite'});
 C.maxPairs=max_test_pairs;
 mode_label='TEST';
end

%% 3. STABLE-SECOND SELECTION AND SNR SCREENING
C.analysisIntervalS=[];
C.firstStableSeconds=10;
C.minimumStableSeconds=5;
C.skipJointLikelyNoise=true;
C.skipRecordLikelyNoise=true;
C.recordNoiseThresholdDb=0;
C.recordNoiseMinCoverage=.8;
C.recordNoiseProtectBursts=true;
C.decode.timingLoopBandwidth=.0002;
% The campaign-specific noise reference is defined in frame_config.
% For another campaign, set C.noiseReference or C.useNoiseCalibration=false.

%% 4. NEW OUTPUT FOLDER AND EXECUTION
output_root=fullfile(fileparts(mfilename('fullpath')),'results');
C.outputDirectory=fullfile(output_root, ...
 ['FRAME_' mode_label '_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
assert(~isfolder(C.outputDirectory),'Frame:Output','The new output folder already exists.');
fprintf('New %s run. Checkpoints and results: %s\n',mode_label,C.outputDirectory);
fprintf('To resume: R=resume_frame_analysis; select this output folder.\n');
R=analyze_frames(C);
