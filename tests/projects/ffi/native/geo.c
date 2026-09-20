#include "geo.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int geo_add(int a, int b) { return a + b; }
unsigned int geo_umax(unsigned int a, unsigned int b) { return a > b ? a : b; }
long geo_mul_long(long a, long b) { return a * b; }
size_t geo_strlen(const char* s) { return strlen(s); }
double geo_hypot(double x, double y) { return x * x + y * y; }
uint8_t geo_low_byte(uint32_t v) { return (uint8_t)(v & 0xFF); }
_Bool geo_is_even(int v) { return (v % 2) == 0; }

const char* geo_color_name(GeoColor c)
{
    switch (c)
    {
    case GEO_RED: return "red";
    case GEO_GREEN: return "green";
    case GEO_BLUE: return "blue";
    }
    return NULL;
}

int geo_count_char(const char* s, char c)
{
    int n = 0;
    for (; *s; s++)
        if (*s == c)
            n++;
    return n;
}

void geo_upper(char* buffer, size_t size)
{
    for (size_t i = 0; i < size && buffer[i]; i++)
        buffer[i] = (char)toupper((unsigned char)buffer[i]);
}

void geo_swap(int* a, int* b)
{
    int t = *a;
    *a = *b;
    *b = t;
}

int geo_sum(const int* values, size_t count)
{
    int s = 0;
    for (size_t i = 0; i < count; i++)
        s += values[i];
    return s;
}

int geo_divmod(int a, int b, int* quotient, int* remainder)
{
    if (b == 0)
        return 0;
    *quotient = a / b;
    *remainder = a % b;
    return 1;
}

void geo_point_move(GeoPoint* p, int dx, int dy)
{
    p->x += dx;
    p->y += dy;
}

int geo_point_dist2(const GeoPoint* a, const GeoPoint* b)
{
    int dx = a->x - b->x, dy = a->y - b->y;
    return dx * dx + dy * dy;
}

int geo_optional(const GeoPoint* p) { return p ? p->x + p->y : -1; }

GeoPoint geo_point_make(int x, int y)
{
    GeoPoint p = {x, y};
    return p;
}

GeoPoint geo_point_add(GeoPoint a, GeoPoint b)
{
    GeoPoint p = {a.x + b.x, a.y + b.y};
    return p;
}

GeoRect geo_rect_make(GeoPoint min, GeoPoint max, double weight)
{
    GeoRect r = {min, max, weight};
    return r;
}

int geo_rect_area(GeoRect r) { return (r.max.x - r.min.x) * (r.max.y - r.min.y); }

GeoVec geo_vec_scale(GeoVec v, double f)
{
    GeoVec r = {v.x * f, v.y * f};
    return r;
}

struct GeoCanvas
{
    int width, height;
    int* cells;
    void* userdata;
    GeoCallback callback;
};

GeoCanvas* geo_canvas_create(int width, int height)
{
    GeoCanvas* c = (GeoCanvas*)malloc(sizeof(GeoCanvas));
    c->width = width;
    c->height = height;
    c->cells = (int*)calloc((size_t)(width * height), sizeof(int));
    c->userdata = NULL;
    c->callback = NULL;
    return c;
}

void geo_canvas_destroy(GeoCanvas* canvas)
{
    free(canvas->cells);
    free(canvas);
}

void geo_canvas_set(GeoCanvas* canvas, int x, int y, int value) { canvas->cells[y * canvas->width + x] = value; }
int geo_canvas_get(const GeoCanvas* canvas, int x, int y) { return canvas->cells[y * canvas->width + x]; }
void* geo_canvas_userdata(GeoCanvas* canvas) { return canvas->userdata; }
void geo_canvas_set_userdata(GeoCanvas* canvas, void* data) { canvas->userdata = data; }

int geo_printf(const char* format, ...) { return (int)strlen(format); }

int geo_apply(GeoCallback cb, int v) { return cb(v); }
int geo_apply_or(GeoCallback cb, int v, int fallback) { return cb ? cb(v) : fallback; }

int geo_count_if(const int* values, size_t count, GeoFilter filter)
{
    int n = 0;
    for (size_t i = 0; i < count; i++)
        if (filter(values[i]))
            n++;
    return n;
}

void geo_visit_points(GeoVisitor visitor, void* user)
{
    for (int i = 0; i < 3; i++)
    {
        GeoPoint p = {i, i * 10};
        visitor(&p, user);
    }
}

int8_t geo_apply_small(GeoSmall cb, int8_t v) { return cb(v); }
const char* geo_name_with(GeoNamer namer, GeoColor c) { return namer(c); }
int geo_ops_run(const GeoOps* ops, int v) { return ops->fn(v) + ops->base; }

static int doubler(int v) { return v * 2; }
GeoCallback geo_get_doubler(void) { return doubler; }

void geo_canvas_set_callback(GeoCanvas* canvas, GeoCallback cb) { canvas->callback = cb; }
int geo_canvas_fire(GeoCanvas* canvas, int v) { return canvas->callback ? canvas->callback(v) : -1; }
