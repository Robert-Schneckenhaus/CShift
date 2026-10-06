// expect-exit: 101
// expect-stderr: panic: the list was not created (List<T>.Create() or []): the zero value (new(), a field without a value) is empty and cannot change
// expect-stderr: panic_not_created.csh:22:24 in Main
// arc-ignore
// The zero value of a List (here a field that was not given one) can be read, but adding to it panics where the program
// adds; it does not create the storage on its own.
using System;

struct Inventory
{
    string Owner;
    List<string> Items;
}

int Main()
{
    var inventory = Inventory { Owner = "ann" };
    if (inventory.Items.Count() != 0 || inventory.Items.IsCreated())
        return 1;
    foreach (var item in inventory.Items)
        return 2;
    inventory.Items.Add("lamp");
    return 0;
}
