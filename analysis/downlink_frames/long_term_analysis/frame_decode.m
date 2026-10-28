function varargout=frame_decode(action,varargin)
% Derived from supplied decode_downlink_to_pcap.m; HDLC FCS checked.
switch action
 case 'defaults', varargout{1}=defaults();
 case 'decode', varargout{1}=decode(varargin{:});
 case 'crc', varargout{1}=crc16X25(varargin{:});
 case 'hdlc', [varargout{1:nargout}]=decodeHDLC(varargin{:});
 case 'source_bit', varargout{1}=sourceBit(varargin{:});
 otherwise, error('Frame:Action','Unknown decoder action.');
end
end
function cfg=defaults()
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
cfg.timingLoopBandwidth = 0.0002;
cfg.discardInitialSymbols = 10000;
cfg.discardFinalSymbols = 1000;
cfg.tracebackDepth = 64;
cfg.fecGuardBits = 200;
cfg.fecCheckGuardSymbols = 1000;
cfg.alignmentCandidates = 12;
cfg.maxHDLCFrameBits = 131072;
cfg.showPlots = false;
cfg.saveSymbols = false; % true also saves symbolsBPSK in the MAT file, increasing file size

cfg.traceChunkSamples=2048;
cfg.traceGuardSymbols=32;
cfg.maxTimingDriftPpm=100;
cfg.timingStartupAllowanceSymbols=32;
cfg.timingChunkAllowanceSymbols=8;
end
function R=decode(path,offset,duration,cfg)
R=struct('status',"decode_error",'frames',emptyFrames(),'message',"");
try
 [iq,ch]=readRawChannel(path,offset,duration,cfg);
 [symbols,dm]=demodulateBPSK(iq,ch.sample_rate_hz,cfg); clear iq;
 [bits,fec]=decodeFEC(symbols,cfg); clear symbols;
 g=cfg.fecGuardBits;
 assert(numel(bits)>2*g+20+10*5120,'Insufficient decoded bits.');
 u=bits(g+1:end-g);
 d=xor(xor(u(21:end),u(18:end-3)),u(1:end-20));
 z=~xor(d(2:end),d(1:end-1));
 [~,~,~,packets,framing]=recoverFraming(z,cfg);
 F=emptyFrames();
 t0=(ch.raw_first_sample_zero_based+2*ch.discarded_decimated_samples ...
     -ch.fir_group_delay_raw_samples)/cfg.fsRaw;
 for k=1:numel(packets)
  v=packets(k).bytes(:);
  if numel(v)<14, continue; end
  typ=double(v(13))*256+double(v(14));
  if (typ>1500 && typ<1536) || (typ<=1500 && numel(v)<14+typ), continue; end
  q=sourceBit([packets(k).startMainBit packets(k).endMainBit]-1, ...
      framing.frame_origin_zero_based);
  % z(q) refers to latest decoded bit g+21+q, with 0-based indices.
  j=fec.pair_offset_symbols+2*(g+21+q)+1;
  assert(j(1)>=1 && j(2)+1<=numel(dm.symbol_time_lo_s),'Trace index outside symbols.');
  item=struct('bytes',v,'key',sprintf('%02X',v), ...
    'start_lo_s',t0+dm.symbol_time_lo_s(j(1)), ...
    'start_hi_s',t0+dm.symbol_time_hi_s(j(1)+1), ...
    'end_hi_s',t0+dm.symbol_time_hi_s(j(2)+1), ...
    'start_main_bit',packets(k).startMainBit,'end_main_bit',packets(k).endMainBit, ...
    'start_symbol_index',j(1),'end_symbol_index',j(2)+1);
  F(end+1)=item; %#ok<AGROW>
 end
 dm=rmfield(dm,{'symbol_time_lo_s','symbol_time_hi_s'});
 R.frames=F; R.channel=ch; R.demodulation=dm; R.fec=fec; R.framing=framing;
 R.status="decoded"; R.message="CRC-valid observations; zero frames does not prove absent traffic.";
catch ME
 if exist('ch','var'), R.channel=ch; end
 R.error_identifier=string(ME.identifier);
 if startsWith(string(ME.identifier),"Frame:Timing"), R.status="timing_unreliable"; end
 R.message=string(getReport(ME,'extended','hyperlinks','off'));
end
end
function F=emptyFrames()
F=struct('bytes',{},'key',{},'start_lo_s',{},'start_hi_s',{},'end_hi_s',{}, ...
 'start_main_bit',{},'end_main_bit',{},'start_symbol_index',{},'end_symbol_index',{});
end
function q=sourceBit(p,origin)
r=mod(p,4480);
q=origin+floor(p/4480)*5120+496+floor(r/280)*289+mod(r,280);
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
    x4 = single(resample(double(iq),p,q));
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
    cleanupSync=onCleanup(@()release(sync)); %#ok<NASGU>
    % Trace variable-rate synchronizer outputs to consumed input chunks.
    % Bounds are an engineering guard, not certified hardware timestamps.
    symbolsCell = cell(floor(numel(x4)/cfg.traceChunkSamples),1);
    loCell = symbolsCell; hiCell = symbolsCell;
    outputCounts=zeros(numel(symbolsCell),1,'uint16');
    producedCount=0;
    for j = 1:numel(symbolsCell)
        a = (j-1)*cfg.traceChunkSamples+1;
        b = min(j*cfg.traceChunkSamples,numel(x4));
        u = sync(x4(a:b));
        try
            frame_timing_guard('chunk',numel(u),b-a+1,cfg.samplesPerSymbol,cfg, ...
                producedCount<cfg.discardInitialSymbols);
        catch ME
            error(ME.identifier,'Timing input chunk %d, channel-relative %.9f to %.9f s: %s', ...
                j,(a-1)/(cfg.samplesPerSymbol*cfg.symbolRate), ...
                b/(cfg.samplesPerSymbol*cfg.symbolRate),ME.message);
        end
        outputCounts(j)=numel(u); symbolsCell{j} = u;
        producedCount=producedCount+numel(u);
        loCell{j} = repmat((a-1)/(cfg.samplesPerSymbol*cfg.symbolRate) ...
            -cfg.traceGuardSymbols/cfg.symbolRate,numel(u),1);
        hiCell{j} = repmat(b/(cfg.samplesPerSymbol*cfg.symbolRate) ...
            +cfg.traceGuardSymbols/cfg.symbolRate,numel(u),1);
    end
    symbols = vertcat(symbolsCell{:});
    timingInfo=frame_timing_guard('total',numel(symbols), ...
        numel(symbolsCell)*cfg.traceChunkSamples,cfg.samplesPerSymbol,cfg,false);
    traceLo = vertcat(loCell{:}); traceHi = vertcat(hiCell{:});
    assert(numel(symbols)>cfg.discardInitialSymbols+cfg.discardFinalSymbols+2000, ...
        'Too few symbols remain after timing recovery.');
    ixKeep = cfg.discardInitialSymbols+1:numel(symbols)-cfg.discardFinalSymbols;
    symbols = symbols(ixKeep); traceLo = traceLo(ixKeep); traceHi = traceHi(ixKeep);
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
        'discarded_final_symbols',cfg.discardFinalSymbols, ...
        'symbol_time_lo_s',traceLo,'symbol_time_hi_s',traceHi, ...
        'timing_guard',timingInfo,'timing_output_counts',outputCounts);
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
    packets = struct('bytes',{},'startMainBit',{},'endMainBit',{});
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
            packets(end).endMainBit = q+7;
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

