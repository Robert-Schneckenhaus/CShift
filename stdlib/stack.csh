namespace System;

/// The storage behind a [Stack]; use [Stack] instead.
/// @internal
struct StackState<T>
{
    T[] Items;
    int Count;
}

/// A stack of values: last in, first out.
///
/// ```
/// var undo = Stack<string>.Create();
/// undo.Push("move");
/// undo.Push("delete");
/// string last = undo.Pop();        // "delete"
/// if (undo.TryPop() is string s)   // no panic when the stack is empty
///     ...
/// ```
///
/// Like List<T>, a Stack is a small handle to shared storage: copies see the same elements. foreach and Get(i)
/// go from the top (the next Pop) to the bottom.
struct Stack<T>
{
    StackState<T>[] _state;

    /// A new, empty stack.
    static Stack<T> Create()
    {
        return Stack<T> { _state = new StackState<T>[1] };
    }

    /// A new, empty stack with room for `capacity` elements before it has to grow.
    static Stack<T> Create(int capacity)
    {
        var stack = Create();
        stack._Grow(capacity);
        return stack;
    }

    /// The number of elements.
    int Count()
    {
        if (_state == null)
            return 0;
        return _state[0].Count;
    }

    /// Puts `value` on top of the stack.
    void Push(T value)
    {
        _Grow(Count() + 1);
        _state[0].Items[_state[0].Count] = value;
        _state[0].Count += 1;
    }

    /// Removes and returns the top element.
    /// @panics when the stack is empty ([Stack<T>.TryPop] does not).
    T Pop()
    {
        if (Count() == 0)
            Environment.Panic("Pop on an empty Stack");
        return _Take();
    }

    /// Removes and returns the top element, if there is one.
    /// @returns nothing (`null`) when the stack is empty.
    Optional<T> TryPop()
    {
        if (Count() == 0)
            return null;
        return _Take();
    }

    /// The top element, without removing it.
    /// @panics when the stack is empty ([Stack<T>.TryPeek] does not).
    T Peek()
    {
        if (Count() == 0)
            Environment.Panic("Peek on an empty Stack");
        return _state[0].Items[_state[0].Count - 1];
    }

    /// The top element without removing it, if there is one.
    /// @returns nothing (`null`) when the stack is empty.
    Optional<T> TryPeek()
    {
        if (Count() == 0)
            return null;
        return _state[0].Items[_state[0].Count - 1];
    }

    /// The element `index` places below the top (0 is the top).
    /// @panics when `index` is not in 0 to `Count() - 1`.
    T Get(int index)
    {
        int count = Count();
        if (index < 0 || index >= count)
            Environment.Panic("Stack index out of range (index " + index.ToString() + ", count " + count.ToString() + ")");
        return _state[0].Items[count - 1 - index];
    }

    /// Whether an element equals `value` ([IEquatable]).
    bool Contains(T value)
        where T : IEquatable<T>
    {
        int count = Count();
        for (var i = 0; i < count; i += 1)
        {
            if (_state[0].Items[i].Equals(value))
                return true;
        }
        return false;
    }

    /// Removes all elements.
    void Clear()
    {
        if (_state == null)
            return;
        _state[0].Items = null;
        _state[0].Count = 0;
    }

    /// The elements from the top to the bottom (the order Pop would return them).
    T[] ToArray()
    {
        int count = Count();
        var result = new T[count];
        for (var i = 0; i < count; i += 1)
            result[i] = _state[0].Items[count - 1 - i];
        return result;
    }

    T _Take()
    {
        int last = _state[0].Count - 1;
        T value = _state[0].Items[last];
        _state[0].Items[last] = default(T);
        _state[0].Count = last;
        return value;
    }

    // Makes sure the storage exists and can hold at least 'needed' elements.
    void _Grow(int needed)
    {
        if (_state == null)
            _state = new StackState<T>[1];
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
