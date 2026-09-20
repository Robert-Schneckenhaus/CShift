using Geo from "../native/geo.h";

struct Tester
{
    int Failed;

    void Check(bool ok, string what)
    {
        if (!ok)
        {
            Failed += 1;
            Console.WriteLine("FAIL: " + what);
        }
    }
}

// callbacks that C calls
int Twice(int v)
{
    return v * 2;
}

bool IsPositive(int v)
{
    return v > 0;
}

int8 Negate(int8 v)
{
    return (int8)(-v);
}

void Collect(Geo.GeoPoint* p, void* user)
{
    unsafe
    {
        int* total = (int*)user;
        *total = *total + p->x + p->y;
    }
}

char* NameOf(Geo.GeoColor c)
{
    unsafe
    {
        return "custom".CStr();
    }
}

int Main()
{
    var t = new Tester();

    // constants (macros and enumerators)
    t.Check(Geo.GEO_VERSION == 3, "macro int");
    t.Check(Geo.GEO_NAME == "geo", "macro string");
    t.Check(Geo.GEO_PI > 3.14 && Geo.GEO_PI < 3.15, "macro double");
    t.Check(Geo.GEO_FLAG_B == 2, "macro expression");
    t.Check(Geo.GEO_GREEN == Geo.GeoColor.GEO_GREEN, "enumerator");

    // plain values; C int is int32, size_t is nuint
    t.Check(Geo.geo_add(40, 2) == 42, "geo_add");
    t.Check(Geo.geo_umax(7u, 9u) == 9u, "geo_umax");
    t.Check(Geo.geo_mul_long(1000, 3000) == 3000000, "geo_mul_long");
    t.Check(Geo.geo_hypot(3.0, 4.0) == 25.0, "geo_hypot");
    t.Check(Geo.geo_low_byte(0x1234u) == 0x34, "geo_low_byte");
    t.Check(Geo.geo_is_even(4) && !Geo.geo_is_even(5), "geo_is_even");

    // strings: string -> const char*, const char* -> string
    nuint len = Geo.geo_strlen("hello");
    t.Check(len == 5, "geo_strlen");
    t.Check(Geo.geo_color_name(Geo.GeoColor.GEO_BLUE) == "blue", "geo_color_name");
    t.Check(Geo.geo_count_char("banana", 'a') == 3, "geo_count_char");

    // pointers as ref
    int a = 1;
    int b = 2;
    Geo.geo_swap(ref a, ref b);
    t.Check(a == 2 && b == 1, "geo_swap");

    int q = 0;
    int r = 0;
    t.Check(Geo.geo_divmod(17, 5, ref q, ref r) != 0, "geo_divmod result");
    t.Check(q == 3 && r == 2, "geo_divmod out");

    int[] values = new int[4];
    values[0] = 1;
    values[1] = 2;
    values[2] = 3;
    values[3] = 4;

    Geo.GeoPoint p = Geo.geo_point_make(3, 4);
    t.Check(p.x == 3 && p.y == 4, "struct by value return");
    Geo.geo_point_move(ref p, 1, 1);
    t.Check(p.x == 4 && p.y == 5, "struct via ref");
    Geo.GeoPoint origin = default(Geo.GeoPoint);
    t.Check(Geo.geo_point_dist2(p, origin) == 41, "const ref");
    t.Check(Geo.geo_optional(null) == -1, "nullable pointer");
    t.Check(Geo.geo_optional(p) == 9, "nullable pointer with value");

    // structs by value in both directions (shim)
    Geo.GeoPoint sum = Geo.geo_point_add(Geo.geo_point_make(1, 2), Geo.geo_point_make(10, 20));
    t.Check(sum.x == 11 && sum.y == 22, "struct by value args");
    Geo.GeoRect rect = Geo.geo_rect_make(Geo.geo_point_make(0, 0), Geo.geo_point_make(4, 5), 1.5);
    t.Check(rect.max.x == 4 && rect.weight == 1.5, "nested struct");
    t.Check(Geo.geo_rect_area(rect) == 20, "geo_rect_area");
    Geo.GeoVec v = new Geo.GeoVec();
    v.x = 1.0;
    v.y = 2.0;
    Geo.GeoVec scaled = Geo.geo_vec_scale(v, 3.0);
    t.Check(scaled.x == 3.0 && scaled.y == 6.0, "double struct");

    // opaque handle
    unsafe
    {
        Geo.GeoCanvas* canvas = Geo.geo_canvas_create(4, 4);
        Geo.geo_canvas_set(canvas, 1, 2, 99);
        t.Check(Geo.geo_canvas_get(canvas, 1, 2) == 99, "canvas");
        t.Check(Geo.geo_canvas_userdata(canvas) == null, "userdata null");
        // a callback stored by C and called later
        Geo.geo_canvas_set_callback(canvas, Twice);
        t.Check(Geo.geo_canvas_fire(canvas, 8) == 16, "stored callback");
        Geo.geo_canvas_set_callback(canvas, null);
        t.Check(Geo.geo_canvas_fire(canvas, 8) == -1, "stored null callback");
        Geo.geo_canvas_destroy(canvas);

        // callbacks: C calls a CShift function
        t.Check(Geo.geo_apply(Twice, 21) == 42, "callback into CShift");
        t.Check(Geo.geo_apply_or(Twice, 5, -7) == 10, "callback or fallback (callback)");
        t.Check(Geo.geo_apply_or(null, 5, -7) == -7, "callback or fallback (null)");
        t.Check(Geo.geo_apply_small(Negate, 5) == -5, "int8 callback");
        t.Check(Geo.geo_name_with(NameOf, Geo.GeoColor.GEO_RED) == "custom", "char* callback result");

        int* numbers = (int*)Memory.Allocate(4 * sizeof(int));
        numbers[0] = -1;
        numbers[1] = 5;
        numbers[2] = 0;
        numbers[3] = 9;
        t.Check(Geo.geo_count_if(numbers, 4, IsPositive) == 2, "bool callback");
        Memory.Free(numbers);

        int total = 0;
        Geo.geo_visit_points(Collect, (void*)&total);
        t.Check(total == 33, "callback with pointers");

        // function pointers inside structs and returned from C
        Geo.GeoOps ops = default(Geo.GeoOps);
        ops.fn = Twice;
        ops.base = 1;
        t.Check(Geo.geo_ops_run(ops, 10) == 21, "function pointer in a struct");
        Func<int, int> doubler = Geo.geo_get_doubler();
        t.Check(doubler != null && doubler(21) == 42, "C function pointer called from CShift");
    }

    if (t.Failed == 0)
        Console.WriteLine("ffi ok");
    return t.Failed;
}
