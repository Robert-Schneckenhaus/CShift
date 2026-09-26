// Pseudo-random numbers (xorshift64*, seeded with SplitMix64). The same seed always gives the same sequence, on every
// system - useful for tests, procedural content and replays. Not suitable for cryptography.
//
//     var random = Random.Create(42);
//     int die = random.Next(1, 7);          // 1..6
//     double x = random.NextDouble();       // [0, 1)
//
// A Random is a value: a copy continues independently from the same state.

namespace System;

extern "C" int64 time(void* timer);

struct Random
{
    uint64 _state;

    static Random Create(int64 seed)
    {
        // SplitMix64 turns any seed (also 0) into a well mixed, non-zero state.
        uint64 z = unchecked((uint64)seed + 11400714819323198485);
        z = unchecked((z ^ (z >> 30)) * 13787848793156543929);
        z = unchecked((z ^ (z >> 27)) * 10723151780598845931);
        z = z ^ (z >> 31);
        if (z == 0)
            z = 1;
        return Random { _state = z };
    }

    // Seeded from the clock: a different sequence on every run.
    static Random Create()
    {
        unsafe
        {
            return Create(time(null));
        }
    }

    // The next 64 random bits.
    uint64 NextBits()
    {
        uint64 x = _state;
        x = x ^ (x >> 12);
        x = x ^ (x << 25);
        x = x ^ (x >> 27);
        _state = x;
        return unchecked(x * 2685821657736338717);
    }

    // A number from 0 to int.MaxValue - 1.
    int Next()
    {
        return (int)(NextBits() >> 33) % 2147483647;
    }

    // A number from 0 to max - 1 (0 if max <= 0).
    int Next(int max)
    {
        if (max <= 0)
            return 0;
        return (int)((NextBits() >> 1) % (uint64)max);
    }

    // A number from min to max - 1 (min if max <= min).
    int Next(int min, int max)
    {
        if (max <= min)
            return min;
        return min + (int)((NextBits() >> 1) % (uint64)((int64)max - (int64)min));
    }

    // A number in [0, 1).
    double NextDouble()
    {
        return (double)(NextBits() >> 11) / 9007199254740992.0;
    }

    bool NextBool()
    {
        return (NextBits() >> 63) != 0;
    }
}
