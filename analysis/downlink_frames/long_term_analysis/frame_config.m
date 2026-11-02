function C=frame_config()
C.version='paired_frames_v0.1.5';
C.inventoryPath=''; C.snrPath=''; C.cityRoot=''; C.villageRoot='';
C.fileNames=strings(0,1); C.maxPairs=Inf; C.outputDirectory='';
% Inclusive calendar dates; both [] selects every date in the inventory.
C.analysisStartDate=[]; C.analysisEndDate=[];
% [] = all available seconds; [5 15] reports blocks 5,...,14 on city RAW axis.
C.analysisIntervalS=[];
% 0 = existing full/interval mode; 10 = first ten confirmed stable seconds.
C.firstStableSeconds=0;
C.minimumStableSeconds=5;
C.sync=frame_sync_dsp('defaults');
C.sync.channel_center_if_hz=[1311e6 1311e6];
C.sync.channel_bandwidth_hz=2e6;
C.search=struct('discovery_bandwidth_hz',200e3,'wide_radius_s',.5, ...
 'discovery_min_correlation',.15,'confirm_radius_s',.0005);
C.localSearchRadiusS=.0005;
C.probeOffsetsS=[.03 .49 .95];
C.minStableBlocks=3;
C.neighborToleranceS=40e-6;
C.decode=frame_decode('defaults');
C.decodeContextS=.4;
C.decodeStartupGuardS=.030; C.decodeTailGuardS=.020;
C.boundaryGuardS=.003; C.matchToleranceS=.002;
% Known outage interval is calibration evidence, not a hard time exclusion.
% Bounds refer to nominal RAW start in filename, without timezone conversion.
C.useNoiseCalibration=true;
C.noiseReference=[datetime(2026,9,26,13,0,0),datetime(2026,9,27,7,30,0)];
C.snrUncertainMarginDb=1;
C.skipJointLikelyNoise=true;
% Whole-record screening uses both stations; weak city alone is never enough.
C.skipRecordLikelyNoise=true;
C.recordNoiseThresholdDb=0;
C.recordNoiseMinCoverage=.8;
C.recordNoiseProtectBursts=true;
C.saveFrameBytes=true;
end
