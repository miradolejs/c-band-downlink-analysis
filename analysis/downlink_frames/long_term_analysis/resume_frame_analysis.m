function R=resume_frame_analysis(outputDirectory)
% Restore the original configuration without editing any fingerprinted files.
% analyze_frames validates configuration, source signatures and RAW metadata.
if nargin<1 || isempty(outputDirectory)
 outputDirectory=uigetdir(fileparts(mfilename('fullpath')), ...
  'Select the output folder containing run_config.mat');
 if isequal(outputDirectory,0), R=[]; return; end
end
manifestPath=fullfile(outputDirectory,'run_config.mat');
assert(isfile(manifestPath),'Frame:Resume','Select an output folder containing run_config.mat.');
X=load(manifestPath,'C');
assert(isfield(X,'C') && isstruct(X.C),'Frame:Resume','Saved run configuration is missing.');
C=X.C; C.outputDirectory=outputDirectory;
fprintf('Resume saved run: %s\n',char(outputDirectory));
R=analyze_frames(C);
end
