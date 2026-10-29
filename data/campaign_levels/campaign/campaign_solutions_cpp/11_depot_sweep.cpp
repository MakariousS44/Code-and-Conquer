#include "robot.hpp"

int main() {
    while (!at_goal()) {
        while (object_here()) {
            pick_object();
        }
        if (front_is_clear()) {
            move();
        } else {
            turn_left();
        }
    }
    while (carries_object()) {
        put_object();
    }
    return 0;
}
