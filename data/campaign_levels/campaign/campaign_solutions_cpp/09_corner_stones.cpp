#include "robot.hpp"

// Walk one side of the room and leave a token on the corner.
void walk_side() {
    // Write the steps for ONE side here.
    put_object();
    for (int i {0}; i < 5; i++) {
        move();
    }
}

int main() {
    // Call walk_side() once for each side of the room.
    for (int i {0}; i < 4; i++) {
        walk_side();
        turn_left();
    }

    return 0;
}