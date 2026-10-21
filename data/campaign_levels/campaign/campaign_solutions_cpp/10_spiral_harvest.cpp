#include "robot.hpp"

int main() {
    // Collect every token, then drop them all on the goal.
    
    while (!at_goal()) {    // Repeat until at goal:
        if (object_here) {
            pick_object();  // If object on the tile, pick it up
        }
        if (front_is_clear()) {
            move(); // If front is clear, move forward
        } else {
            turn_left();    // If front not clear, turn left
        }
    }
    
    // Reached goal tile, now need to place all the carried objects
    while (carries_object()) {
        put_object();   // Place object until no longer carrying anything
    }
    
    return 0;
}