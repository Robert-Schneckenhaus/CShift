// Pop on an empty stack panics and names the caller.
// expect-exit: 101
// expect-stderr: panic: Pop on an empty Stack
// expect-stderr:   called from
// expect-stderr: panic_stack_empty.csh:13:21 in Main
// arc-ignore

using System;

int Main()
{
    var stack = Stack<int>.Create();
    return stack.Pop();
}
