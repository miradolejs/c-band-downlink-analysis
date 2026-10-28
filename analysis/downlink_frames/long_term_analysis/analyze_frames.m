function R=analyze_frames(C)
% Paired observation of CRC-valid frames, not end-to-end network packet loss.
if ~isfield(C,'analysisStartDate'), C.analysisStartDate=[]; end
if ~isfield(C,'analysisEndDate'), C.analysisEndDate=[]; end
if ~isfield(C,'analysisIntervalS'), C.analysisIntervalS=[]; end
if ~isfield(C,'firstStableSeconds'), C.firstStableSeconds=0; end
if ~isfield(C,'minimumStableSeconds'), C.minimumStableSeconds=5; end
if ~isfield(C,'skipRecordLikelyNoise'), C.skipRecordLikelyNoise=true; end
if ~isfield(C,'recordNoiseThresholdDb'), C.recordNoiseThresholdDb=0; end
if ~isfield(C,'recordNoiseMinCoverage'), C.recordNoiseMinCoverage=.8; end
if ~isfield(C,'recordNoiseProtectBursts'), C.recordNoiseProtectBursts=true; end
frame_interval_selection(struct('second',{},'run',{}),C);
frame_first_stable_pick(struct('second',{},'run',{}),C);
assert(C.saveFrameBytes,'Frame:Reconcile','Set saveFrameBytes=true for overlap reconciliation.');
assert(isfile(C.inventoryPath) && isfile(C.snrPath),'Set inventoryPath and snrPath to MAT files.');
assert(numel(C.probeOffsetsS)>=max(3,C.sync.min_valid_probes) && min(C.probeOffsetsS)>0 && ...
 max(C.probeOffsetsS)+C.sync.reference_duration_s<1,'Invalid probe offsets.');
assert(C.minStableBlocks>=2 && C.matchToleranceS<C.boundaryGuardS,'Invalid stability or boundary guard.');
assert(exist('comm.SymbolSynchronizer','class')~=0,'Communications Toolbox required.');
for f={'resample','butter','filtfilt','kaiserord','vitdec','convenc'}
 assert(exist(f{1},'file')~=0,'Missing toolbox function %s.',f{1});
end
assert(C.decode.fsRaw==C.sync.raw_fs_hz && C.decode.centerIF==C.sync.raw_center_if_hz ...
 && C.decode.lnbLO-C.decode.targetRF==C.sync.channel_center_if_hz(1) ...
 && all(C.sync.channel_center_if_hz==C.sync.channel_center_if_hz(1)), ...
 'Decoder and synchronization frequency settings disagree.');
X=load(C.inventoryPath,'pps_results'); I=X.pps_results;
S=frame_snr('prepare',C.snrPath,C);
A=I.city.data; B=I.village.data;
assert(numel(unique(string(A.File_Name)))==height(A) && ...
 numel(unique(string(B.File_Name)))==height(B),'Duplicate inventory filename.');
% Union keeps missing partners in the exclusion audit.
names=frame_select_dates(union(string(A.File_Name),string(B.File_Name)), ...
 C.analysisStartDate,C.analysisEndDate);
if ~isempty(C.fileNames)
 assert(all(ismember(C.fileNames,names)),'A requested filename is absent from the inventory.');
 names=names(ismember(names,C.fileNames));
end
assert(~isempty(names),'No requested inventory pairs found.');
names=names(1:min(numel(names),C.maxPairs));
out=C.outputDirectory;
if isempty(out)
 out=fullfile(fileparts(mfilename('fullpath')),['FRAME_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
end
if ~isfolder(out), mkdir(out); end
identity=C; identity=rmfield(identity,{'outputDirectory','fileNames','maxPairs'});
d1=dir(C.inventoryPath); d2=dir(C.snrPath);
identity.input_signature=[d1.bytes d1.datenum d2.bytes d2.datenum];
source=dir(fullfile(fileparts(mfilename('fullpath')),'*.m'));
source=source(~strcmp({source.name},'run_frame_analysis.m'));
identity.source_signature=struct('name',{source.name},'bytes',{source.bytes},'datenum',{source.datenum});
manifestPath=fullfile(out,'run_config.mat');
if isfile(manifestPath)
 previous=load(manifestPath,'identity');
 assert(isequaln(previous.identity,identity),'Configuration changed: use a new output folder.');
else
 save(manifestPath,'identity','C','-v7');
end
calibration=struct('city',rmfield(S.city,{'name','start_s','value','signal_power','processed'}), ...
 'village',rmfield(S.village,{'name','start_s','value','signal_power','processed'}));
save(fullfile(out,'snr_calibration.mat'),'calibration','-v7');
audit=struct('File_Name',{},'Status',{},'Message',{},'Result_File',{}, ...
 'Selected_Stable_Seconds',{},'Analyzed_Seconds',{},'Last_Scanned_Second',{}, ...
 'City_Record_SNR_dB',{},'Village_Record_SNR_dB',{}, ...
 'City_Record_SNR_Coverage',{},'Village_Record_SNR_Coverage',{}, ...
 'Synchronization_s',{},'Decoding_s',{},'Reconciliation_s',{},'Elapsed_s',{});
allRows=table();
for k=1:numel(names)
 name=names(k); fprintf('\n[%d/%d] %s\n',k,numel(names),char(name));
 pairTimer=tic; syncSeconds=0; decodeSeconds=0; reconcileSeconds=0;
 selectedCount=NaN; analyzedCount=NaN; lastScanned=NaN;
 recordCity=NaN; recordVillage=NaN; coverageCity=NaN; coverageVillage=NaN;
 resultPath=fullfile(out,[char(erase(name,'.raw')) '_frames.mat']);
 try
  a=frame_input('lookup',A,name); b=frame_input('lookup',B,name);
  assert(string(a.Status)=="present" && string(b.Status)=="present", ...
      'Missing or rejected PPS in at least one station.');
  [sa,ea]=frame_input('four_pps',a); [sb,eb]=frame_input('four_pps',b);
  assert(all(abs([sb-sa;eb-ea])<.5),'PPS pairing outside coarse tolerance.');
  coarse=median([sb-sa;eb-ea]);
  token=regexp(char(name),'^\d+_(\d{6})_(\d{6})\.raw$','tokens','once');
  assert(~isempty(token),'Unrecognized RAW filename.');
  city=fullfile(C.cityRoot,token{2},char(name));
  village=fullfile(C.villageRoot,token{2},char(name));
  ca=frame_input('validate_raw',city,a,C.sync);
  cb=frame_input('validate_raw',village,b,C.sync);
  if isfile(resultPath)
   Z=load(resultPath,'P'); P=Z.P;
   assert(isequaln(P.identity,identity) && P.city_bytes==ca.bytes && ...
       P.village_bytes==cb.bytes && P.city_modified_datenum==ca.modified_datenum && ...
       P.village_modified_datenum==cb.modified_datenum,'Checkpoint incompatible with current input.');
  else
   % PPS interval + margin; include only whole, mutually available seconds.
   first=ceil(max([5;ea+.05;eb+.05-coarse]));
   last=floor(ca.samples/C.sync.raw_fs_hz)-1;
   assert(last>=first,'No complete seconds outside PPS.');
   blocks=struct('second',{},'status',{},'probes',{},'model',{},'run',{}, ...
    'snr_city',{},'snr_village',{},'decode_city',{},'decode_village',{},'counts',{});
   for t=first:last
    blocks(end+1)=struct('second',t,'status',"pending",'probes',{{}}, ...
     'model',struct(),'run',0,'snr_city',struct(),'snr_village',struct(), ...
     'decode_city',struct(),'decode_village',struct(),'counts',struct()); %#ok<AGROW>
   end
   P=struct('identity',identity,'name',name,'city_path',city,'village_path',village, ...
    'city_bytes',ca.bytes,'village_bytes',cb.bytes, ...
    'city_modified_datenum',ca.modified_datenum,'village_modified_datenum',cb.modified_datenum,'coarse_delta_s',coarse, ...
    'last_four_city_onsets',sa,'last_four_village_onsets',sb, ...
    'blocks',blocks,'stage',"synchronization",'complete',false);
   savePair(resultPath,P);
  end
  if ~isfield(P,'record_snr')
   cityRange=[P.blocks(1).second P.blocks(end).second+1];
   villageRange=[max(0,cityRange(1)+coarse) ...
    min(cb.samples/C.sync.raw_fs_hz,cityRange(2)+coarse)];
   P.record_snr=frame_snr('record_pair',S,name,cityRange,villageRange,C);
   if P.record_snr.skip_pair && P.stage=="synchronization"
    for q=1:numel(P.blocks), P.blocks(q).status="record_likely_noise_snr"; end
    if C.firstStableSeconds>0
     P.selection=frame_first_stable_pick(P.blocks,C);
     P.selection.last_scanned_second=NaN; % no correlation was attempted.
    end
    P.stage="decoding";
   end
   savePair(resultPath,P);
  end
  recordCity=P.record_snr.city.mean_snr_db; recordVillage=P.record_snr.village.mean_snr_db;
  coverageCity=P.record_snr.city.coverage; coverageVillage=P.record_snr.village.coverage;
  if P.record_snr.skip_pair
   fprintf('  Skip record: low SNR on BOTH stations (city %.2f dB, village %.2f dB; coverage %.1f/%.1f percent).\n', ...
    recordCity,recordVillage,100*coverageCity,100*coverageVillage);
  end
  if P.stage=="synchronization"
   syncTimer=tic;
   previousDelta=coarse;
   for j=1:numel(P.blocks)
    if C.firstStableSeconds>0
     preview=frame_stable_runs(P.blocks,C);
     pick=frame_first_stable_pick(preview,C);
     if pick.reached_target && j>pick.last_needed_index, break; end
    end
    Q=P.blocks(j); t=Q.second;
    if Q.status~="pending"
     if isfield(Q.model,'usable') && Q.model.usable
      previousDelta=predict(Q.model,t+.5);
     end
     continue;
    end
    fprintf('  sync %02d s\n',t);
    Q.snr_city=frame_snr('window',S,'city',name,t,t+1);
    % Expand the village SNR query by the whole allowed search range.
    Q.snr_village=frame_snr('window',S,'village',name, ...
     t+coarse-C.search.wide_radius_s,t+1+coarse+C.search.wide_radius_s);
    if C.skipJointLikelyNoise && Q.snr_city.class=="likely_noise" && ...
        Q.snr_village.class=="likely_noise"
     Q.status="joint_likely_noise";
    else
     times=[]; delays=[];
     for h=1:numel(C.probeOffsetsS)
      tx=t+C.probeOffsetsS(h);
      probe=frame_sync_probe('probe',city,village,tx,previousDelta, ...
       C.localSearchRadiusS,cb.samples/C.sync.raw_fs_hz,C.sync,false);
      if ~probe.resolved
       probe=frame_sync_probe('wide',city,village,tx,coarse, ...
        cb.samples/C.sync.raw_fs_hz,C.sync,C.search);
      end
      Q.probes{h}=probe;
      if probe.resolved
       times(end+1)=tx; delays(end+1)=probe.total_delta_s; %#ok<AGROW>
      end
     end
     if numel(times)==numel(C.probeOffsetsS)
      Q.model=frame_sync_dsp('fit_model',times,delays,C.sync);
      if Q.model.usable
       va=t+predict(Q.model,t); vb=t+1+predict(Q.model,t+1);
       if va>=0 && vb<=cb.samples/C.sync.raw_fs_hz
        Q.snr_village=frame_snr('window',S,'village',name,va,vb);
        Q.status="locally_stable";
        if C.skipJointLikelyNoise && Q.snr_city.class=="likely_noise" && ...
            Q.snr_village.class=="likely_noise", Q.status="joint_likely_noise"; end
        previousDelta=predict(Q.model,t+.5);
       else, Q.status="mapped_interval_outside_raw";
       end
      else, Q.status="unstable_within_second";
      end
     else, Q.status="unresolved_sync";
     end
    end
    P.blocks(j)=Q; savePair(resultPath,P);
   end
   P.blocks=frame_stable_runs(P.blocks,C);
   if C.firstStableSeconds>0
    P.selection=frame_first_stable_pick(P.blocks,C);
    scanned=find(string({P.blocks.status})~="pending");
    P.selection.last_scanned_second=P.blocks(scanned(end)).second;
    for q=find(string({P.blocks.status})=="pending")
     P.blocks(q).status="not_scanned_after_target";
    end
    fprintf('  Selected stable seconds: %s (target %d, minimum %d)\n', ...
     mat2str(P.selection.report_seconds),C.firstStableSeconds,C.minimumStableSeconds);
   end
   P.stage="decoding"; savePair(resultPath,P);
   syncSeconds=toc(syncTimer);
  end
  if C.firstStableSeconds>0
   [reportMask,decodeMask]=frame_interval_selection(P.blocks,C,P.selection.report_seconds);
   selectedCount=sum(reportMask); lastScanned=P.selection.last_scanned_second;
   if ~P.selection.eligible
    decodeMask(:)=false;
    for q=find(reportMask & string({P.blocks.status})=="accepted")
     P.blocks(q).status="pair_excluded_minimum_seconds";
    end
   end
  else
   [reportMask,decodeMask]=frame_interval_selection(P.blocks,C);
   assert(any(reportMask),'Frame:Interval','Requested interval contains no available whole seconds outside PPS.');
   selectedCount=sum(reportMask & ismember(string({P.blocks.status}), ...
    ["accepted","analyzed","timing_unreliable","decode_error"]));
   lastScanned=P.blocks(end).second;
  end
  if P.record_snr.skip_pair, decodeMask(:)=false; lastScanned=NaN; end
  decodeTimer=tic;
  for j=1:numel(P.blocks)
   Q=P.blocks(j);
   if ~decodeMask(j) || Q.status~="accepted", continue; end
   t=Q.second; m=Q.model;
   delta=predict(m,t); deltaEnd=predict(m,t+1);
   Q.snr_city=frame_snr('window',S,'city',name,t,t+1);
   Q.snr_village=frame_snr('window',S,'village',name,t+delta,t+1+deltaEnd);
   if C.skipJointLikelyNoise && Q.snr_city.class=="likely_noise" && ...
       Q.snr_village.class=="likely_noise"
    Q.status="joint_likely_noise"; P.blocks(j)=Q; savePair(resultPath,P); continue;
   end
   same=find([P.blocks.run]==Q.run);
   bounds=[P.blocks(same(1)).second P.blocks(same(end)).second+1];
   lo=max(bounds(1),t-C.decodeContextS); hi=min(bounds(2),t+1+C.decodeContextS);
   slope=m.slope_s_per_s;
   intercept=m.delta_at_reference_s-slope*m.reference_city_time_s;
   vlo=(1+slope)*lo+intercept; vhi=(1+slope)*hi+intercept;
   fprintf('  decode %02d s, stable run %d\n',t,Q.run);
   DA=frame_decode('decode',city,lo,hi-lo,C.decode);
   DB=frame_decode('decode',village,vlo,vhi-vlo,C.decode);
   Q.decode_city=rmfield(DA,'frames'); Q.decode_village=rmfield(DB,'frames');
   if DA.status=="decoded" && DB.status=="decoded"
    Q.counts=frame_compare(DA.frames,DB.frames,t,bounds,intercept,slope,C);
    if ~C.saveFrameBytes
     Q.counts=rmfield(Q.counts,{'city_frames','village_frames'});
    end
    Q.status="analyzed";
   elseif DA.status=="timing_unreliable" || DB.status=="timing_unreliable"
    Q.status="timing_unreliable";
   else, Q.status="decode_error";
   end
   P.blocks(j)=Q; savePair(resultPath,P);
  end
  decodeSeconds=toc(decodeTimer);
  reconcileTimer=tic;
  if C.saveFrameBytes && any(string({P.blocks.status})=="analyzed")
   P=frame_reconcile(P);
  end
  reconcileSeconds=toc(reconcileTimer);
  analyzedCount=sum(reportMask & string({P.blocks.status})=="analyzed");
  if C.firstStableSeconds>0
   if P.complete && isfield(P.selection,'analyzed_seconds_before_pair_exclusion')
    analyzedCount=P.selection.analyzed_seconds_before_pair_exclusion;
   else
    P.selection.analyzed_seconds_before_pair_exclusion=analyzedCount;
   end
   P.selection.eligible=P.selection.eligible && analyzedCount>=C.minimumStableSeconds;
   if ~P.selection.eligible
    for q=find(reportMask & string({P.blocks.status})=="analyzed")
     P.blocks(q).status="pair_excluded_minimum_seconds";
    end
   end
  end
  P.complete=true; P.stage="complete"; savePair(resultPath,P);
  T=frame_result_table('seconds',P); writetable(T,replace(resultPath,'_frames.mat','_seconds.csv'));
  if ~isempty(C.analysisIntervalS) || C.firstStableSeconds>0 || P.record_snr.skip_pair
   U=frame_result_table('all_seconds',P);
   U.In_Analysis_Interval=reportMask(:);
   U.Selected_For_Decode=decodeMask(:);
   writetable(U,replace(resultPath,'_frames.mat','_all_blocks.csv'));
  end
  if isempty(allRows), allRows=T; else, allRows=[allRows;T]; end %#ok<AGROW>
  status="processed"; message="See per-second status and decoder diagnostics.";
  if C.firstStableSeconds>0 && ~P.selection.eligible
   status="insufficient_stable_seconds";
   message=sprintf('Selected %d stable seconds; %d decoded; minimum %d. Pair contributes no frame counts.', ...
    selectedCount,analyzedCount,C.minimumStableSeconds);
  end
  if P.record_snr.skip_pair
   status="record_likely_noise_snr";
   message=sprintf('Whole-record SNR screen: both means <= %.2f dB; city %.2f dB, village %.2f dB. No correlation or decoding.', ...
    C.recordNoiseThresholdDb,recordCity,recordVillage);
  end
  fprintf('  Time this invocation: sync %.1f s, decode %.1f s, reconcile %.1f s, total %.1f s\n', ...
   syncSeconds,decodeSeconds,reconcileSeconds,toc(pairTimer));
 catch ME
  status="pair_excluded_or_error"; message=string(getReport(ME,'extended','hyperlinks','off'));
  fprintf(2,'  %s\n',char(message));
 end
 audit(end+1)=struct('File_Name',name,'Status',status,'Message',message, ...
  'Result_File',string(resultPath),'Selected_Stable_Seconds',selectedCount, ...
  'Analyzed_Seconds',analyzedCount,'Last_Scanned_Second',lastScanned, ...
  'City_Record_SNR_dB',recordCity,'Village_Record_SNR_dB',recordVillage, ...
  'City_Record_SNR_Coverage',coverageCity,'Village_Record_SNR_Coverage',coverageVillage, ...
  'Synchronization_s',syncSeconds,'Decoding_s',decodeSeconds, ...
  'Reconciliation_s',reconcileSeconds,'Elapsed_s',toc(pairTimer)); %#ok<AGROW>
 writetable(struct2table(audit),fullfile(out,'pair_audit.csv'));
 if width(allRows)>0, writetable(allRows,fullfile(out,'all_seconds.csv')); end
end
R=struct('output_directory',out,'audit',struct2table(audit),'seconds',allRows);
R.summary=frame_result_table('summary',allRows);
R.summary.Pairs_Processed=sum(R.audit.Status=="processed");
R.summary.Pairs_Excluded_Or_Error=sum(R.audit.Status~="processed");
save(fullfile(out,'summary.mat'),'R','C','calibration','-v7.3');
writetable(R.summary,fullfile(out,'summary.csv'));
fprintf('\nDone: %s\n',out); disp(R.summary);
end
function d=predict(M,t)
d=M.delta_at_reference_s+M.slope_s_per_s*(t-M.reference_city_time_s);
end
function savePair(path,P)
% Replace only after a complete checkpoint was written.
tmp=[path '.pending.mat']; save(tmp,'P','-v7.3');
[ok,msg]=movefile(tmp,path,'f'); assert(ok,'%s',msg);
end
