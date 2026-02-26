# RobotGame
Robot Coding Game for Software Engineering class - CSCI 4700  
## Table of Contents
1. something
2. something else
3. [Starting the Godot Project](#Starting-the-Godot-Project)

## Starting the Godot Project
### Prerequisites
Before you begin, ensure you have the following installed:

**Git**: [Download Git](https://git-scm.com/install/)

**Godot Engine**: Currently using Godot 4.6.1. 
- [For Windows](https://godotengine.org/download/windows/)
- [For Linux](https://godotengine.org/download/linux/)
- [For MacOS](https://godotengine.org/download/macos/)

Godot is downloaded as an executable inside a zip file. To just start Godot, unzip the executable.

### Step 1: Clone the Repository
To get a local copy of the project, clone the repository using your terminal or a Git GUI.

1. Open your terminal (Command Prompt, PowerShell, or Terminal).
2. Navigate to the directory where you want to store the project.
3. Run the following command:
   ```bash
   git clone https://github.com/MakariousS44/RobotGame.git
   ```
Once the download is complete, a new folder named after the project will be created.

### Step 2: Import the Project into Godot
Godot does not automatically detect new folders on your drive; you must manually point the Project Manager to the cloned directory.

1. Launch the Godot Engine.
2. In the Project Manager window, click the ```Import Existing Project``` button in the center or the ```Import``` button on the top-left.
3. Navigate into the folder you just cloned and look for the **project.godot** file.
  - Note: The project.godot file is the brain of the project. Godot cannot import a folder unless this file is present in the root.
4. Select the file, open, and import
