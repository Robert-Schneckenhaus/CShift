namespace System;

/// The storage behind a [List]; use [List] instead.
/// @internal
struct ListState<T>
{
    T[] Items;
    int Count;
}

/// A growable array.
///
/// ```
/// using System;
///
/// var names = List<string>.Create();
/// names.Add("Ann");
/// names.Add("Bob");
/// foreach (var name in names)
///     Console.WriteLine(name);
/// ```
///
/// A List is a small handle to shared storage: copies of a List (assignments, arguments) see the same
/// elements, like a reference. The storage is made by Create() or a collection expression (`[]`); the zero value
/// (`new()`, a field without a value) is an empty list that can be read but not changed: Add panics.
///
/// `list[i]` reads an element ([List<T>.Get]), `list[i] = x` writes one ([List<T>.Set]); `foreach` goes through the
/// elements in order.
struct List<T>
{
    ListState<T>[] _state;

    /// A new, empty list.
    static List<T> Create()
    {
        return List<T> { _state = new ListState<T>[1] };
    }

    /// A new, empty list with room for `capacity` elements before it has to grow.
    static List<T> Create(int capacity)
    {
        var list = Create();
        list._Grow(capacity);
        return list;
    }

    /// Whether the list has storage: made by Create() or `[]`, not the zero value (which cannot change).
    bool IsCreated()
    {
        return _state != null;
    }

    /// The number of elements.
    int Count()
    {
        if (_state == null)
            return 0;
        return _state[0].Count;
    }

    /// Number of elements that fit without reallocating.
    int Capacity()
    {
        if (_state == null || _state[0].Items == null)
            return 0;
        return _state[0].Items.Length;
    }

    /// The element at `index` (also `list[index]`).
    /// @panics when `index` is not in 0 to `Count() - 1`.
    T Get(int index)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range (index " + index.ToString() + ", count " + Count().ToString() + ")");
        return _state[0].Items[index];
    }

    /// Replaces the element at `index` (also `list[index] = value`).
    /// @panics when `index` is not in 0 to `Count() - 1`.
    void Set(int index, T value)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range (index " + index.ToString() + ", count " + Count().ToString() + ")");
        _state[0].Items[index] = value;
    }

    /// Adds `value` at the end.
    /// @panics when the list was not created ([List<T>.IsCreated]).
    void Add(T value)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        _Grow(Count() + 1);
        _state[0].Items[_state[0].Count] = value;
        _state[0].Count += 1;
    }

    /// Adds all elements of `values` at the end, in order.
    void AddRange(T[] values)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        for (var i = 0; i < values.Length; i += 1)
            Add(values[i]);
    }

    /// Inserts `value` before the element at `index`; `index == Count()` appends.
    /// @panics when `index` is not in 0 to `Count()`.
    void Insert(int index, T value)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        if (index < 0 || index > Count())
            Environment.Panic("List index out of range (index " + index.ToString() + ", count " + Count().ToString() + ")");
        _Grow(Count() + 1);
        int count = _state[0].Count;
        Array.Copy(_state[0].Items, index, _state[0].Items, index + 1, count - index);
        _state[0].Items[index] = value;
        _state[0].Count += 1;
    }

    /// Removes the element at `index`; the elements after it move down by one.
    /// @panics when `index` is not in 0 to `Count() - 1`.
    void RemoveAt(int index)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range (index " + index.ToString() + ", count " + Count().ToString() + ")");
        int count = _state[0].Count;
        Array.Copy(_state[0].Items, index + 1, _state[0].Items, index, count - index - 1);
        _state[0].Items[count - 1] = default(T);
        _state[0].Count -= 1;
    }

    /// Removes all elements.
    void Clear()
    {
        if (_state == null)
            return;
        _state[0].Items = null;
        _state[0].Count = 0;
    }

    /// The index of the first element that equals `value` ([IEquatable]).
    /// @returns -1 if no element equals it.
    int IndexOf(T value)
        where T : IEquatable<T>
    {
        int count = Count();
        for (var i = 0; i < count; i += 1)
        {
            if (_state[0].Items[i].Equals(value))
                return i;
        }
        return -1;
    }

    /// Whether an element equals `value` ([IEquatable]).
    bool Contains(T value)
        where T : IEquatable<T>
    {
        return IndexOf(value) >= 0;
    }

    /// Removes the first element that equals `value` ([IEquatable]).
    /// @returns whether an element was removed.
    bool Remove(T value)
        where T : IEquatable<T>
    {
        int index = IndexOf(value);
        if (index < 0)
            return false;
        RemoveAt(index);
        return true;
    }

    /// Reverses the order of the elements.
    void Reverse()
    {
        int count = Count();
        for (var i = 0; i < count / 2; i += 1)
        {
            var tmp = _state[0].Items[i];
            _state[0].Items[i] = _state[0].Items[count - 1 - i];
            _state[0].Items[count - 1 - i] = tmp;
        }
    }

    /// Sorts the elements in ascending order ([IComparable]). The sort is stable: equal elements keep their order.
    void Sort()
        where T : IComparable<T>
    {
        int count = Count();
        if (count < 2)
            return;

        var items = _state[0].Items;
        var temp = new T[count];
        for (var width = 1; width < count; width *= 2)
        {
            for (var left = 0; left < count; left += 2 * width)
            {
                int mid = left + width;
                if (mid > count)
                    mid = count;
                int right = left + 2 * width;
                if (right > count)
                    right = count;

                int i = left;
                int j = mid;
                int k = left;
                while (i < mid && j < right)
                {
                    if (items[j].CompareTo(items[i]) < 0)
                    {
                        temp[k] = items[j];
                        j += 1;
                    }
                    else
                    {
                        temp[k] = items[i];
                        i += 1;
                    }
                    k += 1;
                }
                while (i < mid)
                {
                    temp[k] = items[i];
                    i += 1;
                    k += 1;
                }
                while (j < right)
                {
                    temp[k] = items[j];
                    j += 1;
                    k += 1;
                }
            }
            Array.Copy(temp, 0, items, 0, count);
        }
    }

    /// A new array with the elements, in order.
    T[] ToArray()
    {
        int count = Count();
        var result = new T[count];
        if (count > 0)
            Array.Copy(_state[0].Items, 0, result, 0, count);
        return result;
    }

    // ---- with functions (lambdas): list.ForEach(x => Console.WriteLine(x)), list.Where(x => x > 0) ----

    /// Calls `action` for every element, in order: `list.ForEach(x => Console.WriteLine(x))`.
    void ForEach(Action<T> action)
    {
        for (var i = 0; i < Count(); i += 1)
            action(Get(i));
    }

    /// A new list with the elements for which `keep` returns `true`: `list.Where(x => x > 0)`.
    List<T> Where(Func<T, bool> keep)
    {
        var result = List<T>.Create();
        for (var i = 0; i < Count(); i += 1)
        {
            T item = Get(i);
            if (keep(item))
                result.Add(item);
        }
        return result;
    }

    /// A new list with `convert` applied to every element: `list.Select<string>(x => x.ToString())`.
    List<U> Select<U>(Func<T, U> convert)
    {
        var result = List<U>.Create();
        for (var i = 0; i < Count(); i += 1)
            result.Add(convert(Get(i)));
        return result;
    }

    /// Whether `test` returns `true` for at least one element.
    bool Any(Func<T, bool> test)
    {
        return FindIndex(test) >= 0;
    }

    /// Whether `test` returns `true` for every element (`true` for an empty list).
    bool All(Func<T, bool> test)
    {
        for (var i = 0; i < Count(); i += 1)
        {
            if (!test(Get(i)))
                return false;
        }
        return true;
    }

    /// The index of the first element for which 'test' is true, or -1.
    int FindIndex(Func<T, bool> test)
    {
        for (var i = 0; i < Count(); i += 1)
        {
            if (test(Get(i)))
                return i;
        }
        return -1;
    }

    static string _NotCreated()
    {
        return "the list was not created (List<T>.Create() or []): the zero value (new(), a field without a value) is empty and cannot change";
    }

    // Makes sure the storage can hold at least 'needed' elements.
    void _Grow(int needed)
    {
        int capacity = 0;
        if (_state[0].Items != null)
            capacity = _state[0].Items.Length;
        if (needed <= capacity)
            return;

        int newCapacity = capacity == 0 ? 4 : capacity * 2;
        if (newCapacity < needed)
            newCapacity = needed;
        var items = new T[newCapacity];
        if (_state[0].Items != null)
            Array.Copy(_state[0].Items, 0, items, 0, _state[0].Count);
        _state[0].Items = items;
    }
}
