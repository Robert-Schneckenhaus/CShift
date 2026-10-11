// 4x4 matrices for the camera and the cube's rotation, stored the way OpenGL expects them: column-major, element
// (row, column) at M[column * 4 + row].

struct Mat4
{
    float[] M;

    static Mat4 Identity()
    {
        var m = Mat4 { M = new float[16] };
        m.M[0] = 1;
        m.M[5] = 1;
        m.M[10] = 1;
        m.M[15] = 1;
        return m;
    }

    // this * other: applies `other` first, then `this`.
    Mat4 Multiply(Mat4 other)
    {
        var r = Mat4 { M = new float[16] };
        for (var col = 0; col < 4; col += 1)
        {
            for (var row = 0; row < 4; row += 1)
            {
                float sum = 0;
                for (var k = 0; k < 4; k += 1)
                    sum += M[k * 4 + row] * other.M[col * 4 + k];
                r.M[col * 4 + row] = sum;
            }
        }
        return r;
    }

    static Mat4 Translation(float x, float y, float z)
    {
        var m = Identity();
        m.M[12] = x;
        m.M[13] = y;
        m.M[14] = z;
        return m;
    }

    static Mat4 RotationX(double angle)
    {
        var m = Identity();
        float c = (float)Math.Cos(angle);
        float s = (float)Math.Sin(angle);
        m.M[5] = c;
        m.M[6] = s;
        m.M[9] = -s;
        m.M[10] = c;
        return m;
    }

    static Mat4 RotationY(double angle)
    {
        var m = Identity();
        float c = (float)Math.Cos(angle);
        float s = (float)Math.Sin(angle);
        m.M[0] = c;
        m.M[2] = -s;
        m.M[8] = s;
        m.M[10] = c;
        return m;
    }

    // Like gluPerspective: vertical field of view in radians, looking down -Z.
    static Mat4 Perspective(double fovY, double aspect, double near, double far)
    {
        var m = Mat4 { M = new float[16] };
        double f = 1.0 / Math.Tan(fovY / 2);
        m.M[0] = (float)(f / aspect);
        m.M[5] = (float)f;
        m.M[10] = (float)((far + near) / (near - far));
        m.M[11] = -1;
        m.M[14] = (float)(2 * far * near / (near - far));
        return m;
    }
}
