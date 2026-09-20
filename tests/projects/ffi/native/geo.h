#ifndef GEO_H
#define GEO_H

#include <stddef.h>
#include <stdint.h>

#define GEO_VERSION 3
#define GEO_NAME "geo"
#define GEO_PI 3.14159
#define GEO_FLAG_A 0x01
#define GEO_FLAG_B (GEO_FLAG_A << 1)

typedef enum GeoColor
{
    GEO_RED,
    GEO_GREEN = 5,
    GEO_BLUE
} GeoColor;

typedef struct GeoPoint
{
    int x;
    int y;
} GeoPoint;

typedef struct GeoRect
{
    GeoPoint min;
    GeoPoint max;
    double weight;
} GeoRect;

typedef struct GeoVec
{
    double x, y;
} GeoVec;

typedef struct GeoCanvas GeoCanvas; /* opaque */

/* plain values */
int geo_add(int a, int b);
unsigned int geo_umax(unsigned int a, unsigned int b);
long geo_mul_long(long a, long b);
size_t geo_strlen(const char* s);
double geo_hypot(double x, double y);
uint8_t geo_low_byte(uint32_t v);
_Bool geo_is_even(int v);

/* strings */
const char* geo_color_name(GeoColor c);
int geo_count_char(const char* s, char c);
void geo_upper(char* buffer, size_t size);

/* pointers */
void geo_swap(int* a, int* b);
int geo_sum(const int* values, size_t count);
int geo_divmod(int a, int b, int* quotient, int* remainder);
void geo_point_move(GeoPoint* p, int dx, int dy);
int geo_point_dist2(const GeoPoint* a, const GeoPoint* b);
int geo_optional(const GeoPoint* p); /* accepts NULL */

/* structs by value: need a shim */
GeoPoint geo_point_make(int x, int y);
GeoPoint geo_point_add(GeoPoint a, GeoPoint b);
GeoRect geo_rect_make(GeoPoint min, GeoPoint max, double weight);
int geo_rect_area(GeoRect r);
GeoVec geo_vec_scale(GeoVec v, double f);

/* opaque handle and void* */
GeoCanvas* geo_canvas_create(int width, int height);
void geo_canvas_destroy(GeoCanvas* canvas);
void geo_canvas_set(GeoCanvas* canvas, int x, int y, int value);
int geo_canvas_get(const GeoCanvas* canvas, int x, int y);
void* geo_canvas_userdata(GeoCanvas* canvas);
void geo_canvas_set_userdata(GeoCanvas* canvas, void* data);

/* variadic functions are declared */
int geo_printf(const char* format, ...);

/* callbacks: C function pointers are Action/Func types in CShift */
typedef int (*GeoCallback)(int);
typedef _Bool (*GeoFilter)(int value);
typedef void (*GeoVisitor)(const GeoPoint* p, void* user);
typedef int8_t (*GeoSmall)(int8_t v);
typedef const char* (*GeoNamer)(GeoColor c);

typedef struct GeoOps
{
    GeoCallback fn;
    int base;
} GeoOps;

int geo_apply(GeoCallback cb, int v);
int geo_apply_or(GeoCallback cb, int v, int fallback); /* cb may be NULL */
int geo_count_if(const int* values, size_t count, GeoFilter filter);
void geo_visit_points(GeoVisitor visitor, void* user);
int8_t geo_apply_small(GeoSmall cb, int8_t v);
const char* geo_name_with(GeoNamer namer, GeoColor c);
int geo_ops_run(const GeoOps* ops, int v);
GeoCallback geo_get_doubler(void); /* returns a C function */
void geo_canvas_set_callback(GeoCanvas* canvas, GeoCallback cb);
int geo_canvas_fire(GeoCanvas* canvas, int v);

#endif
