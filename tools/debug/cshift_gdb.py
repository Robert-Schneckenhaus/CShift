# Pretty printers for CShift programs in gdb (programs built with cshiftc -g).
#
# cshiftc puts this script into every program it builds with -g (the section .debug_gdb_scripts), so gdb loads it by
# itself when the program's folder is allowed (gdb asks for "add-auto-load-safe-path"). It can also be loaded by hand:
#     (gdb) source <cshift>/tools/debug/cshift_gdb.py
#
# Strings print as text, arrays, slices, List, Stack, Queue, HashSet and Dictionary as their elements, Optional<T> as
# its value or null, SharedPtr<T> as the value it holds.

import gdb

MAX_ITEMS = 10000


def _addr(val):
    return int(val.cast(gdb.lookup_type("long").pointer()) if val.type.strip_typedefs().code == gdb.TYPE_CODE_PTR else val)


def _block(ptr):
    """The block a string/array/SharedPtr points to, or None for null."""
    if int(ptr) == 0:
        return None
    return ptr.dereference()


def _text(address, length):
    if length <= 0:
        return '""'
    n = min(length, MAX_ITEMS)
    data = bytes(gdb.selected_inferior().read_memory(address, n))
    text = data.decode("utf-8", "replace").replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + text + ('..."' if n < length else '"')


def _elements(first, count):
    """Children [0], [1], ... of 'count' elements starting at the pointer 'first'."""
    for i in range(min(count, MAX_ITEMS)):
        yield "[%d]" % i, (first + i).dereference()


def _array_parts(ptr):
    """(pointer to the first element, length) of an array block; (None, 0) for null."""
    block = _block(ptr)
    if block is None:
        return None, 0
    items = block["items"]
    first = items.address.cast(items.type.strip_typedefs().target().pointer())
    return first, int(block["length"])


class StringPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        block = _block(self.val)
        if block is None:
            return "null"
        return _text(int(block["chars"].address), int(block["length"]))


class ArrayPrinter:
    def __init__(self, val):
        self.val = val
        self.first, self.length = _array_parts(val)

    def to_string(self):
        if self.first is None:
            return "null"
        return "%s of length %d" % (self.val.type.name, self.length)

    def children(self):
        if self.first is None:
            return iter(())
        return _elements(self.first, self.length)

    def display_hint(self):
        return "array"


class SlicePrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        name = str(self.val.type.strip_typedefs().tag or self.val.type)
        length = int(self.val["length"])
        if name == "StringSlice":
            return _text(int(self.val["data"]), length)
        return "%s of length %d" % (name, length)

    def children(self):
        if str(self.val.type.strip_typedefs().tag) == "StringSlice":
            return iter(())
        return _elements(self.val["data"], int(self.val["length"]))

    def display_hint(self):
        return "array"


def _state(val):
    """The state struct of List/Stack/Queue/Dictionary/StringBuilder (_state is an array of one element)."""
    first, length = _array_parts(val["_state"])
    if first is None or length == 0:
        return None
    return first.dereference()


class ListPrinter:
    """List<T>, Stack<T> (Items + Count) and Queue<T> (Items + Head + Count, a ring)."""

    def __init__(self, val, kind):
        self.val = val
        self.kind = kind
        self.state = _state(val)

    def _parts(self):
        if self.state is None:
            return None, 0, 0, 0
        first, capacity = _array_parts(self.state["Items"])
        head = int(self.state["Head"]) if self.kind == "Queue" else 0
        return first, int(self.state["Count"]), head, capacity

    def to_string(self):
        first, count, head, capacity = self._parts()
        return "%s with %d elements" % (self.kind, count)

    def children(self):
        first, count, head, capacity = self._parts()
        for i in range(min(count, MAX_ITEMS)):
            index = (head + i) % capacity if capacity > 0 else i
            yield "[%d]" % i, (first + index).dereference()

    def display_hint(self):
        return "array"


def _dictionary_entries(val):
    state = _state(val)
    if state is None:
        return
    first, _ = _array_parts(state["Entries"])
    for i in range(min(int(state["Count"]), MAX_ITEMS)):
        entry = (first + i).dereference()
        if int(entry["Hash"]) >= 0:
            yield entry


class DictionaryPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        return "Dictionary with %d entries" % sum(1 for _ in _dictionary_entries(self.val))

    def children(self):
        for i, entry in enumerate(_dictionary_entries(self.val)):
            yield "[%d]" % (2 * i), entry["Key"]
            yield "[%d]" % (2 * i + 1), entry["Value"]

    def display_hint(self):
        return "map"


class HashSetPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        return "HashSet with %d elements" % sum(1 for _ in _dictionary_entries(self.val["_map"]))

    def children(self):
        for i, entry in enumerate(_dictionary_entries(self.val["_map"])):
            yield "[%d]" % i, entry["Key"]

    def display_hint(self):
        return "array"


class StringBuilderPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        state = _state(self.val)
        if state is None:
            return '""'
        first, _ = _array_parts(state["Data"])
        return _text(int(first), int(state["Length"]))


class OptionalPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        if not bool(self.val["HasValue"]):
            return "null"
        return self.val["Value"].format_string()


class UnionPrinter:
    """A union: the member its tag names (tag k is member k - 1), or empty."""

    def __init__(self, val):
        self.val = val

    def to_string(self):
        tag = int(self.val["tag"])
        value = self.val["value"]
        members = value.type.strip_typedefs().fields()
        if tag <= 0 or tag > len(members):
            return "empty"
        return "%s: %s" % (members[tag - 1].name, value[members[tag - 1].name].format_string())


class SharedPtrPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        block = _block(self.val)
        if block is None:
            return "null"
        return "SharedPtr to " + block["value"].format_string()


def _fields(t):
    try:
        return [f.name for f in t.fields()]
    except TypeError:
        return []


def lookup(val):
    t = val.type
    name = t.name or ""
    if name == "string":
        return StringPrinter(val)
    if name.endswith("[]"):
        return ArrayPrinter(val)
    if name.startswith("SharedPtr<"):
        return SharedPtrPrinter(val)
    basic = t.strip_typedefs()
    if basic.code != gdb.TYPE_CODE_STRUCT:
        return None
    tag = basic.tag or ""
    for prefix, kind in (("System.List<", "List"), ("System.Stack<", "Stack"), ("System.Queue<", "Queue")):
        if tag.startswith(prefix):
            return ListPrinter(val, kind)
    if tag.startswith("System.Dictionary<"):
        return DictionaryPrinter(val)
    if tag.startswith("System.HashSet<"):
        return HashSetPrinter(val)
    if tag == "System.StringBuilder":
        return StringBuilderPrinter(val)
    fields = _fields(basic)
    if fields == ["owner", "data", "length"]:
        return SlicePrinter(val)
    if fields == ["HasValue", "Value"]:
        return OptionalPrinter(val)
    if fields == ["tag", "value"]:
        return UnionPrinter(val)
    return None


def register(objfile=None):
    target = objfile if objfile is not None else gdb
    if lookup not in target.pretty_printers:
        target.pretty_printers.append(lookup)


register(gdb.current_objfile())
