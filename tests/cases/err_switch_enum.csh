// A switch over an enum without 'default:' must handle every member.
// expect-error: the switch over enum 'Direction' does not handle 'East', 'West'; add the cases or 'default:'

using System;

enum Direction : uint8 { North, East, South, West }

int Main()
{
    Direction d = Direction.East;
    switch (d)
    {
        case Direction.North:
        case Direction.South:
            return 1;
    }
    return 0;
}
