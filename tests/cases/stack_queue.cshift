// Stack<T> (last in, first out) and Queue<T> (first in, first out, a ring buffer that wraps around and grows).
// expect-exit: 0
// expect-stdout: stack pop c b
// expect-stdout: stack foreach a
// expect-stdout: stack try none
// expect-stdout: queue 1 2 3 4 5 6 7 8 9 10
// expect-stdout: queue front 11 count 5 get 13 contains true false
// expect-stdout: queue array 11,12,13,14,15
// expect-stdout: queue shared 0

using System;

int Main()
{
    var stack = Stack<string>.Create();
    stack.Push("a");
    stack.Push("b");
    stack.Push("c");
    string first = stack.Pop();
    string second = stack.Pop();
    Console.WriteLine("stack pop " + first + " " + second);
    string all = "";
    foreach (var s in stack)
        all += s;
    Console.WriteLine("stack foreach " + all);
    stack.Pop();
    string tried = stack.TryPop() is string t ? t : "none";
    Console.WriteLine("stack try " + tried);

    // the queue wraps around its ring buffer several times while it grows
    var queue = Queue<int>.Create(2);
    string dequeued = "";
    int next = 1;
    for (var round = 0; round < 5; round += 1)
    {
        queue.Enqueue(next);
        queue.Enqueue(next + 1);
        queue.Enqueue(next + 2);
        next += 3;
        dequeued += " " + queue.Dequeue().ToString() + " " + queue.Dequeue().ToString();
    }
    // 15 enqueued, 10 dequeued: 11..15 remain
    Console.WriteLine("queue" + dequeued);
    Console.WriteLine("queue front " + queue.Peek().ToString() + " count " + queue.Count().ToString() + " get " + queue.Get(2).ToString() +
                      " contains " + queue.Contains(15).ToString().ToLower() + " " + queue.Contains(10).ToString().ToLower());
    string items = "";
    foreach (var n in queue.ToArray())
        items += (items.Length > 0 ? "," : "") + n.ToString();
    Console.WriteLine("queue array " + items);

    var copy = queue;       // copies share the storage
    copy.Clear();
    Console.WriteLine("queue shared " + queue.Count().ToString());
    if (queue.TryDequeue() is int)
        return 1;

    // the zero values are empty and can be read (Push and Enqueue panic)
    var zeroStack = new Stack<int>();
    var zeroQueue = new Queue<int>();
    if (zeroStack.Count() != 0 || zeroQueue.Count() != 0 || zeroStack.IsCreated() || zeroQueue.IsCreated() ||
        zeroStack.TryPop() is int || zeroQueue.TryDequeue() is int || !queue.IsCreated())
        return 2;
    return 0;
}
