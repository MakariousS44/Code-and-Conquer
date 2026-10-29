#include "robot.hpp"

int main() {
    // Place a token on every other tile.
    put_object();
    for (int i {0}; i < 4; i++) {
        for (int i {0}; i < 2; i++) {
             move();
        }
        put_object();
    }

    return 0;
}