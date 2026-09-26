#include "apply.h"
int apply_twice(IntFn f, int v) { return f(f(v)); }
