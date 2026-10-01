// Dates, times and durations: DateTime, TimeSpan, DayOfWeek and Stopwatch (like their .NET namesakes, with methods
// instead of properties).
//
//     var now = DateTime.Now();
//     Console.WriteLine(now.ToString("yyyy-MM-dd HH:mm"));
//     var deadline = now.AddDays(3);
//     TimeSpan left = deadline.Subtract(now);           // 3.00:00:00
//     var sw = Stopwatch.StartNew();
//     ...
//     Console.WriteLine(sw.ElapsedMilliseconds());
//
// Both count in ticks of 100 ns. A DateTime is a date and time of day from 0001-01-01 to 9999-12-31 (the Gregorian
// calendar), either in local time or in UTC (IsUtc); Now() is local, UtcNow() UTC. The clock and the time zone come from
// the operating system layer (_Os, stdlib/os/).

namespace System;

const int64 _TicksPerMillisecond = 10000;
const int64 _TicksPerSecond = 10000000;
const int64 _TicksPerMinute = 600000000;
const int64 _TicksPerHour = 36000000000;
const int64 _TicksPerDay = 864000000000;
const int64 _UnixEpochTicks = 621355968000000000;   // 1970-01-01 in ticks since 0001-01-01
const int64 _MaxDateTicks = 3155378975999999999;    // 9999-12-31 23:59:59.9999999

enum DayOfWeek : int
{
    Sunday = 0,
    Monday = 1,
    Tuesday = 2,
    Wednesday = 3,
    Thursday = 4,
    Friday = 5,
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

// A duration (or a time of day): a signed number of ticks (100 ns).
struct TimeSpan : IComparable<TimeSpan>, IEquatable<TimeSpan>, IHashable
{
    int64 Ticks;

    static TimeSpan FromTicks(int64 ticks) { return TimeSpan { Ticks = ticks }; }
    static TimeSpan FromDays(double days) { return _From(days, _TicksPerDay); }
    static TimeSpan FromHours(double hours) { return _From(hours, _TicksPerHour); }
    static TimeSpan FromMinutes(double minutes) { return _From(minutes, _TicksPerMinute); }
    static TimeSpan FromSeconds(double seconds) { return _From(seconds, _TicksPerSecond); }
    static TimeSpan FromMilliseconds(double milliseconds) { return _From(milliseconds, _TicksPerMillisecond); }

    static TimeSpan _From(double value, int64 scale)
    {
        double ticks = value * (double)scale;
        return TimeSpan { Ticks = (int64)(ticks < 0.0 ? ticks - 0.5 : ticks + 0.5) };
    }

    static TimeSpan Create(int hours, int minutes, int seconds)
    {
        return Create(0, hours, minutes, seconds, 0);
    }

    static TimeSpan Create(int days, int hours, int minutes, int seconds)
    {
        return Create(days, hours, minutes, seconds, 0);
    }

    static TimeSpan Create(int days, int hours, int minutes, int seconds, int milliseconds)
    {
        return TimeSpan { Ticks = (int64)days * _TicksPerDay + (int64)hours * _TicksPerHour + (int64)minutes * _TicksPerMinute +
                                  (int64)seconds * _TicksPerSecond + (int64)milliseconds * _TicksPerMillisecond };
    }

    // the parts (with the sign of the whole: -1.02:03:04 has Days -1, Hours -2, ...)
    int Days() { return (int)(Ticks / _TicksPerDay); }
    int Hours() { return (int)(Ticks / _TicksPerHour % 24); }
    int Minutes() { return (int)(Ticks / _TicksPerMinute % 60); }
    int Seconds() { return (int)(Ticks / _TicksPerSecond % 60); }
    int Milliseconds() { return (int)(Ticks / _TicksPerMillisecond % 1000); }

    // the whole duration in one unit
    double TotalDays() { return (double)Ticks / (double)_TicksPerDay; }
    double TotalHours() { return (double)Ticks / (double)_TicksPerHour; }
    double TotalMinutes() { return (double)Ticks / (double)_TicksPerMinute; }
    double TotalSeconds() { return (double)Ticks / (double)_TicksPerSecond; }
    double TotalMilliseconds() { return (double)Ticks / (double)_TicksPerMillisecond; }

    TimeSpan Add(TimeSpan other) { return TimeSpan { Ticks = Ticks + other.Ticks }; }
    TimeSpan Subtract(TimeSpan other) { return TimeSpan { Ticks = Ticks - other.Ticks }; }
    TimeSpan Negate() { return TimeSpan { Ticks = -Ticks }; }
    TimeSpan Duration() { return TimeSpan { Ticks = Ticks < 0 ? -Ticks : Ticks }; }
    TimeSpan Multiply(double factor) { return _From((double)Ticks * factor, 1); }

    int CompareTo(TimeSpan other) { return Ticks < other.Ticks ? -1 : Ticks > other.Ticks ? 1 : 0; }
    bool Equals(TimeSpan other) { return Ticks == other.Ticks; }
    int GetHashCode() { return unchecked((int)Ticks ^ (int)(Ticks >> 32)); }

    // [-][d.]hh:mm:ss[.fffffff], like .NET's "c" format: 1.02:03:04.5000000
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

// A date and time of day, local or UTC.
struct DateTime : IComparable<DateTime>, IEquatable<DateTime>, IHashable
{
    int64 Ticks;    // 100 ns since 0001-01-01 00:00
    bool IsUtc;

    // ---- now ----

    static DateTime UtcNow()
    {
        return DateTime { Ticks = _Os.NowTicks() + _UnixEpochTicks, IsUtc = true };
    }

    static DateTime Now()
    {
        return UtcNow().ToLocalTime();
    }

    // today's date (local) at 00:00
    static DateTime Today()
    {
        return Now().Date();
    }

    // ---- creating ----

    static DateTime Create(int year, int month, int day)
    {
        return Create(year, month, day, 0, 0, 0, 0);
    }

    static DateTime Create(int year, int month, int day, int hour, int minute, int second)
    {
        return Create(year, month, day, hour, minute, second, 0);
    }

    // a local date and time; a value out of range ends the program with a panic
    static DateTime Create(int year, int month, int day, int hour, int minute, int second, int millisecond)
    {
        if (!_Valid(year, month, day, hour, minute, second, millisecond))
            Environment.Panic("invalid date or time: " + year.ToString() + "-" + month.ToString() + "-" + day.ToString() + " " +
                              hour.ToString() + ":" + minute.ToString() + ":" + second.ToString() + "." + millisecond.ToString());
        return DateTime { Ticks = _TicksOf(year, month, day) + (int64)hour * _TicksPerHour + (int64)minute * _TicksPerMinute +
                                  (int64)second * _TicksPerSecond + (int64)millisecond * _TicksPerMillisecond };
    }

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

    // seconds or milliseconds since 1970-01-01 00:00 UTC (Unix time) as a UTC DateTime
    static DateTime FromUnixSeconds(int64 seconds)
    {
        return DateTime { Ticks = seconds * _TicksPerSecond + _UnixEpochTicks, IsUtc = true };
    }

    static DateTime FromUnixMilliseconds(int64 milliseconds)
    {
        return DateTime { Ticks = milliseconds * _TicksPerMillisecond + _UnixEpochTicks, IsUtc = true };
    }

    int64 ToUnixSeconds()
    {
        return _FloorDiv(ToUniversalTime().Ticks - _UnixEpochTicks, _TicksPerSecond);
    }

    int64 ToUnixMilliseconds()
    {
        return _FloorDiv(ToUniversalTime().Ticks - _UnixEpochTicks, _TicksPerMillisecond);
    }

    static int64 _FloorDiv(int64 a, int64 b)
    {
        int64 q = a / b;
        return a % b < 0 ? q - 1 : q;
    }

    static bool IsLeapYear(int year)
    {
        return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    }

    static int DaysInMonth(int year, int month)
    {
        if (month == 2)
            return IsLeapYear(year) ? 29 : 28;
        return month == 4 || month == 6 || month == 9 || month == 11 ? 30 : 31;
    }

    // ---- parts ----

    int Year() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return y; }
    int Month() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return m; }
    int Day() { int y = 0; int m = 0; int d = 0; _Parts(ref y, ref m, ref d); return d; }
    int Hour() { return (int)(Ticks / _TicksPerHour % 24); }
    int Minute() { return (int)(Ticks / _TicksPerMinute % 60); }
    int Second() { return (int)(Ticks / _TicksPerSecond % 60); }
    int Millisecond() { return (int)(Ticks / _TicksPerMillisecond % 1000); }

    void _Parts(ref int year, ref int month, ref int day)
    {
        _Calendar.CivilFromDays(Ticks / _TicksPerDay - 719162, ref year, ref month, ref day);
    }

    DayOfWeek DayOfWeek()
    {
        return (DayOfWeek)(int)((Ticks / _TicksPerDay + 1) % 7); // 0001-01-01 was a Monday
    }

    // 1 to 366
    int DayOfYear()
    {
        int y = Year();
        return (int)((Ticks - _TicksOf(y, 1, 1)) / _TicksPerDay) + 1;
    }

    // the date at 00:00
    DateTime Date()
    {
        return DateTime { Ticks = Ticks - Ticks % _TicksPerDay, IsUtc = IsUtc };
    }

    // the time since 00:00
    TimeSpan TimeOfDay()
    {
        return TimeSpan { Ticks = Ticks % _TicksPerDay };
    }

    // ---- arithmetic ----

    DateTime Add(TimeSpan span) { return _Plus(span.Ticks); }
    DateTime AddTicks(int64 ticks) { return _Plus(ticks); }
    DateTime AddDays(double days) { return _Plus(TimeSpan.FromDays(days).Ticks); }
    DateTime AddHours(double hours) { return _Plus(TimeSpan.FromHours(hours).Ticks); }
    DateTime AddMinutes(double minutes) { return _Plus(TimeSpan.FromMinutes(minutes).Ticks); }
    DateTime AddSeconds(double seconds) { return _Plus(TimeSpan.FromSeconds(seconds).Ticks); }
    DateTime AddMilliseconds(double milliseconds) { return _Plus(TimeSpan.FromMilliseconds(milliseconds).Ticks); }

    // whole months: the day stays, or becomes the last day of a shorter month (Jan 31 + 1 month = Feb 28/29)
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

    // the time between two dates (both are taken in UTC if one of them is)
    TimeSpan Subtract(DateTime other)
    {
        if (IsUtc != other.IsUtc)
            return TimeSpan { Ticks = ToUniversalTime().Ticks - other.ToUniversalTime().Ticks };
        return TimeSpan { Ticks = Ticks - other.Ticks };
    }

    DateTime Subtract(TimeSpan span)
    {
        return _Plus(-span.Ticks);
    }

    // ---- time zones ----

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

    DateTime ToLocalTime()
    {
        if (!IsUtc)
            return this;
        int offset = _Os.LocalOffsetSeconds(_FloorDiv(Ticks - _UnixEpochTicks, _TicksPerSecond));
        return DateTime { Ticks = Ticks + (int64)offset * _TicksPerSecond, IsUtc = false };
    }

    // ---- comparing ----

    // compares the instants (a local and a UTC value are compared in UTC)
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

    bool Equals(DateTime other) { return CompareTo(other) == 0; }
    int GetHashCode() { return unchecked((int)Ticks ^ (int)(Ticks >> 32)); }

    // ---- text ----

    // 2026-10-01 14:05:09
    string ToString()
    {
        return ToString("yyyy-MM-dd HH:mm:ss");
    }

    // ISO 8601 with the zone: 2026-10-01T12:05:09.250Z (UTC) or 2026-10-01T14:05:09.250+02:00 (local)
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

    // yyyy yy MMMM MMM MM M dddd ddd dd d HH H hh h mm m ss s fff ff f tt; other letters and '...' are copied,
    // \x copies x
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

    // yyyy-MM-dd, optionally followed by T or a space and HH:mm[:ss[.fffffff]], then Z (UTC) or +hh:mm / -hh:mm (UTC,
    // converted from that offset); without a zone the time is local
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

// Measures elapsed time with the monotonic clock of the system (not affected by changes of the time of day).
struct Stopwatch
{
    int64 _start;     // MonotonicTicks when it was started (while running)
    int64 _elapsed;   // the time of the earlier runs
    bool _running;

    static Stopwatch StartNew()
    {
        var sw = Stopwatch { };
        sw.Start();
        return sw;
    }

    void Start()
    {
        if (!_running)
        {
            _start = _Os.MonotonicTicks();
            _running = true;
        }
    }

    void Stop()
    {
        if (_running)
        {
            _elapsed += _Os.MonotonicTicks() - _start;
            _running = false;
        }
    }

    void Reset()
    {
        _elapsed = 0;
        _running = false;
    }

    void Restart()
    {
        _elapsed = 0;
        _start = _Os.MonotonicTicks();
        _running = true;
    }

    bool IsRunning() { return _running; }

    int64 ElapsedTicks()
    {
        return _running ? _elapsed + _Os.MonotonicTicks() - _start : _elapsed;
    }

    int64 ElapsedMilliseconds() { return ElapsedTicks() / _TicksPerMillisecond; }

    TimeSpan Elapsed() { return TimeSpan { Ticks = ElapsedTicks() }; }
}
