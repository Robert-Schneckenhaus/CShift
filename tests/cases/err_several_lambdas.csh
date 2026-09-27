// Errors inside lambda bodies are found too; the lambda's 'return' is not checked against the enclosing function.
// expect-error: err_several_lambdas.csh:11:38: error: undefined name 'limit'
// expect-error: err_several_lambdas.csh:12:50: error: undefined name 'undefinedThing'

using System;

int Main()
{
    var numbers = List<int>.Create();
    numbers.Add(2);
    var big = numbers.Where(x => x > limit);
    numbers.ForEach(x => { Console.WriteLine(x + undefinedThing); });
    Func<int, string> show = x => { return x.ToString(); };
    return big.Count() + show(1).Length;
}
