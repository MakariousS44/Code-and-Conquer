#include "robot.hpp"

int main() {
    // Use a loop to reach the goal.
    for (int i {0}; i < 11; i++) {
        move();
    }

    return 0;
}