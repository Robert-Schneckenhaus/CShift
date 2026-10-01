// DateTime, TimeSpan, DayOfWeek, Stopwatch and Thread.Sleep (independent of the time zone of the machine)
// expect-stdout: 2024-02-29 13:05:09
// expect-stdout: Thursday, 29. February 2024 01:05:09.250 PM
// expect-stdout: 2024 2 29 13 5 9 250 Thursday 60
// expect-stdout: 2025-02-28 2024-01-31 2023-02-28
// expect-stdout: 2024-03-02 01:05:09
// expect-stdout: 2023-11-14T22:13:20.000Z 1700000000 1700000000123
// expect-stdout: 29.00:00:00 -1.01:01:01.5000000 01:30:00 0.5
// expect-stdout: 1 2 3 4 5 | 26.1
// expect-stdout: 2026-10-01T10:30:15.500Z
// expect-stdout: 1999-12-31T23:59:59.000Z
// expect-stdout: 2026-01-02 00:00:00 local
// expect-stdout: invalid: '2026-13-01' is not a valid date or time
// expect-stdout: invalid: 'yesterday' is not a date (yyyy-MM-dd)
// expect-stdout: leap 2024 true 2100 false 2000 true, February 2023 has 28 days
// expect-stdout: sorted 1999 2024 2026
// expect-stdout: utc round trip true
// expect-stdout: now true, stopwatch true
using System;

int Main()
{
    var d = DateTime.Create(2024, 2, 29, 13, 5, 9, 250);
    Console.WriteLine(d.ToString());
    Console.WriteLine(d.ToString("dddd, d. MMMM yyyy hh:mm:ss.fff tt"));
    Console.WriteLine($"{d.Year()} {d.Month()} {d.Day()} {d.Hour()} {d.Minute()} {d.Second()} {d.Millisecond()} {d.DayOfWeek()} {d.DayOfYear()}");
    Console.WriteLine(d.AddYears(1).ToString("yyyy-MM-dd") + " " + DateTime.Create(2023, 12, 31).AddMonths(1).ToString("yyyy-MM-dd") + " " +
                      d.AddMonths(-12).ToString("yyyy-MM-dd"));
    Console.WriteLine(d.AddDays(1.5).ToString());

    var u = DateTime.FromUnixSeconds(1700000000);
    Console.WriteLine(u.ToIsoString() + " " + u.ToUnixSeconds().ToString() + " " +
                      DateTime.FromUnixMilliseconds(1700000000123).ToUnixMilliseconds().ToString());

    var month = DateTime.Create(2024, 3, 1).Subtract(DateTime.Create(2024, 2, 1));
    Console.WriteLine(month.ToString() + " " + TimeSpan.FromSeconds(-90061.5).ToString() + " " + TimeSpan.Create(1, 30, 0).ToString() + " " +
                      TimeSpan.FromHours(12).TotalDays().ToString());
    var span = TimeSpan.Create(1, 2, 3, 4, 5);
    Console.WriteLine($"{span.Days()} {span.Hours()} {span.Minutes()} {span.Seconds()} {span.Milliseconds()} | {span.TotalHours():F1}");

    if (DateTime.Parse("2026-10-01T12:30:15.5+02:00") is DateTime p)
        Console.WriteLine(p.ToIsoString());
    if (DateTime.Parse(" 1999-12-31 23:59:59Z ") is DateTime z)
        Console.WriteLine(z.ToIsoString());
    if (DateTime.Parse("2026-01-02") is DateTime local)
        Console.WriteLine(local.ToString() + (local.IsUtc ? " utc" : " local"));
    if (DateTime.Parse("2026-13-01") is error e1)
        Console.WriteLine("invalid: " + e1.Message);
    if (DateTime.Parse("yesterday") is error e2)
        Console.WriteLine("invalid: " + e2.Message);

    Console.WriteLine($"leap 2024 {DateTime.IsLeapYear(2024)} 2100 {DateTime.IsLeapYear(2100)} 2000 {DateTime.IsLeapYear(2000)}, February 2023 has {DateTime.DaysInMonth(2023, 2)} days");

    var dates = List<DateTime>.Create();
    dates.Add(DateTime.Create(2026, 1, 1));
    dates.Add(DateTime.Create(1999, 1, 1));
    dates.Add(DateTime.Create(2024, 1, 1));
    dates.Sort();
    Console.WriteLine($"sorted {dates[0].Year()} {dates[1].Year()} {dates[2].Year()}");

    var x = DateTime.Create(2026, 6, 15, 12, 0, 0);
    Console.WriteLine("utc round trip " + x.ToUniversalTime().ToLocalTime().Equals(x).ToString());

    bool nowOk = DateTime.Now().Year() >= 2026 && DateTime.UtcNow().Subtract(DateTime.Now().ToUniversalTime()).Duration().TotalSeconds() < 5.0;
    var sw = Stopwatch.StartNew();
    Thread.Sleep(20);
    sw.Stop();
    int64 ms = sw.ElapsedMilliseconds();
    Console.WriteLine($"now {nowOk}, stopwatch {ms >= 15 && ms < 5000}");
    return 0;
}
