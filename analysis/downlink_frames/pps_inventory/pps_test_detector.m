% Standalone synthetic test. This is not calibration against measured data.
% Uses the batch-analysis detector and requires Signal Processing Toolbox.
clear; clc;
C = pps_tools('config');
fs = C.sample_rate_hz/C.decimation;
duration = 5;
t = (0:round(duration*fs)-1).'/fs;
rng(20261020);
noise = 0.02*(randn(size(t))+1j*randn(size(t)));
pulse = zeros(size(t));
for onset = [0.23 1.23 2.23 3.23 4.23]
    pulse(t>=onset & t<onset+0.1) = 1;
end
tone1 = exp(1j*2*pi*4312.5*t);
tone2 = exp(-1j*2*pi*7319.25*t);
names = {'PPS +4312.5 Hz','PPS -7319.25 Hz','Noise only', ...
    'Continuous tone','Single pulse','Broadband pulses','Two candidates','Missing first pulse'};
expected = {'present','present','not_detected','not_detected', ...
    'ambiguous','not_detected','ambiguous','present'};
frequency = [4312.5 -7319.25 NaN NaN NaN NaN NaN 4312.5];
for k = 1:numel(names)
    switch k
        case 1, x = noise+0.4*pulse.*tone1;
        case 2, x = noise+0.4*pulse.*tone2;
        case 3, x = noise;
        case 4, x = noise+0.4*tone1;
        case 5, x = noise+0.4*(t>0.23 & t<0.33).*tone1;
        case 6, x = noise.*(1+19*pulse);
        case 7
            x = noise+0.4*pulse.*tone1+0.35*pulse.*exp(-1j*2*pi*8123.25*t);
        case 8, x = noise+0.4*pulse.*(t>0.9).*tone1;
    end
    D = pps_tools('detect',single(x),fs,0,duration,C,false);
    assert(D.Status==string(expected{k}), ...
        'Test %s: expected %s, got %s.',names{k},expected{k},char(D.Status));
    if isfinite(frequency(k))
        assert(abs(D.Marker_Offset_Hz-frequency(k))<2, ...
            'Excessive frequency estimation error in test %s.',names{k});
    end
    fprintf('PASS %s | %s | offset %.3f Hz\n', ...
        names{k},char(D.Status),D.Marker_Offset_Hz);
end
% Integration test of the full RAW -> reading -> upfirdn -> detector path.
% This test also covers RAW input handling and filtering data types.
testRawInput(x,fs,C);
fprintf('\nAll synthetic tests, including RAW input handling, passed.\n');
fprintf('Before a full run, inspect measured PPS markers in the test PNG files.\n');

function testRawInput(x,fs,C)
C.sample_rate_hz = fs;
C.center_frequency_if_hz = C.nominal_marker_if_hz;
C.decimation = 1;
C.raw_chunk_samples = 250000;
path = [tempname '.raw'];
cleanup = onCleanup(@() delete(path)); %#ok<NASGU>
fid = fopen(path,'w','ieee-le');
assert(fid>=0,'Cannot create test RAW file.');
closer = onCleanup(@() fclose(fid));
count = fwrite(fid,int16([real(x) imag(x)].'*C.iq_scale),'int16');
assert(count==2*numel(x),'Incomplete test RAW write.');
clear closer;
info = struct('Measurement_ID',"test_RAW",'Source_File',string(path), ...
    'File_Name',"test_RAW.raw",'Day_Folder',"test",'File_Start_Time',NaT, ...
    'Filename_Time_Valid',false,'File_Size_Bytes',4*numel(x));
row = pps_tools('analyze',info,C,false);
assert(row.Status=="present",'RAW integration test failed: %s',char(row.Message));
assert(abs(row.Marker_Offset_Hz-4312.5)<2,'Frequency estimated from RAW data does not match.');
fprintf('PASS Interleaved int16 RAW reading and block upfirdn filtering\n');
end
