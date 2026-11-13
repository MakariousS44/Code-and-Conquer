#include "robot.hpp"

void turn_right() {
    turn_left();
    turn_left();
    turn_left();
}

int main() {
    // Solve any maze: keep going until you reach the goal.
    while (!at_goal()) {
        // Add your maze-solving logic here.
        if (right_is_clear()) {
            turn_right();
            move();
        } else if (front_is_clear()) {
            move();
        } else {
            turn_left();
        }
    }
    return 0;
}