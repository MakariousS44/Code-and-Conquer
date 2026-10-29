#include "robot.hpp"

int main() {
    // Follow the corridor, turn, then reach the goal.
    move();
    move();
    move();
    move();
    turn_left();
    move();
    move();
    move();
    move();

    return 0;
}