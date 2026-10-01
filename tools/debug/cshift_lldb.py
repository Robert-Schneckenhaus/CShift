# Formatters for CShift programs in lldb (programs built with cshiftc -g). Load them with
#     (lldb) command script import <cshift>/tools/debug/cshift_lldb.py
# (or put that line into ~/.lldbinit).
#
# Strings print as text, arrays, slices, List, Stack, Queue, HashSet and Dictionary as their elements, Optional<T> as
# its value or null, SharedPtr<T> as the value it holds, a union as the member it holds.

import lldb

MAX_ITEMS = 10000


def _ptr_size(valobj):
    return valobj.GetTarget().GetAddressByteSize()


def _text(valobj, address, length):
    if length <= 0:
        return '""'
    n = min(length, MAX_ITEMS)
    error = lldb.SBError()
    data = valobj.GetProcess().ReadMemory(address, n, error)
    if not error.Success():
        return "<unreadable>"
    text = data.decode("utf-8", "replace").replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return '"' + text + ('..."' if n < length else '"')


def _array_parts(ptr):
    """(address of the first element, length, element type) of a string/array block; (0, 0, None) for null."""
    address = ptr.GetValueAsUnsigned()
    if address == 0:
        return 0, 0, None
    block = ptr.Dereference()
    length = block.GetChildMemberWithName("length").GetValueAsSigned()
    items = block.GetChildMemberWithName("items")
    if not items.IsValid():
        items = block.GetChildMemberWithName("chars")
    return address + 2 * _ptr_size(ptr), length, items.GetType().GetArrayElementType()


def string_summary(valobj, internal_dict):
    first, length, _ = _array_parts(valobj)
    if first == 0:
        return "null"
    return _text(valobj, first, length)


class _Elements:
    """Synthetic children [0], [1], ... of elements in memory; subclasses set self.first, self.count, self.type."""

    def __init__(self, valobj, internal_dict):
        self.valobj = valobj
        self.first = 0
        self.count = 0
        self.type = None
        self.wrap = 0
        self.head = 0

    def num_children(self):
        return min(self.count, MAX_ITEMS)

    def get_child_index(self, name):
        try:
            return int(name.lstrip("[").rstrip("]"))
        except ValueError:
            return -1

    def get_child_at_index(self, index):
        if self.type is None or index < 0 or index >= self.count:
            return None
        if self.wrap > 0:
            index = (self.head + index) % self.wrap
        return self.valobj.CreateValueFromAddress("[%d]" % index, self.first + index * self.type.GetByteSize(), self.type)

    def has_children(self):
        return True


class ArrayProvider(_Elements):
    def update(self):
        self.first, self.count, self.type = _array_parts(self.valobj)
        return False


def array_summary(valobj, internal_dict):
    target = valobj.GetNonSyntheticValue()
    if target.GetValueAsUnsigned() == 0:
        return "null"
    # lldb does not unfold a pointer by itself, so the first elements are part of the summary
    count = valobj.GetNumChildren()
    shown = [_shown(valobj.GetChildAtIndex(i)) for i in range(min(count, 20))]
    return "length %d [%s%s]" % (count, ", ".join(shown), ", ..." if count > 20 else "")


class SliceProvider(_Elements):
    def update(self):
        data = self.valobj.GetChildMemberWithName("data")
        self.first = data.GetValueAsUnsigned()
        self.count = self.valobj.GetChildMemberWithName("length").GetValueAsSigned()
        self.type = data.GetType().GetPointeeType()
        return False


def slice_summary(valobj, internal_dict):
    target = valobj.GetNonSyntheticValue()
    length = target.GetChildMemberWithName("length").GetValueAsSigned()
    if target.GetTypeName() == "StringSlice":
        return _text(valobj, target.GetChildMemberWithName("data").GetValueAsUnsigned(), length)
    return "length %d" % length


def _state(valobj):
    """The state struct of List/Stack/Queue/Dictionary/StringBuilder (_state is an array of one element)."""
    first, length, elem = _array_parts(valobj.GetNonSyntheticValue().GetChildMemberWithName("_state"))
    if first == 0 or length == 0:
        return None
    return valobj.CreateValueFromAddress("state", first, elem)


class ListProvider(_Elements):
    """List<T> and Stack<T> (Items + Count), Queue<T> (Items + Head + Count, a ring)."""

    def update(self):
        state = _state(self.valobj)
        if state is None:
            self.count = 0
            return False
        self.first, capacity, self.type = _array_parts(state.GetChildMemberWithName("Items"))
        self.count = state.GetChildMemberWithName("Count").GetValueAsSigned()
        head = state.GetChildMemberWithName("Head")
        if head.IsValid():
            self.head = head.GetValueAsSigned()
            self.wrap = capacity
        return False


def count_summary(valobj, internal_dict):
    return "%d elements" % valobj.GetNumChildren()


def _dictionary_entries(valobj):
    state = _state(valobj)
    if state is None:
        return []
    first, _, elem = _array_parts(state.GetChildMemberWithName("Entries"))
    entries = []
    for i in range(min(state.GetChildMemberWithName("Count").GetValueAsSigned(), MAX_ITEMS)):
        entry = valobj.CreateValueFromAddress("entry", first + i * elem.GetByteSize(), elem)
        if entry.GetChildMemberWithName("Hash").GetValueAsSigned() >= 0:
            entries.append(entry)
    return entries


class DictionaryProvider:
    def __init__(self, valobj, internal_dict):
        self.valobj = valobj
        self.entries = []

    def update(self):
        self.entries = _dictionary_entries(self.valobj)
        return False

    def num_children(self):
        return len(self.entries)

    def get_child_index(self, name):
        return -1

    def get_child_at_index(self, index):
        if index < 0 or index >= len(self.entries):
            return None
        entry = self.entries[index]
        key = entry.GetChildMemberWithName("Key")
        value = entry.GetChildMemberWithName("Value")
        summary = key.GetSummary() or key.GetValue() or ""
        return value.CreateValueFromData("[%s]" % summary, value.GetData(), value.GetType())

    def has_children(self):
        return True


class HashSetProvider(DictionaryProvider):
    def update(self):
        self.entries = _dictionary_entries(self.valobj.GetChildMemberWithName("_map"))
        return False

    def get_child_at_index(self, index):
        if index < 0 or index >= len(self.entries):
            return None
        key = self.entries[index].GetChildMemberWithName("Key")
        return key.CreateValueFromData("[%d]" % index, key.GetData(), key.GetType())


def string_builder_summary(valobj, internal_dict):
    state = _state(valobj)
    if state is None:
        return '""'
    first, _, _ = _array_parts(state.GetChildMemberWithName("Data"))
    return _text(valobj, first, state.GetChildMemberWithName("Length").GetValueAsSigned())


def _shown(value):
    return value.GetSummary() or value.GetValue() or ""


def optional_summary(valobj, internal_dict):
    if not valobj.GetChildMemberWithName("HasValue").GetValueAsUnsigned():
        return "null"
    return _shown(valobj.GetChildMemberWithName("Value"))


def shared_ptr_summary(valobj, internal_dict):
    if valobj.GetValueAsUnsigned() == 0:
        return "null"
    return "SharedPtr to " + _shown(valobj.Dereference().GetChildMemberWithName("value"))


def union_summary(valobj, internal_dict):
    tag = valobj.GetChildMemberWithName("tag").GetValueAsSigned()
    value = valobj.GetChildMemberWithName("value")
    if tag <= 0 or tag > value.GetNumChildren():
        return "empty"
    member = value.GetChildAtIndex(tag - 1)
    return "%s: %s" % (member.GetName(), _shown(member))


def is_union(sbtype, internal_dict):
    t = sbtype.GetCanonicalType()
    return t.GetNumberOfFields() == 2 and t.GetFieldAtIndex(0).GetName() == "tag" and t.GetFieldAtIndex(1).GetName() == "value"


def __lldb_init_module(debugger, internal_dict):
    m = __name__
    commands = [
        'type summary add -w cshift -F %s.string_summary string' % m,
        'type synthetic add -w cshift -x "^.+\\[\\]$" -l %s.ArrayProvider' % m,
        'type summary add -w cshift -x "^.+\\[\\]$" -F %s.array_summary' % m,
        'type synthetic add -w cshift -x "^(Slice|ReadOnlySlice)<.+>$" -l %s.SliceProvider' % m,
        'type summary add -w cshift -x "^(Slice<.+>|ReadOnlySlice<.+>|StringSlice)$" -e -F %s.slice_summary' % m,
        'type synthetic add -w cshift -x "^System\\.(List|Stack|Queue)<.+>$" -l %s.ListProvider' % m,
        'type summary add -w cshift -x "^System\\.(List|Stack|Queue)<.+>$" -e -F %s.count_summary' % m,
        'type synthetic add -w cshift -x "^System\\.Dictionary<.+>$" -l %s.DictionaryProvider' % m,
        'type summary add -w cshift -x "^System\\.Dictionary<.+>$" -e -F %s.count_summary' % m,
        'type synthetic add -w cshift -x "^System\\.HashSet<.+>$" -l %s.HashSetProvider' % m,
        'type summary add -w cshift -x "^System\\.HashSet<.+>$" -e -F %s.count_summary' % m,
        'type summary add -w cshift -F %s.string_builder_summary System.StringBuilder' % m,
        'type summary add -w cshift -x "^Optional<.+>$" -F %s.optional_summary' % m,
        'type summary add -w cshift -x "^SharedPtr<.+>$" -F %s.shared_ptr_summary' % m,
        'type summary add -w cshift --recognizer-function %s.is_union -F %s.union_summary' % (m, m),
        'type category enable cshift',
    ]
    for command in commands:
        debugger.HandleCommand(command)
