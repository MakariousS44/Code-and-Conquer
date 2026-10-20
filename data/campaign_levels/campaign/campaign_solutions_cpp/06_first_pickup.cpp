#include "robot.hpp"

int main()
{
	for (int i {0}; i < 2; i++) {
        turn_left();
        
        // move 3 times
        move();
        move();
        move();
        
        // turn right
        turn_left();
        turn_left();
        turn_left();
        
        // move 3 times
        move();
        move();
        move();
    }
    
    // turn right
    turn_left();
    turn_left();
    turn_left();
        
    // move 2 times
    move();
    move();
    
    //pick_object(); //uncomment this line to pick it up
    
    // turn around
    turn_left();
    turn_left();
    
    // move 5 times
    move();
    move();
    move();
    move();
    move();
}
