// Characters do not become text by themselves (they need not be UTF-8); a string and a StringSlice become characters.
// expect-error: err_chars_to_text.csh:9:24: error: cannot implicitly convert 'ReadOnlySlice<char>' to 'StringSlice'
// expect-error: err_chars_to_text.csh:10:34: error: cannot implicitly convert 'string' to 'ReadOnlySlice<uint8>'
using System;

int Main()
{
    ReadOnlySlice<char> chars = "abc";
    StringSlice text = chars;
    ReadOnlySlice<uint8> bytes = "abc";
    return text.Length + bytes.Length;
}
