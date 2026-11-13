#include "robot.hpp"

void turn_right() {
    turn_left();
    turn_left();
    turn_left();
}

void plant_row() {
    put_object();
    while (front_is_clear()) {
        if (wall_on_right()) {
            turn_left();
            move();
            turn_right();
            move();
            move();
            turn_right();
            move();
            turn_left();
        } else {
            move();
            move();
        }
        put_object();
    }
}

int main() {
    plant_row();
    turn_left();
    for (int step = 0; step < 3; step++) {
        move();
    }
    turn_left();

    plant_row();
    turn_right();
    for (int step = 0; step < 3; step++) {
        move();
    }
    turn_right();
    plant_row();
    return 0;
}
