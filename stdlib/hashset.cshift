namespace System;

/// A set of values (T must be a valid Dictionary key: numbers, bool, char, enums, string, or a
/// struct with GetHashCode/Equals).
///
/// ```
/// var seen = HashSet<string>.Create();
/// if (seen.Add("a")) ...       // true if the value was new
/// ```
struct HashSet<T>
{
    Dictionary<T, bool> _map;

    /// A new, empty set.
    static HashSet<T> Create()
    {
        return HashSet<T> { _map = Dictionary<T, bool>.Create() };
    }

    /// Whether the set has storage: made by Create() or `[]`, not the zero value (which cannot change).
    bool IsCreated()
    {
        return _map.IsCreated();
    }

    /// The number of values in the set.
    int Count()
    {
        return _map.Count();
    }

    /// Whether `value` is in the set.
    bool Contains(T value)
    {
        return _map.ContainsKey(value);
    }

    /// Adds `value` to the set.
    /// @returns `true` if the value was added, `false` if it was already in the set.
    /// @panics when the set was not created ([HashSet<T>.IsCreated]).
    bool Add(T value)
    {
        if (!_map.IsCreated())
            Environment.Panic("the set was not created (HashSet<T>.Create() or []): the zero value (new(), a field without a value) is empty and cannot change");
        if (_map.ContainsKey(value))
            return false;
        _map.Set(value, true);
        return true;
    }

    /// Removes `value` from the set.
    /// @returns whether the value was in the set.
    bool Remove(T value)
    {
        return _map.Remove(value);
    }

    /// Removes all values.
    void Clear()
    {
        _map.Clear();
    }

    /// A new array with the values of the set (in no particular order).
    T[] ToArray()
    {
        return _map.Keys();
    }
}
