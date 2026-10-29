#include "robot.hpp"

void walk(int steps) {
    for (int i = 0; i < steps; i++) {
        move();
    }
}

void turn_right() {
    turn_left();
    turn_left();
    turn_left();
}

int main() {
    // Reach the left stack through column 3, past the wall.
    turn_right();
    move();
    turn_left();
    walk(4);
    turn_left();
    move();
    while (object_here()) {
        pick_object();
    }

    // Cross the canal on row 4 and collect the right stack.
    turn_left();
    turn_left();
    move();
    turn_right();
    walk(2);
    turn_left();
    walk(5);
    turn_left();
    walk(2);
    while (object_here()) {
        pick_object();
    }

    turn_left();
    turn_left();
    walk(4);
    while (carries_object()) {
        put_object();
    }
    return 0;
}
