// Dictionary<TKey, TValue>: a hash table (separate chaining). Keys keep their insertion order in Keys(),
// Values() and Entries() as long as no entry was removed.
//
//     using System;
//
//     var ages = Dictionary<string, int>.Create();
//     ages.Set("Ann", 31);
//     if (ages.TryGet("Ann") is int age)
//         Console.WriteLine(age);
//     foreach (var key in ages.Keys())
//         Console.WriteLine(key);
//
// TKey must be IEquatable and IHashable: numbers, bool, char, enums and string are, and your own structs
// are as soon as they define 'bool Equals(T other)' and 'int GetHashCode()'.
//
// Like List<T>, a Dictionary is a handle to shared storage (see list.csh): use Dictionary<K, V>.Create()
// when the dictionary is handed out before its first entry is added.

namespace System;

struct KeyValuePair<TKey, TValue>
{
    TKey Key;
    TValue Value;
}

// Internal: one slot of the entry table. Chain and free-list links are stored as index + 1 (0 = none).
struct DictionaryEntry<TKey, TValue>
{
    int Hash; // -1 = unused slot
    int Next;
    TKey Key;
    TValue Value;
}

struct DictionaryState<TKey, TValue>
{
    int[] Buckets; // first entry of each chain (index + 1)
    DictionaryEntry<TKey, TValue>[] Entries;
    int Count;     // used slots, including removed ones that are in the free list
    int FreeList;  // first removed slot (index + 1)
    int FreeCount;
}

struct Dictionary<TKey, TValue>
    where TKey : IEquatable<TKey>, IHashable
{
    DictionaryState<TKey, TValue>[] _state;

    static Dictionary<TKey, TValue> Create()
    {
        return Dictionary<TKey, TValue> { _state = new DictionaryState<TKey, TValue>[1] };
    }

    int Count()
    {
        if (_state == null)
            return 0;
        return _state[0].Count - _state[0].FreeCount;
    }

    bool ContainsKey(TKey key)
    {
        return _Find(key) >= 0;
    }

    // The value of key, or no value if the key is not present.
    Optional<TValue> TryGet(TKey key)
    {
        int index = _Find(key);
        if (index < 0)
            return null;
        return _state[0].Entries[index].Value;
    }

    // The value of key; panics if the key is not present (dict[key] calls it). TryGet asks without panicking.
    TValue Get(TKey key)
    {
        int index = _Find(key);
        if (index < 0)
            Environment.Panic("the key is not present in the Dictionary");
        return _state[0].Entries[index].Value;
    }

    TValue GetOrDefault(TKey key, TValue fallback)
    {
        int index = _Find(key);
        if (index < 0)
            return fallback;
        return _state[0].Entries[index].Value;
    }

    // Adds the entry or replaces the value of an existing key.
    void Set(TKey key, TValue value)
    {
        int index = _Find(key);
        if (index >= 0)
        {
            _state[0].Entries[index].Value = value;
            return;
        }
        _Insert(key, value);
    }

    // Adds an entry; fails if the key already exists.
    Error<void> Add(TKey key, TValue value)
    {
        if (_Find(key) >= 0)
            return error("an entry with the same key already exists");
        _Insert(key, value);
        return;
    }

    bool Remove(TKey key)
    {
        if (_state == null || _state[0].Buckets == null)
            return false;

        int hash = key.GetHashCode() & 0x7FFFFFFF;
        int bucket = hash % _state[0].Buckets.Length;
        int previous = -1;
        int i = _state[0].Buckets[bucket] - 1;
        while (i >= 0)
        {
            if (_state[0].Entries[i].Hash == hash && _state[0].Entries[i].Key.Equals(key))
            {
                int next = _state[0].Entries[i].Next;
                if (previous < 0)
                    _state[0].Buckets[bucket] = next;
                else
                    _state[0].Entries[previous].Next = next;

                // Clear the slot (releases key and value) and put it into the free list.
                _state[0].Entries[i] = new DictionaryEntry<TKey, TValue>();
                _state[0].Entries[i].Hash = -1;
                _state[0].Entries[i].Next = _state[0].FreeList;
                _state[0].FreeList = i + 1;
                _state[0].FreeCount += 1;
                return true;
            }
            previous = i;
            i = _state[0].Entries[i].Next - 1;
        }
        return false;
    }

    void Clear()
    {
        if (_state == null)
            return;
        _state[0] = new DictionaryState<TKey, TValue>();
    }

    TKey[] Keys()
    {
        var result = new TKey[Count()];
        if (_state == null)
            return result;
        int n = 0;
        for (var i = 0; i < _state[0].Count; i += 1)
        {
            if (_state[0].Entries[i].Hash >= 0)
            {
                result[n] = _state[0].Entries[i].Key;
                n += 1;
            }
        }
        return result;
    }

    TValue[] Values()
    {
        var result = new TValue[Count()];
        if (_state == null)
            return result;
        int n = 0;
        for (var i = 0; i < _state[0].Count; i += 1)
        {
            if (_state[0].Entries[i].Hash >= 0)
            {
                result[n] = _state[0].Entries[i].Value;
                n += 1;
            }
        }
        return result;
    }

    KeyValuePair<TKey, TValue>[] Entries()
    {
        var result = new KeyValuePair<TKey, TValue>[Count()];
        if (_state == null)
            return result;
        int n = 0;
        for (var i = 0; i < _state[0].Count; i += 1)
        {
            if (_state[0].Entries[i].Hash >= 0)
            {
                result[n] = KeyValuePair<TKey, TValue> { Key = _state[0].Entries[i].Key, Value = _state[0].Entries[i].Value };
                n += 1;
            }
        }
        return result;
    }

    // Index of the entry with the given key, or -1.
    int _Find(TKey key)
    {
        if (_state == null || _state[0].Buckets == null)
            return -1;
        int hash = key.GetHashCode() & 0x7FFFFFFF;
        int i = _state[0].Buckets[hash % _state[0].Buckets.Length] - 1;
        while (i >= 0)
        {
            if (_state[0].Entries[i].Hash == hash && _state[0].Entries[i].Key.Equals(key))
                return i;
            i = _state[0].Entries[i].Next - 1;
        }
        return -1;
    }

    // Adds an entry for a key that is known to be absent.
    void _Insert(TKey key, TValue value)
    {
        if (_state == null)
            _state = new DictionaryState<TKey, TValue>[1];
        if (_state[0].Buckets == null)
            _Resize(8);

        int index;
        if (_state[0].FreeCount > 0)
        {
            index = _state[0].FreeList - 1;
            _state[0].FreeList = _state[0].Entries[index].Next;
            _state[0].FreeCount -= 1;
        }
        else
        {
            if (_state[0].Count == _state[0].Entries.Length)
                _Resize(_state[0].Entries.Length * 2);
            index = _state[0].Count;
            _state[0].Count += 1;
        }

        int hash = key.GetHashCode() & 0x7FFFFFFF;
        int bucket = hash % _state[0].Buckets.Length;
        _state[0].Entries[index] = DictionaryEntry<TKey, TValue>
        {
            Hash = hash,
            Next = _state[0].Buckets[bucket],
            Key = key,
            Value = value
        };
        _state[0].Buckets[bucket] = index + 1;
    }

    // Reallocates the tables with newSize slots and rebuilds the chains.
    void _Resize(int newSize)
    {
        var entries = new DictionaryEntry<TKey, TValue>[newSize];
        var buckets = new int[newSize];
        int count = _state[0].Count;
        if (_state[0].Entries != null)
            Array.Copy(_state[0].Entries, 0, entries, 0, count);
        for (var i = 0; i < count; i += 1)
        {
            if (entries[i].Hash >= 0)
            {
                int bucket = entries[i].Hash % newSize;
                entries[i].Next = buckets[bucket];
                buckets[bucket] = i + 1;
            }
        }
        _state[0].Buckets = buckets;
        _state[0].Entries = entries;
    }
}
