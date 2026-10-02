namespace System;

const int64 _TicksPerMillisecond = 10000;
const int64 _TicksPerSecond = 10000000;
const int64 _TicksPerMinute = 600000000;
const int64 _TicksPerHour = 36000000000;
const int64 _TicksPerDay = 864000000000;
const int64 _UnixEpochTicks = 621355968000000000;   // 1970-01-01 in ticks since 0001-01-01
const int64 _MaxDateTicks = 3155378975999999999;    // 9999-12-31 23:59:59.9999999

/// The days of the week, with the numbers of .NET (Sunday is 0).
enum DayOfWeek : int
{
    /// Sunday.
    Sunday = 0,
    /// Monday.
    Monday = 1,
    /// Tuesday.
    Tuesday = 2,
    /// Wednesday.
    Wednesday = 3,
    /// Thursday.
    Thursday = 4,
    /// Friday.
    Friday = 5,
    /// Saturday.
    Saturday = 6
}

// The Gregorian calendar as day numbers (days since 1970-01-01, negative before), after Howard Hinnant's algorithms.
struct _Calendar
{
    static int64 DaysFromCivil(int year, int month, int day)
    {
        int64 y = month <= 2 ? year - 1 : year;
        int64 era = (y >= 0 ? y : y - 399) / 400;
        int64 yoe = y - era * 400;
        int64 doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1;
        int64 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        return era * 146097 + doe - 719468;
    }

    // the year, month and day of a day number
    static void CivilFromDays(int64 days, ref int year, ref int month, ref int day)
    {
        int64 z = days + 719468;
        int64 era = (z >= 0 ? z : z - 146096) / 146097;
        int64 doe = z - era * 146097;
        int64 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        int64 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        int64 mp = (5 * doy + 2) / 153;
        day = (int)(doy - (153 * mp + 2) / 5 + 1);
        month = (int)(mp < 10 ? mp + 3 : mp - 9);
        year = (int)(yoe + era * 400 + (month <= 2 ? 1 : 0));
    }
}

/// A duration (or a time of day): a signed number of ticks of 100 ns, like .NET's `TimeSpan` (with methods instead of
/// properties).
///
/// ```
/// TimeSpan t = TimeSpan.Create(1, 30, 0);       // 01:30:00
/// Console.WriteLine(t.TotalMinutes());           // 90
/// TimeSpan left = deadline.Subtract(DateTime.Now());
/// ```
struct TimeSpan : IComparable<TimeSpan>, IEquatable<TimeSpan>, IHashable
{
    /// The duration in ticks of 100 ns.
    int64 Ticks;

    /// A duration of `ticks` ticks (100 ns each).
    static TimeSpan FromTicks(int64 ticks) { return TimeSpan { Ticks = ticks }; }
    /// A duration of `days` days (rounded to whole ticks).
    static TimeSpan FromDays(double days) { return _From(days, _TicksPerDay); }
    /// A duration of `hours` hours (rounded to whole ticks).
    static TimeSpan FromHours(double hours) { return _From(hours, _TicksPerHour); }
    /// A duration of `minutes` minutes (rounded to whole ticks).
    static TimeSpan FromMinutes(double minutes) { return _From(minutes, _TicksPerMinute); }
    /// A duration of `seconds` seconds (rounded to whole ticks).
    static TimeSpan FromSeconds(double seconds) { return _From(seconds, _TicksPerSecond); }
    /// A duration of `milliseconds` milliseconds (rounded to whole ticks).
    static TimeSpan FromMilliseconds(double milliseconds) { return _From(milliseconds, _TicksPerMillisecond); }

    static TimeSpan _From(double value, int64 scale)
    {
        double ticks = value * (double)scale;
        return TimeSpan { Ticks = (int64)(ticks < 0.0 ? ticks - 0.5 : ticks + 0.5) };
    }

    /// A duration of the given hours, minutes and seconds.
    static TimeSpan Create(int hours, int minutes, int seconds)
    {
        return Create(0, hours, minutes, seconds, 0);
    }

    /// A duration of the given days, hours, minutes and seconds.
    static TimeSpan Create(int days, int hours, int minutes, int seconds)
    {
        return Create(days, hours, minutes, seconds, 0);
    }

    /// A duration of the given days, hours, minutes, seconds and milliseconds.
    static TimeSpan Create(int days, int hours, int minutes, int seconds, int milliseconds)
    {
        return TimeSpan { Ticks = (int64)days * _TicksPerDay + (int64)hours * _TicksPerHour + (int64)minutes * _TicksPerMinute +
                                  (int64)seconds * _TicksPerSecond + (int64)milliseconds * _TicksPerMillisecond };
    }

    /// The days part of the duration. The parts have the sign of the whole: -1.02:03:04 has the days -1, the hours -2,
    /// ...
    int Days() { return (int)(Ticks / _TicksPerDay); }
    /// The hours part of the duration (-23 to 23).
    int Hours() { return (int)(Ticks / _TicksPerHour % 24); }
    /// The minutes part of the duration (-59 to 59).
    int Minutes() { return (int)(Ticks / _TicksPerMinute % 60); }
    /// The seconds part of the duration (-59 to 59).
    int Seconds() { return (int)(Ticks / _TicksPerSecond % 60); }
    /// The milliseconds part of the duration (-999 to 999).
    int Milliseconds() { return (int)(Ticks / _TicksPerMillisecond % 1000); }

    /// The whole duration in days, with fractions.
    double TotalDays() { return (double)Ticks / (double)_TicksPerDay; }
    /// The whole duration in hours, with fractions.
    double TotalHours() { return (double)Ticks / (double)_TicksPerHour; }
    /// The whole duration in minutes, with fractions.
    double TotalMinutes() { return (double)Ticks / (double)_TicksPerMinute; }
    /// The whole duration in seconds, with fractions.
    double TotalSeconds() { return (double)Ticks / (double)_TicksPerSecond; }
    /// The whole duration in milliseconds, with fractions.
    double TotalMilliseconds() { return (double)Ticks / (double)_TicksPerMillisecond; }

    /// The sum of this duration and `other`.
    TimeSpan Add(TimeSpan other) { return TimeSpan { Ticks = Ticks + other.Ticks }; }
    /// This duration minus `other`.
    TimeSpan Subtract(TimeSpan other) { return TimeSpan { Ticks = Ticks - other.Ticks }; }
    /// The duration with the opposite sign.
    TimeSpan Negate() { return TimeSpan { Ticks = -Ticks }; }
    /// The absolute value of the duration.
    TimeSpan Duration() { return TimeSpan { Ticks = Ticks < 0 ? -Ticks : Ticks }; }
    /// The duration times `factor` (rounded to whole ticks).
    TimeSpan Multiply(double factor) { return _From((double)Ticks * factor, 1); }

    /// Compares the lengths of the durations ([IComparable]).
    int CompareTo(TimeSpan other) { return Ticks < other.Ticks ? -1 : Ticks > other.Ticks ? 1 : 0; }
    /// Whether the durations are equal ([IEquatable]).
    bool Equals(TimeSpan other) { return Ticks == other.Ticks; }
    /// A hash code of the duration ([IHashable]).
    int GetHashCode() { return unchecked((int)Ticks ^ (int)(Ticks >> 32)); }

    /// The duration as text, like .NET's `"c"` format: `[-][d.]hh:mm:ss[.fffffff]`, e.g. `1.02:03:04.5000000`.
    string ToString()
    {
        int64 t = Ticks < 0 ? -Ticks : Ticks;
        var sb = StringBuilder.Create();
        if (Ticks < 0)
            sb.Append("-");
        int64 days = t / _TicksPerDay;
        if (days > 0)
        {
            sb.Append(days.ToString());
            sb.Append(".");
        }
        sb.Append(_TimeText.Pad((int)(t / _TicksPerHour % 24), 2));
        sb.Append(":");
        sb.Append(_TimeText.Pad((int)(t / _TicksPerMinute % 60), 2));
        sb.Append(":");
        sb.Append(_TimeText.Pad((int)(t / _TicksPerSecond % 60), 2));
        int64 fraction = t % _TicksPerSecond;
        if (fraction != 0)
        {
            sb.Append(".");
            sb.Append(_TimeText.Pad(fraction, 7));
        }
        return sb.ToString();
    }

}

// the numbers of dates and times as text
struct _TimeText
{
    // value with leading zeros to 'digits' digits
    static string Pad(int64 value, int digits)
    {
        string text = value.ToString();
        while (text.Length < digits)
            text = "0" + text;
        return text;
    }
}

/// A date and time of day, local or UTC.
///
/// ```
/// var now = DateTime.Now();
/// Console.WriteLine(now.ToString("yyyy-MM-dd HH:mm"));
/// var deadline = now.AddDays(3);
/// TimeSpan left = deadline.Subtract(now);           // 3.00:00:00
/// ```
///
/// A `DateTime` counts ticks of 100 ns from 0001-01-01 to 9999-12-31 (the Gregorian calendar), either in local time
/// or in UTC ([DateTime.IsUtc]); [DateTime.Now] is local, [DateTime.UtcNow] UTC. The clock and the time zone come from
/// the operating system. Like the .NET type, with methods instead of properties.
struct DateTime : IComparable<DateTime>, IEquatable<DateTime>, IHashable
{
    /// The ticks of 100 ns since 0001-01-01 00:00.
    int64 Ticks;
    /// Whether the time is UTC (otherwise it is local time).
    bool IsUtc;

    // ---- now ----

    /// The current date and time in UTC.
    static DateTime UtcNow()
    {
        return DateTime { Ticks = _Os.NowTicks() + _UnixEpochTicks, IsUtc = true };
    }

    /// The current date and time in local time.
    static DateTime Now()
    {
        return UtcNow().ToLocalTime();
    }

    /// today's date (local) at 00:00
    static DateTime Today()
    {
        return Now().Date();
    }

    // ---- creating ----

    /// A local date at 00:00.
    /// @panics when the date does not exist.
    static DateTime Create(int year, int month, int day)
    {
        return Create(year, month, day, 0, 0, 0, 0);
    }

    /// A local date and time.
    /// @panics when the date or time does not exist.
    static DateTime Create(int year, int month, int day, int hour, int minute, int second)
    {
        return Create(year, month, day, hour, minute, second, 0);
    }

    /// A local date and time with milliseconds.
    /// @panics when the date or time does not exist.
    static DateTime Create(int year, int month, int day, int hour, int minute, int second, int millisecond)
    {
        if (!_Valid(year, month, day, hour, minute, second, millisecond))
            Environment.Panic("invalid date or time: " + year.ToString() + "-" + month.ToString() + "-" + day.ToString() + " " +
                              hour.ToString() + ":" + minute.ToString() + ":" + second.ToString() + "." + millisecond.ToString());
        return DateTime { Ticks = _TicksOf(year, month, day) + (int64)hour * _TicksPerHour + (int64)minute * _TicksPerMinute +
                                  (int64)second * _TicksPerSecond + (int64)millisecond * _TicksPerMillisecond };
    }

    /// A date and time in UTC.
    /// @panics when the date or time does not exist.
    static DateTime CreateUtc(int year, int month, int day, int hour, int minute, int second)
    {
        var d = Create(year, month, day, hour, minute, second, 0);
        d.IsUtc = true;
        return d;
    }

    static bool _Valid(int year, int month, int day, int hour, int minute, int second, int millisecond)
    {
        return year >= 1 && year <= 9999 && month >= 1 && month <= 12 && day >= 1 && day <= DaysInMonth(year, month) &&
               hour >= 0 && hour < 24 && minute >= 0 && minute < 60 && second >= 0 && second < 60 &&
               millisecond >= 0 && millisecond < 1000;
    }

    // the ticks of 00:00 of a date
    static int64 _TicksOf(int year, int month, int day)
    {
        return _Calendar.DaysFromCivil(year, month, day) * _TicksPerDay + _UnixEpochTicks;
    }

    /// The UTC date and time `seconds` seconds after 1970-01-01 00:00 UTC (Unix time).
    static DateTime FromUnixSeconds(int64 seconds)
    {
        return DateTime { Ticks = seconds * _TicksPerSecond + _UnixEpochTicks, IsUtc = true };
    }

    /// The UTC date and time `milliseconds` milliseconds after 1970-01-01 00:00 UTC.
    static DateTime FromUnixMilliseconds(int64 milliseconds)
    {
        return DateTime { Ticks = milliseconds * _TicksPerMillisecond + _UnixEpochTicks, IsUtc = true };
    }

    /// The seconds since 1970-01-01 00:00 UTC (Unix time); a local time is converted to UTC first.
    int64 ToUnixSeconds()
    {
        return _FloorDiv(ToUniversalTime().Ticks - _UnixEpochTicks, _TicksPerSecond);
    }

    /// The milliseconds since 1970-01-01 00:00 UTC; a local time is converted to UTC first.
    int64 ToUnixMilliseconds()
    {
        return _FloorDiv(ToUniversalTime().Ticks - _UnixEpochTicks, _TicksPerMillisecond);
    }

    static int64 _FloorDiv(int64 a, int64 b)
    {
        int64 q = a / b;
        return a % b < 0 ? q - 1 : q;
    }

    /// Whether `year` is a leap year in the Gregorian calendar.
    static bool IsLeapYear(int year)
    {
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    /// The number of days of `month` (1 to 12) in `year`.
    static int DaysInMonth(int year, int month)
    {
        if (month == 2)
            return IsLeapYear(year) ? 29 : 28;
        return month == 4 || month == 6 || month == 9 || month == 11 ? 30 : 31;
    }

    // ---- parts ----

    /// The year (1 to 9999).
    int Year() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return y; }
    /// The month (1 to 12).
    int Month() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return m; }
    /// The day of the month (1 to 31).
    int Day() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return d; }
    /// The hour (0 to 23).
    int Hour() { return (int)(Ticks / _TicksPerHour % 24); }
    /// The minute (0 to 59).
    int Minute() { return (int)(Ticks / _TicksPerMinute % 60); }
    /// The second (0 to 59).
    int Second() { return (int)(Ticks / _TicksPerSecond % 60); }
    /// The millisecond (0 to 999).
    int Millisecond() { return (int)(Ticks / _TicksPerMillisecond % 1000); }

    void _Parts(ref int year, ref int month, ref int day)
    {
        _Calendar.CivilFromDays(Ticks / _TicksPerDay - 719162, ref year, ref month, ref day);
    }

    /// The day of the week.
    DayOfWeek DayOfWeek()
    {
        return (DayOfWeek)(int)((Ticks / _TicksPerDay + 1) % 7); // 0001-01-01 was a Monday
    }

    /// The day of the year (1 to 366).
    int DayOfYear()
    {
        int y = Year();
        return (int)((Ticks - _TicksOf(y, 1, 1)) / _TicksPerDay) + 1;
    }

    /// The date at 00:00 (the same zone).
    DateTime Date()
    {
        return DateTime { Ticks = Ticks - Ticks % _TicksPerDay, IsUtc = IsUtc };
    }

    /// The time since 00:00.
    TimeSpan TimeOfDay()
    {
        return TimeSpan { Ticks = Ticks % _TicksPerDay };
    }

    // ---- arithmetic ----

    /// The date and time `span` later (earlier for a negative span).
    DateTime Add(TimeSpan span) { return _Plus(span.Ticks); }
    /// The date and time `ticks` ticks of 100 ns later.
    DateTime AddTicks(int64 ticks) { return _Plus(ticks); }
    /// The date and time `days` days later (fractions are possible).
    DateTime AddDays(double days) { return _Plus(TimeSpan.FromDays(days).Ticks); }
    /// The date and time `hours` hours later.
    DateTime AddHours(double hours) { return _Plus(TimeSpan.FromHours(hours).Ticks); }
    /// The date and time `minutes` minutes later.
    DateTime AddMinutes(double minutes) { return _Plus(TimeSpan.FromMinutes(minutes).Ticks); }
    /// The date and time `seconds` seconds later.
    DateTime AddSeconds(double seconds) { return _Plus(TimeSpan.FromSeconds(seconds).Ticks); }
    /// The date and time `milliseconds` milliseconds later.
    DateTime AddMilliseconds(double milliseconds) { return _Plus(TimeSpan.FromMilliseconds(milliseconds).Ticks); }

    /// The date `months` whole months later: the day stays, or becomes the last day of a shorter month (Jan 31 + 1
    /// month is Feb 28 or 29).
    DateTime AddMonths(int months)
    {
        int y = 0;
        int m = 0;
        int d = 0;
        _Parts(ref y, ref m, ref d);
        int total = y * 12 + (m - 1) + months;
        int year = total / 12;
        int month = total % 12 + 1;
        if (year < 1 || year > 9999)
            Environment.Panic("the date is out of range (years 1 to 9999)");
        int last = DaysInMonth(year, month);
        if (d > last)
            d = last;
        return DateTime { Ticks = _TicksOf(year, month, d) + Ticks % _TicksPerDay, IsUtc = IsUtc };
    }

    /// The date `years` years later (Feb 29 becomes Feb 28 in a year that is not a leap year).
    DateTime AddYears(int years)
    {
        return AddMonths(years * 12);
    }

    DateTime _Plus(int64 ticks)
    {
        int64 t = Ticks + ticks;
        if (t < 0 || t > _MaxDateTicks)
            Environment.Panic("the date is out of range (years 1 to 9999)");
        return DateTime { Ticks = t, IsUtc = IsUtc };
    }

    /// The time from `other` to this date (both are taken in UTC if one of them is).
    TimeSpan Subtract(DateTime other)
    {
        if (IsUtc != other.IsUtc)
            return TimeSpan { Ticks = ToUniversalTime().Ticks - other.ToUniversalTime().Ticks };
        return TimeSpan { Ticks = Ticks - other.Ticks };
    }

    /// The date and time `span` earlier.
    DateTime Subtract(TimeSpan span)
    {
        return _Plus(-span.Ticks);
    }

    // ---- time zones ----

    /// The same instant in UTC (a UTC value stays as it is). Near a change of daylight saving time, the offset of the
    /// result decides.
    DateTime ToUniversalTime()
    {
        if (IsUtc)
            return this;
        // the offset at the local time; near a change of daylight saving time, the offset of the result decides
        int64 guess = (Ticks - _UnixEpochTicks) / _TicksPerSecond;
        int offset = _Os.LocalOffsetSeconds(guess);
        offset = _Os.LocalOffsetSeconds(guess - offset);
        return DateTime { Ticks = Ticks - (int64)offset * _TicksPerSecond, IsUtc = true };
    }

    /// The same instant in local time (a local value stays as it is).
    DateTime ToLocalTime()
    {
        if (!IsUtc)
            return this;
        int offset = _Os.LocalOffsetSeconds(_FloorDiv(Ticks - _UnixEpochTicks, _TicksPerSecond));
        return DateTime { Ticks = Ticks + (int64)offset * _TicksPerSecond, IsUtc = false };
    }

    // ---- comparing ----

    /// compares the instants (a local and a UTC value are compared in UTC)
    int CompareTo(DateTime other)
    {
        int64 a = Ticks;
        int64 b = other.Ticks;
        if (IsUtc != other.IsUtc)
        {
            a = ToUniversalTime().Ticks;
            b = other.ToUniversalTime().Ticks;
        }
        return a < b ? -1 : a > b ? 1 : 0;
    }

    /// Whether both are the same instant and zone ([IEquatable]).
    bool Equals(DateTime other) { return CompareTo(other) == 0; }
    /// A hash code of the date and time ([IHashable]).
    int GetHashCode() { return unchecked((int)Ticks ^ (int)(Ticks >> 32)); }

    // ---- text ----

    /// The date and time as text: `2026-10-01 14:05:09`.
    string ToString()
    {
        return ToString("yyyy-MM-dd HH:mm:ss");
    }

    /// ISO 8601 with the zone: 2026-10-01T12:05:09.250Z (UTC) or 2026-10-01T14:05:09.250+02:00 (local)
    string ToIsoString()
    {
        string text = ToString("yyyy-MM-ddTHH:mm:ss.fff");
        if (IsUtc)
            return text + "Z";
        int offset = (int)(Subtract(ToUniversalTime()).Ticks / _TicksPerMinute);
        string sign = offset < 0 ? "-" : "+";
        if (offset < 0)
            offset = -offset;
        return text + sign + _TimeText.Pad(offset / 60, 2) + ":" + _TimeText.Pad(offset % 60, 2);
    }

    /// The date and time in a custom format: `d.ToString("dd.MM.yyyy HH:mm")`.
    ///
    /// | Letters | Meaning |
    /// |---|---|
    /// | `yyyy` `yy` | the year with 4 or 2 digits |
    /// | `MMMM` `MMM` `MM` `M` | the month: its name, the short name, 2 digits, the number |
    /// | `dddd` `ddd` `dd` `d` | the day: the name of the weekday, its short name, 2 digits, the number |
    /// | `HH` `H` | the hour, 0 to 23 (2 digits or the number) |
    /// | `hh` `h` | the hour, 1 to 12 |
    /// | `mm` `m` | the minute |
    /// | `ss` `s` | the second |
    /// | `fff` `ff` `f` | fractions of a second |
    /// | `tt` | `AM` or `PM` |
    ///
    /// Other letters and text in `'...'` are copied; `\x` copies `x`. The names are English.
    string ToString(string format)
    {
        int y = 0;
        int mo = 0;
        int d = 0;
        _Parts(ref y, ref mo, ref d);
        var sb = StringBuilder.Create();
        int i = 0;
        while (i < format.Length)
        {
            char c = format[i];
            int n = 1;
            while (i + n < format.Length && format[i + n] == c)
                n += 1;
            if (c == '\\' && i + 1 < format.Length)
            {
                sb.Append(format[i + 1]);
                i += 2;
                continue;
            }
            if (c == '\'')
            {
                int end = format.IndexOf('\'', i + 1);
                if (end < 0)
                    end = format.Length;
                sb.Append(format.Substring(i + 1, end - i - 1));
                i = end + 1;
                continue;
            }
            if (c == 'y')
                sb.Append(n <= 2 ? _TimeText.Pad(y % 100, 2) : _TimeText.Pad(y, n));
            else if (c == 'M')
                sb.Append(n >= 4 ? _MonthNames[mo - 1] : n == 3 ? _MonthNames[mo - 1].Substring(0, 3).ToString() : _TimeText.Pad(mo, n));
            else if (c == 'd')
            {
                string day = _DayNames[(int)DayOfWeek()];
                sb.Append(n >= 4 ? day : n == 3 ? day.Substring(0, 3).ToString() : _TimeText.Pad(d, n));
            }
            else if (c == 'H')
                sb.Append(_TimeText.Pad(Hour(), n > 2 ? 2 : n));
            else if (c == 'h')
            {
                int h = Hour() % 12;
                sb.Append(_TimeText.Pad(h == 0 ? 12 : h, n > 2 ? 2 : n));
            }
            else if (c == 'm')
                sb.Append(_TimeText.Pad(Minute(), n > 2 ? 2 : n));
            else if (c == 's')
                sb.Append(_TimeText.Pad(Second(), n > 2 ? 2 : n));
            else if (c == 'f')
            {
                int digits = n > 7 ? 7 : n;
                int64 fraction = Ticks % _TicksPerSecond;
                for (var k = digits; k < 7; k += 1)
                    fraction = fraction / 10;
                sb.Append(_TimeText.Pad(fraction, digits));
            }
            else if (c == 't')
                sb.Append(Hour() < 12 ? "AM" : "PM");
            else
            {
                for (var k = 0; k < n; k += 1)
                    sb.Append(c);
            }
            i += n;
        }
        return sb.ToString();
    }

    /// Reads a date and time: `yyyy-MM-dd`, optionally followed by `T` or a space and `HH:mm[:ss[.fffffff]]`, then `Z`
    /// (UTC) or `+hh:mm` / `-hh:mm` (UTC, converted from that offset). Without a zone the time is local.
    /// @error ParseError.Invalid the text has another format.
    /// @error ParseError.OutOfRange the date or time does not exist.
    static ParseError<DateTime> Parse(string text)
    {
        var p = _DateParser { Text = text.Trim().ToString(), Pos = 0 };
        int year = p.Number(4);
        if (year < 0 || !p.Skip('-'))
            return error("'" + text + "' is not a date (yyyy-MM-dd)", ParseError.Invalid);
        int month = p.Number(2);
        if (month < 0 || !p.Skip('-'))
            return error("'" + text + "' is not a date (yyyy-MM-dd)", ParseError.Invalid);
        int day = p.Number(2);
        if (day < 0)
            return error("'" + text + "' is not a date (yyyy-MM-dd)", ParseError.Invalid);
        int hour = 0;
        int minute = 0;
        int second = 0;
        int64 fraction = 0;
        if (p.Skip('T') || p.Skip(' '))
        {
            hour = p.Number(2);
            if (hour < 0 || !p.Skip(':'))
                return error("'" + text + "' has no valid time (HH:mm[:ss])", ParseError.Invalid);
            minute = p.Number(2);
            if (minute < 0)
                return error("'" + text + "' has no valid time (HH:mm[:ss])", ParseError.Invalid);
            if (p.Skip(':'))
            {
                second = p.Number(2);
                if (second < 0)
                    return error("'" + text + "' has no valid time (HH:mm[:ss])", ParseError.Invalid);
                if (p.Skip('.'))
                {
                    int digits = 0;
                    while (p.Pos < p.Text.Length && Char.IsDigit(p.Text[p.Pos]))
                    {
                        if (digits < 7)
                        {
                            fraction = fraction * 10 + (int64)(p.Text[p.Pos] - '0');
                            digits += 1;
                        }
                        p.Pos += 1;
                    }
                    if (digits == 0)
                        return error("'" + text + "' has no digits after the '.'", ParseError.Invalid);
                    while (digits < 7)
                    {
                        fraction = fraction * 10;
                        digits += 1;
                    }
                }
            }
        }
        if (!_Valid(year, month, day, hour, minute, second, 0))
            return error("'" + text + "' is not a valid date or time", ParseError.OutOfRange);
        var result = DateTime { Ticks = _TicksOf(year, month, day) + (int64)hour * _TicksPerHour + (int64)minute * _TicksPerMinute +
                                        (int64)second * _TicksPerSecond + fraction };
        if (p.Skip('Z'))
            result.IsUtc = true;
        else if (p.Pos < p.Text.Length && (p.Text[p.Pos] == '+' || p.Text[p.Pos] == '-'))
        {
            bool negative = p.Text[p.Pos] == '-';
            p.Pos += 1;
            int oh = p.Number(2);
            if (oh < 0 || !p.Skip(':'))
                return error("'" + text + "' has no valid zone (+hh:mm)", ParseError.Invalid);
            int om = p.Number(2);
            if (om < 0)
                return error("'" + text + "' has no valid zone (+hh:mm)", ParseError.Invalid);
            int64 offset = (int64)(oh * 60 + om) * _TicksPerMinute;
            result.Ticks = negative ? result.Ticks + offset : result.Ticks - offset;
            result.IsUtc = true;
        }
        if (p.Pos != p.Text.Length)
            return error("'" + text + "' has more text after the date", ParseError.Invalid);
        return result;
    }
}

const ReadOnlySlice<string> _MonthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                           "September", "October", "November", "December"];
const ReadOnlySlice<string> _DayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

// reads the parts of DateTime.Parse
struct _DateParser
{
    string Text;
    int Pos;

    // exactly 'digits' digits (-1 if they are not there)
    int Number(int digits)
    {
        int value = 0;
        for (var i = 0; i < digits; i += 1)
        {
            if (Pos >= Text.Length || !Char.IsDigit(Text[Pos]))
                return -1;
            value = value * 10 + (Text[Pos] - '0');
            Pos += 1;
        }
        return value;
    }

    bool Skip(char c)
    {
        if (Pos < Text.Length && Text[Pos] == c)
        {
            Pos += 1;
            return true;
        }
        return false;
    }
}

/// Measures elapsed time with the monotonic clock of the system (not affected by changes of the time of day).
struct Stopwatch
{
    int64 _start;     // MonotonicTicks when it was started (while running)
    int64 _elapsed;   // the time of the earlier runs
    bool _running;

    /// A new stopwatch that is running.
    static Stopwatch StartNew()
    {
        var sw = Stopwatch { };
        sw.Start();
        return sw;
    }

    /// Starts measuring (or continues after [Stopwatch.Stop]).
    void Start()
    {
        if (!_running)
        {
            _start = _Os.MonotonicTicks();
            _running = true;
        }
    }

    /// Stops measuring; the elapsed time stays.
    void Stop()
    {
        if (_running)
        {
            _elapsed += _Os.MonotonicTicks() - _start;
            _running = false;
        }
    }

    /// Stops measuring and sets the elapsed time to zero.
    void Reset()
    {
        _elapsed = 0;
        _running = false;
    }

    /// Sets the elapsed time to zero and starts measuring.
    void Restart()
    {
        _elapsed = 0;
        _start = _Os.MonotonicTicks();
        _running = true;
    }

    /// Whether the stopwatch is measuring.
    bool IsRunning() { return _running; }

    /// The elapsed time in ticks of 100 ns.
    int64 ElapsedTicks()
    {
        return _running ? _elapsed + _Os.MonotonicTicks() - _start : _elapsed;
    }

    /// The elapsed time in milliseconds.
    int64 ElapsedMilliseconds() { return ElapsedTicks() / _TicksPerMillisecond; }

    /// The elapsed time.
    TimeSpan Elapsed() { return TimeSpan { Ticks = ElapsedTicks() }; }
}
