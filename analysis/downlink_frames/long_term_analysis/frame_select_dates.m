function names=frame_select_dates(names,startDate,endDate)
% Select recordings by the calendar date encoded in the RAW filename.
% Both endpoints are inclusive. No timezone conversion is performed.
names=string(names(:));
assert(isempty(startDate)==isempty(endDate),'Frame:DateRange', ...
 'Set both analysisStartDate and analysisEndDate, or leave both empty.');
if isempty(startDate), return; end
assert(isdatetime(startDate) && isscalar(startDate) && ~isnat(startDate) && ...
 isdatetime(endDate) && isscalar(endDate) && ~isnat(endDate), ...
 'Frame:DateRange','Date bounds must be valid scalar datetime values.');
assert(isempty(startDate.TimeZone) && isempty(endDate.TimeZone), ...
 'Frame:DateRange','Use dates without a timezone, matching the filename clock.');
first=dateshift(startDate,'start','day');
last=dateshift(endDate,'start','day');
assert(last>=first,'Frame:DateRange','The end date precedes the start date.');
recordDates=NaT(numel(names),1);
for k=1:numel(names)
 token=regexp(char(names(k)),'^\d+_\d{6}_(\d{6})\.raw$','tokens','once');
 if isempty(token), continue; end
 d=token{1};
 try
  candidate=datetime(['20' d(5:6) d(3:4) d(1:2)],'InputFormat','yyyyMMdd');
  % Reject invalid dates even if a parser normalizes them.
  if strcmp(char(string(candidate,'ddMMyy')),d), recordDates(k)=candidate; end
 catch
  % Invalid dates cannot be assigned to the requested calendar interval.
 end
end
invalid=isnat(recordDates);
if any(invalid)
 warning('Frame:InvalidFilenameDate', ...
  '%d inventory filenames have no valid date and were excluded by the date filter.',sum(invalid));
end
names=names(~invalid & recordDates>=first & recordDates<=last);
end
