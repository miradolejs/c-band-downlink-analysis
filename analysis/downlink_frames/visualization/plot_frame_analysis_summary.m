function R = plot_frame_analysis_summary(inputDirectory, outputDirectory)
% PLOT_FRAME_ANALYSIS_SUMMARY Plot completed CSV results without RAW reading or decoding.
% R = plot_frame_analysis_summary;                 % select the input folder using a dialog
% R = plot_frame_analysis_summary('D:\...\FRAME_FULL_...');
% MATLAB R2020b+; no additional toolboxes required.
if nargin < 1 || isempty(inputDirectory)
    inputDirectory = uigetdir(pwd, 'Select the folder containing all_seconds.csv and pair_audit.csv');
    if isequal(inputDirectory, 0), R = []; return; end
end
if nargin < 2 || isempty(outputDirectory)
    outputDirectory = fullfile(inputDirectory, ['FIGURES_' datestr(now,'yyyymmdd_HHMMSS')]);
end
S = readtable(findCSV(inputDirectory, 'all_seconds'), 'TextType','string');
A = readtable(findCSV(inputDirectory, 'pair_audit'), 'TextType','string');
need(S, {'File_Name','Second','Status','City_Total','Village_Total','Common','City_Only','Village_Only'});
need(A, {'File_Name','Status'});
assert(numel(unique(string(A.File_Name))) == height(A), 'Duplicate filenames in pair_audit.csv.');
assert(height(unique(S(:,{'File_Name','Second'}))) == height(S), 'Duplicate filename/second identifiers in all_seconds.csv.');
S = S(string(S.Status) == "analyzed", :);
assert(~isempty(S), 'No analyzed seconds were found.');
counts = [S.City_Total S.Village_Total S.Common S.City_Only S.Village_Only];
assert(all(isfinite(counts(:))) && all(counts(:)>=0), 'Invalid frame counts.');
assert(all(S.City_Total == S.Common+S.City_Only) && ...
    all(S.Village_Total == S.Common+S.Village_Only), 'Frame-count identities do not match.');
assert(all(ismember(string(S.File_Name),string(A.File_Name))), 'Some per-second filenames are missing from pair_audit.csv.');
A.Record_Time = fileTimes(A.File_Name);
A = sortrows(A,'Record_Time');
n = height(A);
P = table(string(A.File_Name), A.Record_Time, string(A.Status), ...
    'VariableNames',{'File_Name','Record_Time','Status'});
P.Day = dateshift(P.Record_Time,'start','day');
for v = {'Analyzed_Seconds','City_Total','Village_Total','Common','City_Only','Village_Only'}
    P.(v{1}) = zeros(n,1);
end
P.Common_Over_Village = nan(n,1);
P.Second_Ratio_SD_pp = nan(n,1);
P.Second_Ratio_Min_pct = nan(n,1);
P.Second_Ratio_Max_pct = nan(n,1);
P.City_SNR_dB = nan(n,1); P.Village_SNR_dB = nan(n,1);
for k = 1:n
    B = S(string(S.File_Name)==P.File_Name(k),:);
    P.Analyzed_Seconds(k) = height(B);
    for v = {'City_Total','Village_Total','Common','City_Only','Village_Only'}
        P.(v{1})(k) = sum(B.(v{1}));
    end
    P.Common_Over_Village(k) = ratio(P.Common(k),P.Village_Total(k));
    b = 100*ratio(B.Common,B.Village_Total); b = b(isfinite(b));
    if ~isempty(b)
        P.Second_Ratio_Min_pct(k) = min(b); P.Second_Ratio_Max_pct(k) = max(b);
        if numel(b)>=2, P.Second_Ratio_SD_pp(k) = std(b); end
    end
    for station = {'City','Village'}
        outputName = [station{1} '_SNR_dB'];
        auditName = [station{1} '_Record_SNR_dB'];
        if ismember(auditName,A.Properties.VariableNames)
            P.(outputName)(k) = A.(auditName)(k);
        elseif ismember(outputName,B.Properties.VariableNames)
            x = B.(outputName); x = x(isfinite(x));
            if ~isempty(x), P.(outputName)(k) = 10*log10(mean(10.^(x/10))); end
        end
    end
end
days = unique(P.Day); nd = numel(days);
D = table(days,'VariableNames',{'Day'});
for v = {'Pairs_Total','Pairs_Analyzed','Pairs_SNR_Skipped','Pairs_PPS_Skipped','Pairs_Other', ...
        'Analyzed_Seconds','City_Total','Village_Total','Common','City_Only','Village_Only'}
    D.(v{1}) = zeros(nd,1);
end
D.Common_Over_Village = nan(nd,1);
used = P.Analyzed_Seconds>0;
noise = ~used & contains(lower(P.Status),'likely_noise');
ppsEvidence = contains(lower(P.Status),'pps');
if ismember('Message',A.Properties.VariableNames)
    % Match PPS rejection messages emitted by the paired-analysis functions.
    messages = lower(string(A.Message));
    for phrase = {'missing or rejected pps','four pps pulses', ...
            'last four pps','pps pairing','satsync:pps'}
        ppsEvidence = ppsEvidence | contains(messages,phrase{1});
    end
end
pps = ~used & ~noise & ppsEvidence;
other = ~used & ~noise & ~pps;
for k = 1:nd
    z = P.Day==days(k);
    D.Pairs_Total(k)=sum(z); D.Pairs_Analyzed(k)=sum(z&used);
    D.Pairs_SNR_Skipped(k)=sum(z&noise); D.Pairs_PPS_Skipped(k)=sum(z&pps);
    D.Pairs_Other(k)=sum(z&other);
    for v = {'Analyzed_Seconds','City_Total','Village_Total','Common','City_Only','Village_Only'}
        D.(v{1})(k)=sum(P.(v{1})(z));
    end
    D.Common_Over_Village(k)=ratio(D.Common(k),D.Village_Total(k));
end
G=table(height(P),sum(used),sum(noise),sum(pps),sum(other),height(S), ...
    sum(S.City_Total),sum(S.Village_Total),sum(S.Common),sum(S.City_Only),sum(S.Village_Only), ...
    ratio(sum(S.Common),sum(S.Village_Total)), ...
    'VariableNames',{'Pairs_Total','Pairs_Analyzed','Pairs_SNR_Skipped','Pairs_PPS_Skipped', ...
    'Pairs_Other','Analyzed_Seconds','City_Total','Village_Total','Common','City_Only', ...
    'Village_Only','Common_Over_Village'});
% Optionally validate summary.csv; plots are always derived from per-second results.
summaryFiles=dir(fullfile(inputDirectory,'summary*.csv'));
if numel(summaryFiles)==1
    Q=readtable(fullfile(summaryFiles.folder,summaryFiles.name));
    for v={'Analyzed_Seconds','City_Total','Village_Total','Common','City_Only','Village_Only'}
        if ismember(v{1},Q.Properties.VariableNames)
            assert(height(Q)==1 && Q.(v{1})(1)==G.(v{1})(1), ...
                'summary.csv does not match all_seconds.csv: %s',v{1});
        end
    end
end
if ~isfolder(outputDirectory), mkdir(outputDirectory); end
writetable(P,fullfile(outputDirectory,'records_summary.csv'));
writetable(D,fullfile(outputDirectory,'daily_summary.csv'));
writetable(G,fullfile(outputDirectory,'global_summary.csv'));
city=[0.80 0.25 0.16]; village=[0.10 0.43 0.69]; common=[0.12 0.57 0.37];
labels=cellstr(datestr(D.Day,'dd.mm.yyyy')); x=(1:nd)';

f=newFigure('Time series',1250,900); tl=tiledlayout(f,3,1,'TileSpacing','compact');
ax=nexttile(tl); plot(ax,P.Record_Time,100*P.Common_Over_Village,'o-', ...
    'Color',common,'MarkerSize',3,'LineWidth',0.8); hold(ax,'on');
if isfinite(G.Common_Over_Village)
    yline(ax,100*G.Common_Over_Village,'--',sprintf('Global %.2f %%',100*G.Common_Over_Village));
end
ylabel(ax,'Common / village (%)'); ylim(ax,[0 105]); grid(ax,'on');
title(ax,'One point per analyzed record; ratio of summed frame counts');
ax=nexttile(tl); plot(ax,P.Record_Time,P.City_SNR_dB,'-','Color',city); hold(ax,'on');
plot(ax,P.Record_Time,P.Village_SNR_dB,'-','Color',village); yline(ax,0,':');
ylabel(ax,'SNR (dB), 1 MHz'); legend(ax,{'City','Village'},'Location','best'); grid(ax,'on');
ax=nexttile(tl); a=ratio(P.City_Total,P.Analyzed_Seconds); b=ratio(P.Village_Total,P.Analyzed_Seconds);
c=ratio(P.Common,P.Analyzed_Seconds);
plot(ax,P.Record_Time,a,'-','Color',city); hold(ax,'on');
plot(ax,P.Record_Time,b,'-','Color',village); plot(ax,P.Record_Time,c,'-','Color',common);
ylabel(ax,'Frames / analyzed second'); xlabel(ax,'Recording time (file timestamp)');
legend(ax,{'City','Village','Common'},'Location','best'); grid(ax,'on');
formatTimes(tl); title(tl,'Frame analysis - time series'); savePlot(f,outputDirectory,'01_time_series');

f=newFigure('Daily summary',1150,820); tl=tiledlayout(f,2,1,'TileSpacing','compact');
ax=nexttile(tl); bar(ax,x,100*D.Common_Over_Village,'FaceColor',common); hold(ax,'on');
if isfinite(G.Common_Over_Village)
    yline(ax,100*G.Common_Over_Village,'--',sprintf('Global %.2f %%',100*G.Common_Over_Village));
end
set(ax,'XTick',x,'XTickLabel',labels); ylim(ax,[0 105]); ylabel(ax,'Common / village (%)'); grid(ax,'on');
for k=1:nd
    if isfinite(D.Common_Over_Village(k))
        text(ax,k,100*D.Common_Over_Village(k)+2,sprintf('%.2f%%',100*D.Common_Over_Village(k)), ...
            'HorizontalAlignment','center');
    end
end
title(ax,'Daily ratio = sum(common) / sum(village)');
ax=nexttile(tl); h=bar(ax,x,[ratio(D.City_Total,D.Analyzed_Seconds), ...
    ratio(D.Village_Total,D.Analyzed_Seconds),ratio(D.Common,D.Analyzed_Seconds)],'grouped');
h(1).FaceColor=city; h(2).FaceColor=village; h(3).FaceColor=common;
set(ax,'XTick',x,'XTickLabel',labels); ylabel(ax,'Frames / analyzed second'); xlabel(ax,'Day');
legend(ax,{'City','Village','Common'},'Location','best'); grid(ax,'on');
title(tl,'Daily frame summary'); savePlot(f,outputDirectory,'02_daily_summary');

f=newFigure('SNR relationship',1200,540); tl=tiledlayout(f,1,2,'TileSpacing','compact');
for k=1:2
    ax=nexttile(tl); if k==1, snr=P.City_SNR_dB; name='City'; else, snr=P.Village_SNR_dB; name='Village'; end
    z=used & isfinite(snr) & isfinite(P.Common_Over_Village);
    scatter(ax,snr(z),100*P.Common_Over_Village(z),24,datenum(P.Day(z)),'filled');
    xlabel(ax,[name ' record SNR (dB), 1 MHz']); ylabel(ax,'Common / village (%)');
    ylim(ax,[0 105]); grid(ax,'on'); title(ax,'One point per record');
    if any(z)
        cb=colorbar(ax); cb.Ticks=datenum(days); cb.TickLabels=labels;
        if nd>1, caxis(ax,[datenum(days(1)) datenum(days(end))]); end
    end
end
colormap(f,parula(max(nd,2))); title(tl,'Frame agreement versus SNR (descriptive association)');
savePlot(f,outputDirectory,'03_snr_relationship');

f=newFigure('Coverage',1100,650); ax=axes(f);
h=bar(ax,x,[D.Pairs_Analyzed D.Pairs_SNR_Skipped D.Pairs_PPS_Skipped D.Pairs_Other],'stacked');
h(1).FaceColor=common; h(2).FaceColor=[0.65 0.68 0.72];
h(3).FaceColor=[0.93 0.63 0.15]; h(4).FaceColor=city;
set(ax,'XTick',x,'XTickLabel',labels); ylabel(ax,'Number of paired records'); xlabel(ax,'Day');
legend(ax,{'Analyzed','Skipped: likely noise (SNR)','Skipped: PPS','Other / no analyzed seconds'}, ...
    'Location','southoutside'); grid(ax,'on');
title(ax,sprintf('Coverage: %d / %d paired records, %d analyzed seconds',sum(used),n,height(S)));
savePlot(f,outputDirectory,'04_coverage');

f=newFigure('Within-record variability',1150,560); tl=tiledlayout(f,1,2,'TileSpacing','compact');
ax=nexttile(tl); z=used & isfinite(P.Second_Ratio_SD_pp);
histogram(ax,P.Second_Ratio_SD_pp(z),20,'FaceColor',village);
xlabel(ax,'Within-record standard deviation (percentage points)'); ylabel(ax,'Number of records');
grid(ax,'on'); title(ax,'Variation across analyzed seconds');
ax=nexttile(tl); scatter(ax,100*P.Common_Over_Village(z),P.Second_Ratio_SD_pp(z), ...
    22,ratio(P.Village_Total(z),P.Analyzed_Seconds(z)),'filled');
xlabel(ax,'Record common / village (%)'); ylabel(ax,'Within-record SD (percentage points)');
cb=colorbar(ax); cb.Label.String='Village frames / analyzed second'; grid(ax,'on');
title(ax,'Seconds with zero village frames are undefined');
title(tl,'Within-record variability (selected seconds only)');
savePlot(f,outputDirectory,'05_within_record_variability');

R=struct('outputDirectory',outputDirectory,'records',P,'daily',D,'global',G);
save(fullfile(outputDirectory,'graph_summary.mat'),'R');
fprintf('\nDone: %s\n',outputDirectory);
fprintf('Included %d/%d pairs, %d seconds. Common/village: %.2f %%\n',sum(used),n,height(S),100*G.Common_Over_Village);
end

function path=findCSV(folder,base)
path=fullfile(folder,[base '.csv']); if isfile(path), return; end
q=dir(fullfile(folder,[base '*.csv']));
assert(numel(q)==1,'The folder must contain exactly one %s*.csv file (or an exact %s.csv match).',base,base);
path=fullfile(q.folder,q.name);
end
function need(T,names)
assert(all(ismember(names,T.Properties.VariableNames)),'CSV is missing required columns: %s',strjoin(names,', '));
end
function t=fileTimes(names)
t=NaT(numel(names),1);
for k=1:numel(names)
    q=regexp(char(names(k)),'^\d+_(\d{6})_(\d{6})\.raw$','tokens','once');
    assert(~isempty(q),'Unrecognized RAW filename format: %s',char(names(k)));
    d=q{2}; h=q{1};
    t(k)=datetime(2000+str2double(d(5:6)),str2double(d(3:4)),str2double(d(1:2)), ...
        str2double(h(1:2)),str2double(h(3:4)),str2double(h(5:6)));
end
end
function y=ratio(a,b)
y=nan(size(a)); z=isfinite(a)&isfinite(b)&b>0; y(z)=a(z)./b(z);
end
function f=newFigure(name,w,h)
f=figure('Name',name,'Color','w','Position',[80 60 w h]);
end
function formatTimes(tl)
axesList=findall(tl,'Type','axes');
for k=1:numel(axesList), xtickformat(axesList(k),'dd.MM.yyyy HH:mm'); end
end
function savePlot(f,folder,name)
axesList=findall(f,'Type','axes');
for k=1:numel(axesList)
    axesList(k).FontSize=10;
    if isprop(axesList(k),'Toolbar') && ~isempty(axesList(k).Toolbar)
        axesList(k).Toolbar.Visible='off';
    end
end
set(f,'InvertHardcopy','off'); drawnow;
target=findall(f,'Type','tiledlayout');
if isempty(target), target=axesList(1); else, target=target(1); end
exportgraphics(target,fullfile(folder,[name '.png']),'Resolution',250);
exportgraphics(target,fullfile(folder,[name '.pdf']),'ContentType','vector');
savefig(f,fullfile(folder,[name '.fig']));
end
