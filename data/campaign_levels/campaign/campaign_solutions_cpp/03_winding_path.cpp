#include "robot.hpp"

int main() {
    // Find the gaps and reach the goal.
    move();
    move();
    move();
    move();
    turn_left();
    move();
    turn_left();
    move();
    move();
    move();
    move();
    
    // turn right
    turn_left();
    turn_left();
    turn_left();
    
    move();
    move();
    move();
    
    // turn right
    turn_left();
    turn_left();
    turn_left();
    
    move();
    move();
    move();
    move();
    
    return 0;
}