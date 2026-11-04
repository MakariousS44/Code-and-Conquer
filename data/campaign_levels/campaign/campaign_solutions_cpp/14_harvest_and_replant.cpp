#include "robot.hpp"

void turn_right() {
    turn_left();
    turn_left();
    turn_left();
}

void balance_row() {
    bool gap_passed = false;
    for (int spot = 0; spot < 4; spot++) {
        // Every starting stack has two tokens, so leave one behind.
        if (object_here()) {
            pick_object();
        } else {
            put_object();
        }
        if (spot == 3) {
            break;
        }
        if (!gap_passed && wall_on_right()) {
            turn_left();
            move();
            turn_right();
            move();
            move();
            turn_right();
            move();
            turn_left();
            gap_passed = true;
        } else {
            move();
            move();
        }
    }
}

int main() {
    balance_row();
    turn_left();
    for (int step = 0; step < 3; step++) {
        move();
    }
    turn_left();

    balance_row();
    turn_left();
    for (int step = 0; step < 3; step++) {
        move();
    }
    return 0;
}
