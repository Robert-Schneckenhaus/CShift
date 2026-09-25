// A method of a struct that is reached while another struct is laid out may take that outer struct by value or
// return a struct that contains it: only fields make a struct contain itself.
// expect-stdout: roll 7
// expect-stdout: enter 3
// expect-stdout: push 6
// expect-stdout: wrapped 1
using System;

struct Battle
{
    int Base;

    int Roll(Session session)
    {
        return session.Count + Base;
    }
}

struct Modal
{
    int Value;

    void Enter(Session session)
    {
        Console.WriteLine("enter " + (session.Count + Value));
    }

    Wrapper Wrap(Session session)
    {
        return Wrapper { Inner = session };
    }
}

struct Wrapper
{
    Session Inner;
}

struct Stack
{
    List<Modal> Modals;

    void Push(Session session, int value)
    {
        Console.WriteLine("push " + (session.Count + value));
    }
}

struct Session
{
    int Count;
    Stack Stack;
    Dictionary<int, Battle> Battles;
}

int Main()
{
    var s = Session { Count = 1, Stack = Stack { Modals = List<Modal>.Create() }, Battles = Dictionary<int, Battle>.Create() };
    s.Battles.Set(1, Battle { Base = 6 });
    s.Stack.Modals.Add(Modal { Value = 2 });
    if (s.Battles.TryGet(1) is Battle battle)
        Console.WriteLine("roll " + battle.Roll(s));
    s.Stack.Modals.Get(0).Enter(s);
    s.Stack.Push(s, 5);
    Console.WriteLine("wrapped " + s.Stack.Modals.Get(0).Wrap(s).Inner.Count);
    return 0;
}
