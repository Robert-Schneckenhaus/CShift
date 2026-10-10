// What the 68000 backend's Prepare knows (Facts.csh) must never change a result: loads of variables that a store on
// some way changes, bounds checks of elements that are written, checked sums that stay checked.
// expect-stdout: known facts ok
using System;

int Crypt(uint8[] data, uint16 key)
{
    // the JH encryption: data[index] read and written, index + 1 checked once
    int length = data.Length;
    int numWords = (length + 1) >> 1;
    int d0 = key;
    int index = 0;
    for (var i = 0; i < numWords; i += 1)
    {
        if (index == length - 1)
            data[index] = (uint8)(data[index] ^ (d0 >> 8));
        else
        {
            data[index] = (uint8)(data[index] ^ (d0 >> 8));
            data[index + 1] = (uint8)(data[index + 1] ^ d0);
        }
        int d1 = d0;
        d0 = ((d0 << 4) + d1 + 87) & 0xffff;
        index += 2;
    }
    int sum = 0;
    foreach (var b in data)
        sum = (sum * 31 + b) & 0xffffff;
    return sum;
}

int Main()
{
    // a variable that a store in the loop changes on some iterations only
    int x = 1;
    int total = 0;
    for (var i = 0; i < 6; i += 1)
    {
        total += x;
        if (i == 2)
            x = 10;
        else if (i == 4)
            x += 5;
        total += x;
    }
    if (total != 1 + 1 + 1 + 1 + 1 + 10 + 10 + 10 + 10 + 15 + 15 + 15)
        return 1;

    // a value loaded before a loop that changes it
    int y = 3;
    int seen = y;
    while (y < 40)
        y = y * 2;
    if (seen != 3 || y != 48)
        return 2;

    // elements read and written at the same index, and at index + 1
    var a = new int[] { 1, 2, 3, 4, 5 };
    for (var i = 0; i + 1 < a.Length; i += 1)
    {
        a[i] ^= 7;
        a[i + 1] += a[i];
    }
    if (a[0] != 6 || a[1] != 15 || a[2] != 21 || a[3] != 30 || a[4] != 35)
        return 3;

    // the same comparison twice, with a store in between that changes its operand
    int k = 2;
    int hits = 0;
    if (k < 3)
        hits += 1;
    k = 5;
    if (k < 3)
        hits += 10;
    if (hits != 1)
        return 4;

    // length - 1 of an empty array is -1, not an overflow
    var empty = new uint8[0];
    if (empty.Length - 1 != -1)
        return 5;

    // the JH loop, for an even and an odd length
    var even = new uint8[] { 1, 2, 3, 4, 5, 6, 7, 8 };
    var odd = new uint8[] { 9, 8, 7, 6, 5, 4, 3 };
    int c1 = Crypt(even, 0x1234);
    int c2 = Crypt(odd, 0xbeef);
    if (Crypt(even, 0x1234) == c1 || even[0] != 1 || even[7] != 8 || Crypt(odd, 0xbeef) == c2 || odd[6] != 3)
        return 6; // (crypting twice gives the data back)
    Console.WriteLine("known facts ok");
    return 0;
}
