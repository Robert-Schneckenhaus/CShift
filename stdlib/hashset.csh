// HashSet<T>: a set of values (T must be a valid Dictionary key: numbers, bool, char, enums, string, or a
// struct with GetHashCode/Equals).
//
//     var seen = HashSet<string>.Create();
//     if (seen.Add("a")) ...       // true if the value was new

namespace System;

struct HashSet<T>
{
    Dictionary<T, bool> _map;

    static HashSet<T> Create()
    {
        return HashSet<T> { _map = Dictionary<T, bool>.Create() };
    }

    int Count()
    {
        return _map.Count();
    }

    bool Contains(T value)
    {
        return _map.ContainsKey(value);
    }

    // Returns true if the value was added, false if it was already in the set.
    bool Add(T value)
    {
        if (_map.ContainsKey(value))
            return false;
        _map.Set(value, true);
        return true;
    }

    bool Remove(T value)
    {
        return _map.Remove(value);
    }

    void Clear()
    {
        _map.Clear();
    }

    T[] ToArray()
    {
        return _map.Keys();
    }
}
