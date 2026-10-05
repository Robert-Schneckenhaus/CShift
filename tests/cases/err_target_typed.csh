// Target-typed integer arithmetic: an operand that does not fit the target type means the usual rules apply (and the
// result needs a cast); a constant expression that does not fit is an error.
// expect-error: err_target_typed.csh:14:16: error: cannot implicitly convert 'int32' to 'uint8'
// expect-error: err_target_typed.csh:15:16: error: cannot implicitly convert 'int32' to 'uint8'
// expect-error: err_target_typed.csh:16:16: error: cannot implicitly convert 'int32' to 'uint8'
// expect-error: err_target_typed.csh:17:16: error: cannot implicitly convert 'int32' to 'uint8'
// expect-error: err_target_typed.csh:19:20: error: operator cannot mix 'uint64' and signed types
// expect-error: err_target_typed.csh:21:24: error: integer overflow in a constant expression (the value does not fit into uint8)
int Main()
{
    uint8 a = 200;
    int8 n = -5;
    int32 i = 7;
    uint8 e1 = a + n;        // uint8 + int8 needs int16
    uint8 e2 = a + i;        // int32 does not fit uint8
    uint8 e3 = -a;           // unary minus: only in a signed type
    uint8 e4 = 200 + 100;    // 300 does not fit
    uint64 big = 5;
    int64 e5 = big + i;
    const uint8 K = 200;
    const uint8 E6 = K + 100;
    return 0;
}
