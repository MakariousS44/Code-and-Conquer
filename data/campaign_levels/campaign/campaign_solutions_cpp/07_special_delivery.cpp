#include "robot.hpp"

int main() {
    // Pick up the token, carry it to the goal, and put it down.
    move();
    move();
    pick_object();
    move();
    move();
    move();
    turn_left();
    move();
    move();
    move();
    // put_object();

    return 0;
}