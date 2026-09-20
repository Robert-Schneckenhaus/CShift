// List<T>: a growable array.
//
//     using System;
//
//     var names = List<string>.Create();
//     names.Add("Ann");
//     names.Add("Bob");
//     foreach (var name in names)
//         Console.WriteLine(name);
//
// A List is a small handle to shared storage: copies of a List (assignments, arguments) see the same
// elements, like a reference. The storage is created by Create() or by the first Add(); a list that is
// still empty and was created with 'new List<T>()' is not yet connected to its copies, so start lists with
// List<T>.Create() when you hand them out before adding elements.

namespace System;

struct ListState<T>
{
    T[] Items;
    int Count;
}

struct List<T>
{
    ListState<T>[] _state;

    static List<T> Create()
    {
        return List<T> { _state = new ListState<T>[1] };
    }

    static List<T> Create(int capacity)
    {
        var list = Create();
        list._Grow(capacity);
        return list;
    }

    int Count()
    {
        if (_state == null)
            return 0;
        return _state[0].Count;
    }

    // Number of elements that fit without reallocating.
    int Capacity()
    {
        if (_state == null || _state[0].Items == null)
            return 0;
        return _state[0].Items.Length;
    }

    T Get(int index)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range");
        return _state[0].Items[index];
    }

    void Set(int index, T value)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range");
        _state[0].Items[index] = value;
    }

    void Add(T value)
    {
        _Grow(Count() + 1);
        _state[0].Items[_state[0].Count] = value;
        _state[0].Count += 1;
    }

    void AddRange(T[] values)
    {
        for (var i = 0; i < values.Length; i += 1)
            Add(values[i]);
    }

    // Inserts before the element at index (index == Count() appends).
    void Insert(int index, T value)
    {
        if (index < 0 || index > Count())
            Environment.Panic("List index out of range");
        _Grow(Count() + 1);
        int count = _state[0].Count;
        Array.Copy(_state[0].Items, index, _state[0].Items, index + 1, count - index);
        _state[0].Items[index] = value;
        _state[0].Count += 1;
    }

    void RemoveAt(int index)
    {
        if (index < 0 || index >= Count())
            Environment.Panic("List index out of range");
        int count = _state[0].Count;
        Array.Copy(_state[0].Items, index + 1, _state[0].Items, index, count - index - 1);
        _state[0].Items[count - 1] = default(T);
        _state[0].Count -= 1;
    }

    void Clear()
    {
        if (_state == null)
            return;
        _state[0].Items = null;
        _state[0].Count = 0;
    }

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

    bool Contains(T value)
        where T : IEquatable<T>
    {
        return IndexOf(value) >= 0;
    }

    // Removes the first element that equals value.
    bool Remove(T value)
        where T : IEquatable<T>
    {
        int index = IndexOf(value);
        if (index < 0)
            return false;
        RemoveAt(index);
        return true;
    }

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

    // Stable merge sort.
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

    T[] ToArray()
    {
        int count = Count();
        var result = new T[count];
        if (count > 0)
            Array.Copy(_state[0].Items, 0, result, 0, count);
        return result;
    }

    // Makes sure the storage exists and can hold at least 'needed' elements.
    void _Grow(int needed)
    {
        if (_state == null)
            _state = new ListState<T>[1];
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
