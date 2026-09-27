// Queue<T>: first in, first out.
//
//     var jobs = Queue<string>.Create();
//     jobs.Enqueue("load");
//     jobs.Enqueue("draw");
//     string next = jobs.Dequeue();         // "load"
//     if (jobs.TryDequeue() is string s)    // no panic when the queue is empty
//         ...
//
// Like List<T>, a Queue is a small handle to shared storage: copies see the same elements. foreach and Get(i)
// go from the front (the next Dequeue) to the back. The elements are kept in a ring buffer, so Enqueue and
// Dequeue do not move the other elements.

namespace System;

struct QueueState<T>
{
    T[] Items;
    int Head;   // index of the front element
    int Count;
}

struct Queue<T>
{
    QueueState<T>[] _state;

    static Queue<T> Create()
    {
        return Queue<T> { _state = new QueueState<T>[1] };
    }

    static Queue<T> Create(int capacity)
    {
        var queue = Create();
        queue._Grow(capacity);
        return queue;
    }

    int Count()
    {
        if (_state == null)
            return 0;
        return _state[0].Count;
    }

    void Enqueue(T value)
    {
        _Grow(Count() + 1);
        _state[0].Items[_Slot(_state[0].Count)] = value;
        _state[0].Count += 1;
    }

    // Removes and returns the front element; panics if the queue is empty (TryDequeue does not).
    T Dequeue()
    {
        if (Count() == 0)
            Environment.Panic("Dequeue on an empty Queue");
        return _Take();
    }

    Optional<T> TryDequeue()
    {
        if (Count() == 0)
            return null;
        return _Take();
    }

    // The front element without removing it; panics if the queue is empty (TryPeek does not).
    T Peek()
    {
        if (Count() == 0)
            Environment.Panic("Peek on an empty Queue");
        return _state[0].Items[_state[0].Head];
    }

    Optional<T> TryPeek()
    {
        if (Count() == 0)
            return null;
        return _state[0].Items[_state[0].Head];
    }

    // The element 'index' places behind the front (0 = the front).
    T Get(int index)
    {
        int count = Count();
        if (index < 0 || index >= count)
            Environment.Panic("Queue index out of range (index " + index.ToString() + ", count " + count.ToString() + ")");
        return _state[0].Items[_Slot(index)];
    }

    bool Contains(T value)
        where T : IEquatable<T>
    {
        int count = Count();
        for (var i = 0; i < count; i += 1)
        {
            if (_state[0].Items[_Slot(i)].Equals(value))
                return true;
        }
        return false;
    }

    void Clear()
    {
        if (_state == null)
            return;
        _state[0].Items = null;
        _state[0].Head = 0;
        _state[0].Count = 0;
    }

    // The elements from the front to the back (the order Dequeue would return them).
    T[] ToArray()
    {
        int count = Count();
        var result = new T[count];
        for (var i = 0; i < count; i += 1)
            result[i] = _state[0].Items[_Slot(i)];
        return result;
    }

    // The position in Items of the element 'index' places behind the front.
    int _Slot(int index)
    {
        int slot = _state[0].Head + index;
        int capacity = _state[0].Items.Length;
        return slot >= capacity ? slot - capacity : slot;
    }

    T _Take()
    {
        int head = _state[0].Head;
        T value = _state[0].Items[head];
        _state[0].Items[head] = default(T);
        head += 1;
        _state[0].Head = head == _state[0].Items.Length ? 0 : head;
        _state[0].Count -= 1;
        return value;
    }

    // Makes sure the storage exists and can hold at least 'needed' elements (the front moves to index 0).
    void _Grow(int needed)
    {
        if (_state == null)
            _state = new QueueState<T>[1];
        int capacity = 0;
        if (_state[0].Items != null)
            capacity = _state[0].Items.Length;
        if (needed <= capacity)
            return;

        int newCapacity = capacity == 0 ? 4 : capacity * 2;
        if (newCapacity < needed)
            newCapacity = needed;
        var items = new T[newCapacity];
        int count = _state[0].Count;
        for (var i = 0; i < count; i += 1)
            items[i] = _state[0].Items[_Slot(i)];
        _state[0].Items = items;
        _state[0].Head = 0;
    }
}
