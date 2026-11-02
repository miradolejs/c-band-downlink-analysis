function result = decode_downlink_to_pcap(rawPath, offsetSeconds, durationSeconds)
% DECODE_DOWNLINK_TO_PCAP  RAW IQ -> BPSK -> FEC -> multiplex -> Ethernet PCAP.
%
% Usage:
%   decode_downlink_to_pcap                 % select RAW file, process the 15 to 20 s interval
%   decode_downlink_to_pcap([], 25, 5)      % select RAW file, process the 25 to 30 s interval
%   R = decode_downlink_to_pcap('D:\data\recording.raw', 25, 5);
%
% For the analyzed 3839 MHz downlink, little-endian int16 I,Q RAW data; Fs = 10 MHz.
% Requires Signal Processing Toolbox and Communications Toolbox.
% This decoder is specific to the analyzed satellite downlink.
%
% Outputs in a new subfolder alongside the RAW file:
%   ethernet.pcap : only frames with valid HDLC FCS-16, with that FCS removed
%   analysis.mat  : FEC-decoded bits, demultiplexed branches, packets, diagnostics
%   summary.txt   : parameters, results, and timestamp limitations
%
% The PCAP has no actual calendar date. Time is relative to the first packet,
% derived from the nominal symbol rate and position in the original multiplex.
% It does not represent exact network packet reception times. Boundary frames may be lost.
%

%% Recording configuration -- adjust when the receiving chain or signal parameters change
cfg.fsRaw = 10e6;
cfg.centerIF = 1312e6;
cfg.lnbLO = 5150e6;
cfg.targetRF = 3839e6;
cfg.symbolRate = 1.024e6;
cfg.passbandHz = 950e3;
cfg.stopbandHz = 1.2e6;
cfg.passbandRippleDb = 0.1;
cfg.stopbandAttenuationDb = 60;
cfg.rawChunkSamples = 1000000;
cfg.carrierFFT = 131072;
cfg.carrierSearchHz = 100e3; % search range in the spectrum of the SQUARED signal
cfg.carrierBlockSeconds = 0.002;
cfg.samplesPerSymbol = 4;
cfg.timingLoopBandwidth = 0.005;
cfg.discardInitialSymbols = 10000;
cfg.discardFinalSymbols = 1000;
cfg.tracebackDepth = 64;
cfg.fecGuardBits = 200;
cfg.fecCheckGuardSymbols = 1000;
cfg.alignmentCandidates = 12;
cfg.maxHDLCFrameBits = 131072;
cfg.showPlots = true;
cfg.saveSymbols = false; % true also saves symbolsBPSK in the MAT file, increasing file size

if nargin<2 || isempty(offsetSeconds), offsetSeconds = 15; end
if nargin<3 || isempty(durationSeconds), durationSeconds = 5; end
validateattributes(offsetSeconds,{'numeric'}, ...
    {'scalar','real','finite','nonnegative'},mfilename,'offsetSeconds');
validateattributes(durationSeconds,{'numeric'}, ...
    {'scalar','real','finite','>=',0.2},mfilename,'durationSeconds');
offsetSeconds = double(offsetSeconds);
durationSeconds = double(durationSeconds);
result = struct('status','cancelled');
if nargin<1 || isempty(rawPath)
    [name,folder] = uigetfile('*.raw','Select an int16 I/Q RAW recording');
    if isequal(name,0), return; end
    rawPath = fullfile(folder,name);
end
rawPath = char(rawPath);
assert(isfile(rawPath),'RAW file does not exist: %s',rawPath);
required = {'pwelch','resample','kaiserord','fir1', ...
    'poly2trellis','vitdec','convenc'};
for k = 1:numel(required)
    assert(exist(required{k},'file')~=0, ...
        'Missing function %s. Check that the required toolboxes are installed.',required{k});
end
assert(exist('comm.SymbolSynchronizer','class')~=0, ...
    'Missing comm.SymbolSynchronizer from Communications Toolbox.');
assert(bitxor(crc16X25(uint8('123456789')),uint16(65535)) ...
    ==uint16(hex2dec('906E')),'CRC-16/X-25 reference test failed.');

fprintf('\nRAW -> BPSK -> FEC -> multiplex -> PCAP\n');
fprintf('RAW: %s\nInterval: %.6f to %.6f s\n', ...
    rawPath,offsetSeconds,offsetSeconds+durationSeconds);

%% 1. Block reading, channel translation, and FIR decimation to 5 MHz
fprintf('\n[1/6] Reading and selecting the channel...\n');
[iq,channelInfo] = readRawChannel(rawPath,offsetSeconds,durationSeconds,cfg);
fs = channelInfo.sample_rate_hz;
fprintf('Prepared %d IQ samples at Fs %.3f MHz.\n',numel(iq),fs/1e6);

%% 2. BPSK carrier correction and Gardner timing recovery
fprintf('[2/6] Carrier estimation, phase correction, and symbol timing recovery...\n');
[symbolsBPSK,demodInfo,plotData] = demodulateBPSK(iq,fs,cfg);
clear iq;
fprintf('Estimated carrier offset: %.3f Hz; symbols after trimming: %d\n', ...
    demodInfo.carrier_offset_estimate_hz,numel(symbolsBPSK));

%% 3. Pair alignment, soft-decision Viterbi decoding, and validation
fprintf('[3/6] FEC K=7, R=1/2, generators [133 171]...\n');
[decodedBits,fecInfo] = decodeFEC(symbolsBPSK,cfg);
fprintf('Pair syndrome at offset 0 / 1: %.3f %% / %.3f %%\n', ...
    100*fecInfo.pair_syndrome(1),100*fecInfo.pair_syndrome(2));
fprintf('Selected first symbol of the pair: %d\n',fecInfo.pair_offset_symbols+1);
fprintf('Re-encoding disagreement: %.4f %% (NOT BER).\n', ...
    100*fecInfo.reencode_disagreement_not_BER);
if min(fecInfo.pair_syndrome)>0.15
    warning('downlink:WeakFEC', ...
        'Weak FEC validation. This interval may have poor synchronization or contain a different signal.');
end
if ~cfg.saveSymbols, clear symbolsBPSK; end

%% 4. Linear descrambling and differential transformation
g = cfg.fecGuardBits;
assert(numel(decodedBits)>2*g+20+10*5120, ...
    'Too little data remains after synchronization. Select a longer interval.');
trimmed = decodedBits(g+1:end-g);
descrambledBits = xor(xor(trimmed(21:end),trimmed(18:end-3)),trimmed(1:end-20));
z = ~xor(descrambledBits(2:end),descrambledBits(1:end-1));
clear trimmed;

%% 5. Automatic demultiplexing, bit destuffing, and HDLC FCS validation
fprintf('[4/6] Searching for alignment of the 496 + 16*(280+9) structure...\n');
[mainBits,branch496Bits,branch9Bits,hdlcFrames,framingInfo,alignment] = ...
    recoverFraming(z,cfg);
clear z;
fprintf('Valid HDLC FCS: %d; validation half: %d\n', ...
    numel(hdlcFrames),framingInfo.validation_crc_passes);

%% 6. Ethernet PCAP, MAT, and summary
fprintf('[5/6] Preparing export...\n');
[ethernetFrames,packetTimesSeconds,packetStartMainBitMatlab,packetInfo] = ...
    prepareEthernet(hdlcFrames,framingInfo.frame_origin_zero_based,cfg.symbolRate);
outFolder = newOutputFolder(rawPath,offsetSeconds,durationSeconds);
matPath = fullfile(outFolder,'analysis.mat');
summaryPath = fullfile(outFolder,'summary.txt');
pcapPath = '';
if ~isempty(ethernetFrames)
    pcapPath = fullfile(outFolder,'ethernet.pcap');
    writePCAP(pcapPath,ethernetFrames,packetTimesSeconds);
    if framingInfo.independently_validated
        status = 'ok';
    else
        status = 'packets_found_alignment_not_independently_validated';
        warning('downlink:AlignmentNotValidated', ...
            ['The PCAP contains CRC-valid frames, but alignment was not confirmed in both ' ...
             'halves of the interval. Check another interval or a longer recording.']);
    end
else
    status = 'no_valid_ethernet_frames';
    warning('downlink:NoPackets', ...
        ['No Ethernet frames with valid HDLC FCS. No PCAP was created. ' ...
         'MAT and summary files will be saved for diagnostics; this does not establish that the channel has no traffic.']);
end

analysisInfo = struct;
analysisInfo.status = status;
analysisInfo.source_raw = rawPath;
analysisInfo.offset_seconds = offsetSeconds;
analysisInfo.duration_seconds = durationSeconds;
analysisInfo.config = cfg;
analysisInfo.channel = channelInfo;
analysisInfo.demodulation = demodInfo;
analysisInfo.fec = fecInfo;
analysisInfo.fec_guard_bits_each_end = g;
analysisInfo.descrambler_delays_bits = [3 20];
analysisInfo.differential_transform = 'NOT XOR of neighboring descrambled bits';
analysisInfo.framing = framingInfo;
analysisInfo.packet_summary = packetInfo;
analysisInfo.pcap_time_reference = ...
    'Relative to first exported packet; nominal symbol clock; no absolute date';
analysisInfo.physical_standard_identified = false;
analysisInfo.matlab_version = version;
save(matPath,'decodedBits','descrambledBits','mainBits', ...
    'branch496Bits','branch9Bits','hdlcFrames','ethernetFrames', ...
    'packetTimesSeconds','packetStartMainBitMatlab','analysisInfo','alignment','-v7');
if cfg.saveSymbols, save(matPath,'symbolsBPSK','-append'); end
writeSummary(summaryPath,analysisInfo,pcapPath);
result = struct('status',status,'output_folder',outFolder, ...
    'raw_file',rawPath, ...
    'pcap_file',pcapPath,'mat_file',matPath,'summary_file',summaryPath, ...
    'valid_hdlc_frames',numel(hdlcFrames),'ethernet_frames',numel(ethernetFrames));

fprintf('[6/6] Done. Output: %s\n',outFolder);
if ~isempty(pcapPath)
    fprintf('Open in Wireshark: %s\n',pcapPath);
    fprintf('Use relative time. The absolute PCAP date is not the measurement date.\n');
end
fprintf('Ethernet: %d frames; ARP %d; IPv4 %d; IPv6 %d; IEEE 802.3 %d.\n', ...
    packetInfo.total,packetInfo.arp,packetInfo.ipv4,packetInfo.ipv6,packetInfo.ieee8023);
fprintf('Do not use CRC ratios to estimate BER or network packet loss.\n');
if cfg.showPlots
    showDiagnostics(plotData,alignment,packetTimesSeconds,fecInfo,framingInfo);
end
end

function [iq,info] = readRawChannel(path,offset,duration,cfg)
    first = round(offset*cfg.fsRaw);
    count = round(duration*cfg.fsRaw);
    fileInfo = dir(path);
    available = floor(double(fileInfo.bytes)/4);
    assert(first+count<=available, ...
        'The file contains %.6f s, but the requested interval ends at %.6f s.', ...
        available/cfg.fsRaw,(first+count)/cfg.fsRaw);
    assert(mod(fileInfo.bytes,4)==0, ...
        'RAW file size is not a multiple of 4 bytes. Check the int16 I/Q format.');
    deltaP = (10^(cfg.passbandRippleDb/20)-1)/(10^(cfg.passbandRippleDb/20)+1);
    deltaS = 10^(-cfg.stopbandAttenuationDb/20);
    [order,Wn,beta,ftype] = kaiserord( ...
        [cfg.passbandHz cfg.stopbandHz],[1 0],[deltaP deltaS],cfg.fsRaw);
    order = order+mod(order,2);
    h = single(fir1(order,Wn,ftype,kaiser(order+1,beta),'noscale'));
    h = h/sum(h);
    state = complex(zeros(numel(h)-1,1,'single'));
    iq = complex(zeros(ceil(count/2),1,'single'));
    fid = fopen(path,'r','ieee-le');
    assert(fid>=0,'Cannot open RAW file: %s',path);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fseek(fid,4*first,'bof')==0,'Could not seek to the requested RAW file position.');
    fOffset = cfg.lnbLO-cfg.targetRF-cfg.centerIF;
    readCount = 0; written = 0;
    nextProgress = 0;
    while readCount<count
        n = min(cfg.rawChunkSamples,count-readCount);
        raw = fread(fid,[2 n],'int16=>single');
        assert(size(raw,2)==n,'Unexpected end of file or RAW read error.');
        x = complex(raw(1,:),raw(2,:)).'/single(32768);
        t = (readCount+(0:n-1).')/cfg.fsRaw;
        % High-side LNB mixing: first translate the IF channel to baseband, then conjugate.
        x = conj(x.*single(exp(-1j*2*pi*fOffset*t)));
        [y,state] = filter(h,single(1),x,state);
        start = 1+mod(readCount,2);
        y = y(start:2:end);
        iq(written+(1:numel(y))) = y;
        written = written+numel(y);
        readCount = readCount+n;
        if readCount/count>=nextProgress
            fprintf('  RAW %.0f %%\n',100*readCount/count);
            nextProgress = nextProgress+0.2;
        end
    end
    discard = ceil(order/2); % discard the entire initial FIR transient
    assert(written>discard,'The interval is too short for the channel filter.');
    iq = iq(discard+1:written);
    power = 0;
    for a = 1:cfg.rawChunkSamples:numel(iq)
        ix = a:min(a+cfg.rawChunkSamples-1,numel(iq));
        power = power+sum(abs(double(iq(ix))).^2);
    end
    power = power/numel(iq);
    assert(isfinite(power) && power>0,'Zero or invalid channel power.');
    iq = iq/single(sqrt(power));
    info = struct('sample_rate_hz',cfg.fsRaw/2,'rf_frequency_hz',cfg.targetRF, ...
        'if_offset_hz',fOffset,'raw_first_sample_zero_based',first, ...
        'raw_samples_read',count,'channel_samples',numel(iq), ...
        'channel_filter_order',order,'discarded_decimated_samples',discard, ...
        'fir_group_delay_raw_samples',order/2,'power_before_normalization',power);
end

function [symbols,info,plotData] = demodulateBPSK(iq,fs,cfg)
    nfft = cfg.carrierFFT;
    nEstimate = min(numel(iq),max(nfft,round(0.5*fs)));
    assert(nEstimate>=nfft,'The interval is too short for carrier estimation.');
    [P,f] = pwelch(double(iq(1:nEstimate)).^2, ...
        hann(nfft,'periodic'),nfft/2,nfft,fs,'centered');
    mask = abs(f)<=cfg.carrierSearchHz;
    fLocal = f(mask); pLocal = P(mask);
    [peak,index] = max(pLocal);
    coarse = fLocal(index)/2;
    background = median(pLocal(abs(fLocal-fLocal(index))>2*fs/nfft));
    prominence = 10*log10(peak/max(background,realmin));
    if prominence<6
        warning('downlink:WeakCarrier','The tone in the squared signal has low prominence: %.1f dB.',prominence);
    end
    L = round(cfg.carrierBlockSeconds*fs);
    nBlocks = floor(numel(iq)/L);
    assert(nBlocks>=10,'The interval is too short for carrier phase tracking.');
    moment = complex(zeros(nBlocks,1));
    blockTime = ((0:nBlocks-1).'*L+(L-1)/2)/fs;
    for k = 1:nBlocks
        ix = (k-1)*L+(1:L);
        t = (ix.'-1)/fs;
        u = double(iq(ix)).*exp(-1j*2*pi*coarse*t);
        moment(k) = mean(u.^2);
    end
    phase2 = unwrap(angle(moment));
    fit = polyfit(blockTime,phase2,1);
    residual = phase2-polyval(fit,blockTime);
    % Combine the coarse frequency offset with the interpolated slow phase.
    % Process in chunks to limit memory usage.
    chunk = cfg.rawChunkSamples;
    for a = 1:chunk:numel(iq)
        ix = a:min(a+chunk-1,numel(iq));
        t = (ix.'-1)/fs;
        phase = interp1(blockTime,0.5*phase2,t,'linear','extrap');
        iq(ix) = iq(ix).*single(exp(-1j*(2*pi*coarse*t+phase)));
    end
    [p,q] = rat(cfg.samplesPerSymbol*cfg.symbolRate/fs,1e-10);
    x4 = resample(iq,p,q);
    clear iq;
    normalizer = 0;
    for a = 1:chunk:numel(x4)
        ix = a:min(a+chunk-1,numel(x4));
        normalizer = normalizer+sum(abs(double(x4(ix))).^2);
    end
    x4 = x4/single(sqrt(normalizer/numel(x4)));
    sync = comm.SymbolSynchronizer( ...
        'TimingErrorDetector','Gardner (non-data-aided)', ...
        'SamplesPerSymbol',cfg.samplesPerSymbol,'DampingFactor',1, ...
        'NormalizedLoopBandwidth',cfg.timingLoopBandwidth);
    symbols = sync(x4);
    release(sync);
    assert(numel(symbols)>cfg.discardInitialSymbols+cfg.discardFinalSymbols+2000, ...
        'Too few symbols remain after timing recovery.');
    symbols = symbols(cfg.discardInitialSymbols+1:end-cfg.discardFinalSymbols);
    phaseCorrection = 0.5*angle(mean(double(symbols).^2));
    symbols = symbols.*single(exp(-1j*phaseCorrection));
    previewStep = max(1,ceil(numel(symbols)/15000));
    plotData = struct('constellation',symbols(1:previewStep:end), ...
        'block_time_s',blockTime,'carrier_phase2_residual_rad',residual);
    info = struct('symbol_rate_candidate',cfg.symbolRate, ...
        'carrier_coarse_offset_hz',coarse, ...
        'carrier_offset_estimate_hz',coarse+fit(1)/(4*pi), ...
        'carrier_squared_tone_prominence_db',prominence, ...
        'carrier_phase2_residual_rms_rad',sqrt(mean(residual.^2)), ...
        'constant_symbol_phase_correction_rad',phaseCorrection, ...
        'symbol_count',numel(symbols), ...
        'discarded_initial_symbols',cfg.discardInitialSymbols, ...
        'discarded_final_symbols',cfg.discardFinalSymbols);
end

function [bits,info] = decodeFEC(symbols,cfg)
    trellis = poly2trellis(7,[133 171]);
    assert(trellis.nextStates(1,2)==32 && trellis.outputs(1,2)==3, ...
        'Unexpected MATLAB trellis convention.');
    impulse = convenc([1;zeros(6,1)],trellis);
    generators = reshape(double(impulse),2,7).';
    soft = double(real(symbols(:)));
    syndrome = zeros(2,1);
    for o = 0:1
        hard = soft(o+1:end)<0;
        pairs = reshape(double(hard(1:2*floor(numel(hard)/2))),2,[]).';
        check = mod(conv(pairs(:,1),generators(:,2),'valid') ...
            +conv(pairs(:,2),generators(:,1),'valid'),2);
        syndrome(o+1) = mean(check);
    end
    [~,which] = min(syndrome); offset = which-1;
    soft = soft(offset+1:end);
    soft = soft(1:2*floor(numel(soft)/2));
    bits = logical(vitdec(soft,trellis,cfg.tracebackDepth,'trunc','unquant'));
    bits = bits(:);
    encoded = logical(convenc(double(bits),trellis));
    encoded = encoded(:);
    guard = cfg.fecCheckGuardSymbols;
    valid = guard+1:numel(soft)-guard;
    assert(~isempty(valid),'The input is too short for FEC validation.');
    disagreement = mean(encoded(valid)~=(soft(valid)<0));
    info = struct('constraint_length',7,'rate',0.5, ...
        'generator_octal_matlab_order',[133 171], ...
        'pair_offset_symbols',offset,'pair_syndrome',syndrome, ...
        'decoded_bit_count',numel(bits),'traceback_depth',cfg.tracebackDepth, ...
        'reencode_disagreement_not_BER',disagreement);
end

function [main,aux,tails,packets,info,alignment] = recoverFraming(z,cfg)
    period = 5120;
    e = double(xor(z(9:end),z(1:end-8)));
    n = floor(numel(e)/period);
    assert(n>=8,'The bitstream is too short to identify the multiplex structure.');
    folded = reshape(e(1:n*period),period,n);
    split = floor(n/2);
    trainProfile = mean(folded(:,1:split),2);
    validationProfile = mean(folded(:,split+1:end),2);
    mask = zeros(period,1);
    for k = 0:15, mask(496+k*289+(1:272)) = 1; end
    score = real(ifft(conj(fft(mask)).*fft(trainProfile)))/sum(mask);
    [~,order] = sort(score,'ascend');
    candidates = zeros(0,1);
    for k = 1:numel(order)
        o = order(k)-1;
        distance = abs(candidates-o);
        distance = min(distance,period-distance);
        if isempty(distance) || all(distance>=5)
            candidates(end+1,1) = o; %#ok<AGROW>
        end
        if numel(candidates)>=cfg.alignmentCandidates, break; end
    end
    trainingCounts = zeros(numel(candidates),1);
    validationCounts = zeros(numel(candidates),1);
    totalCounts = zeros(numel(candidates),1);
    bestTraining = -1; bestTotal = -1;
    for k = 1:numel(candidates)
        [m,a,t] = demultiplex(z,candidates(k));
        [p,hdlcStats] = decodeHDLC(m,cfg.maxHDLCFrameBits);
        boundary = floor(numel(m)/4480/2)*4480;
        if isempty(p), locations = zeros(0,1); else, locations = [p.startMainBit].'; end
        training = sum(locations<=boundary);
        validation = numel(p)-training;
        trainingCounts(k) = training;
        validationCounts(k) = validation;
        totalCounts(k) = numel(p);
        fprintf('  Origin %4d: CRC passes in first half %d, second half %d\n', ...
            candidates(k),training,validation);
        item = struct('main',m,'aux',a,'tails',t,'packets',p, ...
            'stats',hdlcStats,'origin',candidates(k),'training',training, ...
            'validation',validation,'candidateIndex',k);
        if training>bestTraining
            bestTrainItem = item;
            bestTraining = training;
        end
        if numel(p)>bestTotal
            bestTotalItem = item;
            bestTotal = numel(p);
        end
    end
    if bestTraining>0
        best = bestTrainItem;
        selection = 'CRC count in first half; second half held out';
    else
        % Traffic may occur only in the second half of the interval. In that case,
        % the second half does not independently validate the alignment selection.
        best = bestTotalItem;
        selection = 'Fallback: full-window CRC count; no held-out validation';
    end
    main = best.main; aux = best.aux; tails = best.tails; packets = best.packets;
    alignment = struct('origins_zero_based',candidates, ...
        'training_crc_counts',trainingCounts,'validation_crc_counts',validationCounts, ...
        'total_crc_counts',totalCounts,'training_score_all_origins',score, ...
        'training_change_profile',trainProfile,'validation_change_profile',validationProfile);
    info = struct('layout_period_bits',period,'leading_branch_bits',496, ...
        'number_of_cells',16,'cell_payload_bits',280,'cell_tail_bits',9, ...
        'frame_origin_zero_based',best.origin,'frame_origin_matlab',best.origin+1, ...
        'training_crc_passes',best.training,'validation_crc_passes',best.validation, ...
        'selected_by',selection,'independently_validated',bestTraining>0 && best.validation>0, ...
        'valid_hdlc_frames',numel(packets),'hdlc_stats',best.stats, ...
        'nominal_main_branch_rate_bps',cfg.symbolRate/2*4480/5120, ...
        'branch_496_meaning_unresolved',true,'branch_9_meaning_unresolved',true);
end

function [main,aux,tails] = demultiplex(z,origin)
    n = floor((numel(z)-origin)/5120);
    f = reshape(z(origin+1:origin+n*5120),5120,n);
    aux = f(1:496,:).';
    c = reshape(f(497:end,:),289,16,n);
    payload = c(1:280,:,:);
    main = payload(:);
    tails = permute(c(281:289,:,:),[3 2 1]);
end

function [packets,stats] = decodeHDLC(x,maxBits)
    flag = logical([0 1 1 1 1 1 1 0]);
    mismatch = zeros(numel(x)-7,1,'uint8');
    for j = 1:8
        mismatch = mismatch+uint8(x(j:j+numel(mismatch)-1)~=flag(j));
    end
    starts = find(mismatch==0);
    packets = struct('bytes',{},'startMainBit',{});
    tested = 0; failedFCS = 0; invalidStuffing = 0; oversize = 0;
    for k = 1:numel(starts)-1
        p = starts(k); q = starts(k+1);
        if q-p<40, continue; end
        if q-p-8>maxBits, oversize = oversize+1; continue; end
        raw = x(p+8:q-1);
        out = false(numel(raw),1); count = 0; onesCount = 0; bad = false;
        for j = 1:numel(raw)
            if onesCount==5
                if raw(j), bad = true; break; end
                onesCount = 0;
                continue;
            end
            count = count+1; out(count) = raw(j);
            if raw(j), onesCount = onesCount+1; else, onesCount = 0; end
        end
        if bad || onesCount==5
            invalidStuffing = invalidStuffing+1;
            continue;
        end
        if count<32 || mod(count,8)~=0, continue; end
        bytes = uint8(reshape(double(out(1:count)),8,[]).'*(2.^(0:7)).');
        tested = tested+1;
        if crc16X25(bytes)==uint16(hex2dec('F0B8'))
            packets(end+1).bytes = bytes(1:end-2); %#ok<AGROW>
            packets(end).startMainBit = p;
        else
            failedFCS = failedFCS+1;
        end
    end
    stats = struct('flag_count',numel(starts),'byte_aligned_candidates',tested, ...
        'valid_fcs_count',numel(packets),'failed_fcs_count',failedFCS, ...
        'invalid_stuffing_count',invalidStuffing,'oversize_candidates',oversize);
end

function c = crc16X25(bytes)
    persistent lut
    if isempty(lut)
        lut = zeros(256,1,'uint16');
        for i = 0:255
            v = uint16(i);
            for j = 1:8
                if bitand(v,uint16(1))
                    v = bitxor(bitshift(v,-1),uint16(hex2dec('8408')));
                else
                    v = bitshift(v,-1);
                end
            end
            lut(i+1) = v;
        end
    end
    c = uint16(65535);
    for j = 1:numel(bytes)
        index = double(bitand(bitxor(c,uint16(bytes(j))),uint16(255)))+1;
        c = bitxor(bitshift(c,-8),lut(index));
    end
end

function [frames,times,positions,info] = prepareEthernet(packets,origin,Rs)
    frames = cell(0,1); positions = zeros(0,1); types = zeros(0,1);
    for k = 1:numel(packets)
        v = packets(k).bytes;
        if numel(v)<14, continue; end
        t = double(v(13))*256+double(v(14));
        if (t>1500 && t<1536) || (t<=1500 && numel(v)-14<t), continue; end
        frames{end+1,1} = v; %#ok<AGROW>
        positions(end+1,1) = packets(k).startMainBit; %#ok<AGROW>
        types(end+1,1) = t; %#ok<AGROW>
    end
    if isempty(positions)
        times = zeros(0,1);
    else
        p = positions-1;
        within = mod(p,4480);
        source = origin+floor(p/4480)*5120+496 ...
            +floor(within/280)*289+mod(within,280);
        times = (source-source(1))/(Rs/2);
    end
    info = struct('total',numel(frames),'arp',sum(types==hex2dec('0806')), ...
        'ipv4',sum(types==hex2dec('0800')),'ipv6',sum(types==hex2dec('86DD')), ...
        'ieee8023',sum(types<=1500),'ether_type_or_length',types, ...
        'non_ethernet_hdlc_payloads',numel(packets)-numel(frames));
end

function writePCAP(path,packets,times)
    fid = fopen(path,'w','ieee-le');
    assert(fid>=0,'Cannot create PCAP: %s',path);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    assert(fwrite(fid,uint32(hex2dec('A1B2C3D4')),'uint32')==1,'PCAP write error.');
    assert(fwrite(fid,uint16([2 4]),'uint16')==2,'PCAP write error.');
    assert(fwrite(fid,uint32([0 0 65535 1]),'uint32')==4,'PCAP write error.');
    for k = 1:numel(packets)
        micro = round(times(k)*1e6);
        sec = floor(micro/1e6); usec = mod(micro,1e6);
        n = numel(packets{k});
        assert(n<=65535,'The frame exceeds the PCAP snapshot length.');
        assert(fwrite(fid,uint32([sec usec n n]),'uint32')==4,'PCAP write error.');
        assert(fwrite(fid,packets{k},'uint8')==n,'PCAP write error.');
    end
end

function folder = newOutputFolder(rawPath,offset,duration)
    [parent,base] = fileparts(rawPath);
    if isempty(parent), parent = pwd; end
    tag = strrep(sprintf('o%.3f_d%.3f',offset,duration),'.','p');
    stamp = datestr(now,'yyyymmdd_HHMMSSFFF');
    root = fullfile(parent,[base '_' tag '_' stamp]);
    folder = root; k = 1;
    while isfolder(folder), folder = sprintf('%s_%d',root,k); k = k+1; end
    [ok,message] = mkdir(folder);
    assert(ok,'Cannot create output folder: %s',message);
end

function writeSummary(path,A,pcap)
    fid = fopen(path,'w','n','UTF-8');
    assert(fid>=0,'Cannot create summary: %s',path);
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid,'C-BAND DOWNLINK -> WIRESHARK\n\n');
    fprintf(fid,'Status: %s\nRAW: %s\n',A.status,A.source_raw);
    fprintf(fid,'Interval: %.6f to %.6f s\n',A.offset_seconds,A.offset_seconds+A.duration_seconds);
    fprintf(fid,'RF: %.6f MHz; Fs RAW: %.6f MHz\n',A.config.targetRF/1e6,A.config.fsRaw/1e6);
    fprintf(fid,'Nominal Rs: %.3f symbols/s\n',A.config.symbolRate);
    fprintf(fid,'Carrier offset: %.3f Hz\n',A.demodulation.carrier_offset_estimate_hz);
    fprintf(fid,'FEC: K=7, R=1/2, MATLAB generators [133 171] (octal)\n');
    fprintf(fid,'Pair start: symbol %d\n',A.fec.pair_offset_symbols+1);
    fprintf(fid,'Pair syndrome 0/1: %.6f / %.6f\n',A.fec.pair_syndrome);
    fprintf(fid,'Re-encoding disagreement: %.6f %% (NOT BER)\n', ...
        100*A.fec.reencode_disagreement_not_BER);
    fprintf(fid,'Layout: 496 + 16*(280+9) = 5120 bits\n');
    fprintf(fid,'Origin in differential bitstream z, zero-based index: %d\n', ...
        A.framing.frame_origin_zero_based);
    fprintf(fid,'Alignment selection: %s\n',A.framing.selected_by);
    fprintf(fid,'CRC passes in first/second half: %d / %d\n', ...
        A.framing.training_crc_passes,A.framing.validation_crc_passes);
    fprintf(fid,'Independently validated selection: %d\n',A.framing.independently_validated);
    fprintf(fid,'Valid HDLC FCS: %d\n',A.framing.valid_hdlc_frames);
    S = A.packet_summary;
    fprintf(fid,'Ethernet %d; ARP %d; IPv4 %d; IPv6 %d; IEEE 802.3 %d\n', ...
        S.total,S.arp,S.ipv4,S.ipv6,S.ieee8023);
    if isempty(pcap), fprintf(fid,'No PCAP was created.\n'); else, fprintf(fid,'PCAP: %s\n',pcap); end
    fprintf(fid,['\nThe PCAP contains only frames with valid HDLC FCS, with that FCS removed.\n' ...
        'Time is relative to the first exported packet, based on the nominal Rs.\n' ...
        'The calendar date in the PCAP is not the measurement date.\n' ...
        'Boundary frames and corrupted frames may be missing.\n' ...
        'CRC ratios do not estimate BER or network packet loss.\n' ...
        'The meaning of the auxiliary 496-bit and 9-bit branches remains unresolved.\n' ...
        'The physical-layer standard and specific modem have not been identified.\n']);
end

function showDiagnostics(P,A,times,F,M)
    figure('Name','Downlink: decoding diagnostics');
    tiledlayout(2,2);
    nexttile; plot(real(P.constellation),imag(P.constellation),'.','MarkerSize',3);
    axis equal; grid on; xlabel('I'); ylabel('Q'); title('Symbols after synchronization');
    nexttile; plot(P.block_time_s,P.carrier_phase2_residual_rad); grid on;
    xlabel('Time in channel (s)'); ylabel('Squared-signal phase (rad)');
    title('Deviation from the linear carrier model');
    nexttile; plot(0:5119,A.training_score_all_origins); grid on;
    xline(M.frame_origin_zero_based,'--r');
    xlabel('Zero-based origin within the 5120-bit period'); ylabel('Fill-pattern mismatch');
    title('Auxiliary criterion; final selection uses CRC');
    nexttile;
    if isempty(times)
        text(0.1,0.5,'No valid Ethernet frames'); axis off;
    else
        stem(times,ones(size(times)),'.'); grid on;
        xlabel('Time relative to first packet (s)'); ylabel('Valid frame');
    end
    title(sprintf('FEC disagreement %.3f %% (not BER)',100*F.reencode_disagreement_not_BER));
end
