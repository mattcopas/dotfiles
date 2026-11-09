vim9script
# Calendar arithmetic on whole days ("abs" = days since 1970-01-01). Everything goes
# through civil dates, so timezones and daylight saving can't shift an agenda day.
# Names are fixed to English on purpose: org files must not change with the locale.

export const DAY_SHORT: list<string> = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
export const DAY_LONG: list<string> = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
export const MONTH_SHORT: list<string> = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
export const MONTH_LONG: list<string> = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

export def ToAbs(y: number, m: number, d: number): number
  var yy = m <= 2 ? y - 1 : y
  var era = yy / 400
  var yoe = yy - era * 400
  var doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
  var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146097 + doe - 719468
enddef

export def FromAbs(abs: number): dict<number>
  var z = abs + 719468
  var era = z / 146097
  var doe = z - era * 146097
  var yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  var doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  var mp = (5 * doy + 2) / 153
  var d = doy - (153 * mp + 2) / 5 + 1
  var m = mp + (mp < 10 ? 3 : -9)
  return {y: yoe + era * 400 + (m <= 2 ? 1 : 0), m: m, d: d}
enddef

# 0 = Sunday.
export def Weekday(abs: number): number
  return ((abs % 7) + 11) % 7
enddef

export def IsoWeek(abs: number): number
  var thursday = abs - ((Weekday(abs) + 6) % 7) + 3
  var y = FromAbs(thursday).y
  return (thursday - ToAbs(y, 1, 1)) / 7 + 1
enddef

def DaysInMonth(y: number, m: number): number
  return ToAbs(m == 12 ? y + 1 : y, m == 12 ? 1 : m + 1, 1) - ToAbs(y, m, 1)
enddef

# Adds months, clamping to the end of a shorter month as org does.
export def AddMonths(abs: number, months: number): number
  var c = FromAbs(abs)
  var total = c.y * 12 + (c.m - 1) + months
  var ny = total / 12
  var nm = total - ny * 12 + 1
  return ToAbs(ny, nm, min([c.d, DaysInMonth(ny, nm)]))
enddef

export def IsoDate(abs: number): string
  var c = FromAbs(abs)
  return printf('%d-%02d-%02d', c.y, c.m, c.d)
enddef

# Date plus weekday as org writes it, for example `2026-11-11 Wed`.
export def OrgDate(abs: number): string
  return IsoDate(abs) .. ' ' .. DAY_SHORT[Weekday(abs)]
enddef

# The current date and time. Tests set g:orgflow_test_clock to pin it.
export def Now(): dict<number>
  if exists('g:orgflow_test_clock')
    return g:orgflow_test_clock
  endif
  var p = split(strftime('%Y %m %d %H %M'))
  return {
    today: ToAbs(str2nr(p[0]), str2nr(p[1]), str2nr(p[2])),
    minutes: str2nr(p[3]) * 60 + str2nr(p[4]),
  }
enddef

def FormatCode(code: string, abs: number, minutes: number): string
  var c = FromAbs(abs)
  if code ==# 'a'
    return DAY_SHORT[Weekday(abs)]
  elseif code ==# 'A'
    return DAY_LONG[Weekday(abs)]
  elseif code ==# 'b'
    return MONTH_SHORT[c.m - 1]
  elseif code ==# 'B'
    return MONTH_LONG[c.m - 1]
  elseif code ==# 'd'
    return printf('%02d', c.d)
  elseif code ==# 'e'
    return printf('%2d', c.d)
  elseif code ==# 'H'
    return printf('%02d', minutes / 60)
  elseif code ==# 'M'
    return printf('%02d', minutes % 60)
  elseif code ==# 'm'
    return printf('%02d', c.m)
  elseif code ==# 'y'
    return printf('%02d', c.y % 100)
  elseif code ==# 'Y'
    return string(c.y)
  endif
  return '%'
enddef

# The subset of strftime that org-journal formats use.
export def FormatDate(format: string, abs: number, minutes: number = 0): string
  return substitute(format, '\C%\([aAbBdeHmMyY%]\)', (m) => FormatCode(m[1], abs, minutes), 'g')
enddef
