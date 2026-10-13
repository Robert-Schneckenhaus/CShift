namespace Ambermoon.Data.Legacy.Compression;

using System;

/// A match that [MatchChains.GetLongestMatch] found: where the earlier sequence starts and how many bytes match.
struct Match
{
    /// The offset of the earlier sequence (-1 if there is none).
    int Offset;
    /// The number of matching bytes.
    int Length;
}

/// The match finder of the LOB compressors: hash chains. Finds the longest earlier sequence that matches the bytes at
/// an offset, the nearest one of those of that length.
///
/// The sequences are chained by a hash of their first bytes (as many as the shortest match the compressor uses: 2 or
/// 3), the newest first. A search follows the chain of its position until a sequence is too far back (the window of
/// the compression), so it finds the longest match like the trie of the original (Ambermoon.Data.Legacy) did, but
/// on a 68000 in a quarter of the time, and sometimes a nearer one of the same length, which the compressions with
/// shorter codes for near matches need fewer bytes for. A sequence matches at most the length it was added with, like
/// in the trie. Sequences closer than `minDistance` (which the compressor cannot use) are skipped instead of hiding
/// the ones behind them.
struct MatchChains
{
    int[] _head;      // per hash: the newest offset (-1: none)
    int[] _previous;  // per offset: the next older offset with the same hash
    uint8[] _length;  // per offset: the length it was added with + 1 (0: not added)
    int _first;       // the oldest offset that is still in the window
    int _maxMatchOffset;
    int _minDistance;
    int _minLength;   // 2 or 3: the bytes of the hash, the shortest match that is found
    int _bestLength;  // the search: the longest match so far and where it is
    int _bestOffset;
    string _error;

    /// Matches at most `maxMatchOffset` and at least `minDistance` bytes back, of at least `minLength` (2 or 3) bytes.
    static MatchChains Create(int maxMatchOffset, int minDistance, int minLength)
    {
        var m = MatchChains { _maxMatchOffset = maxMatchOffset, _minDistance = minDistance, _minLength = minLength,
            _error = "" };
        m._head = new int[_ChainsHashSize];
        for (var i = 0; i < _ChainsHashSize; i += 1)
            m._head[i] = -1;
        m._previous = new int[0];
        m._length = new uint8[0];
        return m;
    }

    /// "" or why the match finder cannot be used: an offset was added twice (the original throws then).
    string Error()
    {
        return _error;
    }

    /// Adds the sequence of `length` bytes at `offset` (at most the longest match length of the compression, 255 at
    /// most; less at the end of the data).
    void Add(uint8[] sequence, int offset, int length)
    {
        if (_length.Length != sequence.Length)
        {
            _previous = new int[sequence.Length];
            _length = new uint8[sequence.Length];
        }
        if (_length[offset] != 0)
        {
            if (_error.Length == 0)
                _error = "An item with the same key has already been added. Key: " + offset.ToString();
            return;
        }
        // the compressors add the first sequence with the longest match length, also when the data is shorter
        if (length > sequence.Length - offset)
            length = sequence.Length - offset;
        _length[offset] = (uint8)(length + 1);
        if (length >= _minLength)
        {
            int hash = _Hash(sequence, offset);
            _previous[offset] = _head[hash];
            _head[hash] = offset;
        }
        // matches are searched before adding, hence the + 1
        int first = offset - _maxMatchOffset + 1;
        if (first > _first)
            _first = first;
    }

    /// The longest earlier sequence that matches the bytes at `searchOffset`, at most `maxLength` bytes (the nearest of
    /// that length). Matches shorter than the minimum length are not found.
    Match GetLongestMatch(uint8[] sequence, int searchOffset, int maxLength)
    {
        _bestLength = 0;
        _bestOffset = -1;
        if (maxLength < _minLength)
            return Match { Offset = -1, Length = 0 };
        if (_minLength > 2)
        {
            // A run of r equal bytes b at the search offset (shorter than the longest match): a longer match has the
            // same run followed by the same byte c, so it is found in the much shorter chain of "b b c" at the end of
            // the run (data with many short runs of zeros would make the chain of "b b b" very long).
            uint8 b = sequence[searchOffset];
            int run = 1;
            while (run < maxLength && sequence[searchOffset + run] == b)
                run += 1;
            if (run >= 3 && run < maxLength)
            {
                _Walk(sequence, searchOffset, maxLength, run - 2, maxLength);
                if (_bestLength > run)
                    return Match { Offset = _bestOffset, Length = _bestLength };
                // no longer one: the nearest with the run
                _Walk(sequence, searchOffset, maxLength, 0, run);
                return _Result();
            }
        }
        _Walk(sequence, searchOffset, maxLength, 0, maxLength);
        return _Result();
    }

    Match _Result()
    {
        if (_bestLength < _minLength)
            return Match { Offset = -1, Length = 0 };
        return Match { Offset = _bestOffset, Length = _bestLength };
    }

    // Follows the chain of the bytes at searchOffset + shift: the candidates are its offsets - shift. Stops when a
    // match has 'enough' bytes.
    void _Walk(uint8[] sequence, int searchOffset, int maxLength, int shift, int enough)
    {
        int last = searchOffset - _minDistance;
        int first = _first + shift;
        int bestLength = _bestLength;
        int bestOffset = _bestOffset;
        int entry = _head[_Hash(sequence, searchOffset + shift)];
        while (entry >= first)
        {
            int offset = entry - shift;
            if (offset <= last)
            {
                int limit = _length[offset] - 1;
                if (limit > maxLength)
                    limit = maxLength;
                // only a longer match counts: look at the byte that would make it longer first
                if (limit > bestLength && sequence[offset + bestLength] == sequence[searchOffset + bestLength])
                {
                    int n = 0;
                    while (n < limit && sequence[offset + n] == sequence[searchOffset + n])
                        n += 1;
                    if (n > bestLength)
                    {
                        bestLength = n;
                        bestOffset = offset;
                        if (n >= enough)
                            break;
                    }
                }
            }
            entry = _previous[entry];
        }
        _bestLength = bestLength;
        _bestOffset = bestOffset;
    }

    int _Hash(uint8[] sequence, int offset)
    {
        int hash = (sequence[offset] << 6) ^ sequence[offset + 1];
        if (_minLength > 2)
            hash = (hash << 5) ^ (hash >> 9) ^ sequence[offset + 2];
        return hash & (_ChainsHashSize - 1);
    }
}

// the number of chains (a power of two)
const int _ChainsHashSize = 1 << 14;
