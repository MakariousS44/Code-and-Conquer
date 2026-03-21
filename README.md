# Code & Conquer
**A visual coding learning game built with Godot 4**  
*CSCI 4700 — Software Engineering | Pickaxe Productions*

---

## Table of Contents
1. [About the Project](#about-the-project)
3. [Getting Started](#getting-started)
4. [How to Play](#how-to-play)
5. [Available Commands](#available-commands)
6. [Contributing](#contributing)

---

## About the Project

Code & Conquer is an educational coding game where players write real code (C++ or Python) to control a robot navigating an isometric world. It is designed as a beginner-friendly, hands-on introduction to programming concepts like loops, conditionals, and functions — inspired by tools like Reeborg's World.

**Key features:**
- Built-in code editor with syntax highlighting (C++ and Python)
- Real-time robot simulation on an isometric grid
- Compile, validate, run, and step-by-step debug modes
- Levels defined by JSON files for easy customization
- Reeborg's World level format compatible

---

## Getting Started

### Prerequisites

Before you begin, ensure you have the following installed:

**Git** — [Download Git](https://git-scm.com/install/)

**Godot Engine** — Currently using Godot 4.6.1.
- [For Windows](https://godotengine.org/download/windows/)
- [For Linux](https://godotengine.org/download/linux/)
- [For MacOS](https://godotengine.org/download/macos/)

Godot is downloaded as an executable inside a zip file. To start Godot, unzip and run the executable.

**GCC (g++)** — Required to compile C++ student code at runtime.
- Windows: Install via [MinGW](https://www.mingw-w64.org/) or [MSYS2](https://www.msys2.org/)
- Linux/macOS: Usually pre-installed. Run `g++ --version` to verify.

**Python 3** — Required to run Python student code at runtime.
- [Download Python](https://www.python.org/downloads/)
- Run `python3 --version` to verify.

---

### Step 1: Clone the Repository

To get a local copy of the project, clone the repository using your terminal or a Git GUI.

1. Open your terminal (Command Prompt, PowerShell, or Terminal).
2. Navigate to the directory where you want to store the project.
3. Run the following command:

```bash
git clone https://github.com/MakariousS44/RobotGame.git
```

Once the download is complete, a new folder named after the project will be created.

---

### Step 2: Import the Project into Godot

Godot does not automatically detect new folders on your drive; you must manually point the Project Manager to the cloned directory.

1. Launch the Godot Engine.
2. In the Project Manager window, click the `Import Existing Project` button in the center or the `Import` button on the top-left.
3. Navigate into the folder you just cloned and look for the **project.godot** file.
   - Note: The project.godot file is the brain of the project. Godot cannot import a folder unless this file is present in the root.
4. Select the file, open, and import.

---

### Step 3: Run the Project

Press **F5** or click the **Play** button in the top-right of the Godot editor.

---

## How to Play

1. Write C++ or Python code in the **Editor** panel on the left. Use the language selector in the top-right to switch languages.
2. Click **Validate** to check for errors before running.
3. Click **Run** to compile and execute your code — watch the robot move!
4. Click **Step** to execute one command at a time for debugging.
5. Click **Reset** to reload the world and start over.

---

## Available Commands

These are the robot functions students can use. They work the same in both C++ and Python:

```cpp
move();           // Move the robot one tile forward
turn_left();      // Rotate the robot 90° to the left
turn_right();     // Rotate the robot 90° to the right
front_is_clear(); // Returns true if no wall is ahead
pick_object();    // Pick up an object on the current tile
put_object();     // Place an object on the current tile
```

**Example:**
```cpp
int main() {
    for (int i = 0; i < 4; i++) {
        move();
        move();
        move();
        turn_right();
    }
}
```

---

*Pickaxe Productions — MTSU CSCI 4700 Spring 2026*
