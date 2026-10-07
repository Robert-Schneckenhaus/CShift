// Standard library: System.Compression - CRC-32 and Adler-32, deflate/zlib/gzip round trips at all levels, data of
// zlib decompressed, the errors of damaged data. Main returns the number of failed checks.
// expect-stdout: crc CBF43926 adler 091E01DE
// expect-stdout: decoded zlib: hello hello hello hello
// expect-stdout: truncated: Truncated
// expect-stdout: checksum: ChecksumMismatch
// expect-stdout: header: InvalidData
// expect-exit: 0

using System;
using System.Compression;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

bool Same(uint8[] a, ReadOnlySlice<uint8> b)
{
    if (a.Length != b.Length)
        return false;
    for (var i = 0; i < a.Length; i += 1)
    {
        if (a[i] != b[i])
            return false;
    }
    return true;
}

int Main()
{
    int f = 0;
    var digits = "123456789".AsBytes();
    Console.WriteLine("crc " + Crc32.Compute(digits).ToString("X8") + " adler " + Adler32.Compute(digits).ToString("X8"));
    f += Check("crc in parts", Crc32.Update(Crc32.Update(0, digits[0..4]), digits[4..]) == Crc32.Compute(digits));
    f += Check("adler in parts", Adler32.Update(Adler32.Update(1, digits[0..4]), digits[4..]) == Adler32.Compute(digits));

    // made by zlib (level 9, and level 0: a stored block)
    uint8[] packed = [0x78, 0xDA, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x27, 0x01, 0x68, 0x03, 0x08, 0xB1];
    if (Zlib.Decompress(packed) is uint8[] hello)
        Console.WriteLine("decoded zlib: " + string.FromBytes(hello));
    uint8[] stored = [0x78, 0x01, 0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63, 0x02, 0x4D, 0x01, 0x27];
    f += Check("stored", Zlib.Decompress(stored) is uint8[] abc && string.FromBytes(abc) == "abc");

    // data of several kinds: empty, text, runs, pseudo-random bytes, more than one block
    var random = Random.Create(7);
    var noise = new uint8[70000];
    for (var i = 0; i < noise.Length; i += 1)
        noise[i] = (uint8)random.Next(256);
    var runs = new uint8[100000];
    for (var i = 0; i < runs.Length; i += 1)
        runs[i] = (uint8)((i / 1000) % 3 + (i % 7 == 0 ? 1 : 0));
    var text = StringBuilder.Create();
    for (var i = 0; i < 3000; i += 1)
        text.Append("line " + (i % 17).ToString() + " of the text\n");
    var samples = List<uint8[]>.Create();
    samples.Add(new uint8[0]);
    samples.Add(text.ToString().AsBytes().ToArray());
    samples.Add(runs);
    samples.Add(noise);
    for (var s = 0; s < samples.Count(); s += 1)
    {
        var data = samples[s];
        for (var level = 0; level <= 9; level += 1)
        {
            string name = "sample " + s.ToString() + " level " + level.ToString();
            var raw = Deflate.Compress(data, level);
            f += Check(name + " deflate", Deflate.Decompress(raw) is uint8[] a && Same(a, data));
            var z = Zlib.Compress(data, level);
            f += Check(name + " zlib", Zlib.Decompress(z) is uint8[] b && Same(b, data));
            var g = Gzip.Compress(data, level);
            f += Check(name + " gzip", Gzip.Decompress(g) is uint8[] c && Same(c, data));
            if (level >= 1 && s == 2)
                f += Check(name + " runs are small", z.Length < data.Length / 20);
        }
    }
    f += Check("noise is stored", Deflate.Compress(noise).Length <= noise.Length + 64);

    // damaged data
    var good = Zlib.Compress(runs);
    var truncated = Zlib.Decompress(good[0..good.Length / 2]);
    if (truncated is error e1)
        Console.WriteLine("truncated: " + e1.Code.ToString());
    var wrong = good.Clone();
    wrong[wrong.Length - 1] ^= 1;
    if (Zlib.Decompress(wrong) is error e2)
        Console.WriteLine("checksum: " + e2.Code.ToString());
    if (Zlib.Decompress("not zlib".AsBytes()) is error e3)
        Console.WriteLine("header: " + e3.Code.ToString());
    // random changes never crash
    for (var i = 0; i < 200; i += 1)
    {
        var bad = good.Clone();
        for (var k = 0; k < 3; k += 1)
            bad[2 + random.Next(bad.Length - 2)] = (uint8)random.Next(256);
        Zlib.Decompress(bad);
    }
    return f;
}
