#include "robot.hpp"

int main()
{
    for (int i {0}; i < 9; i++) {
        move();
        turn_left();
        move();
        
        // turn right
        turn_left();
        turn_left();
        turn_left();
    }
    
	return 0;
}
