# Circular Pong (Godot 4.3)

A minimalist, procedurally drawn, circular take on the classic game of Pong, built entirely within Godot 4.3 using a completely programmatic approach.

## How It Works

Instead of the traditional left-to-right setup, this game takes place inside a circular arena. The ball spawns at the center and moves outwards. As the player, you control a curved paddle that moves along the outer perimeter of the arena.

The entire game logic and rendering is handled within a single `main.gd` script attached to a `Node2D`. The game doesn't use any visual sprites or external assets. Everything is rendered dynamically each frame using Godot's `_draw()` functions:
- A black void background.
- A white circular boundary defining the arena.
- A red ball that gradually increases in speed with each hit. Small bounce variance is added upon hitting the paddle to prevent repetitive loops.
- A neon green paddle arc that defends the perimeter.
- Breakable yellow rounded square blocks that spawn inside the arena.

### Block Mechanics
As you score, yellow blocks will appear in the arena based on score probabilities (starting after a score of 2, with chances for single or double spawns). 
Blocks have three states:
1. **Spawning**: Blocks blink rapidly when they first appear.
2. **Normal**: Blocks can bounce the ball. On the first hit, they crack.
3. **Disintegrating**: On the second hit, blocks expand and fade out.

## Controls

* **Mouse Scroll Up / Down**: Move the paddle counter-clockwise and clockwise along the circular arena.
* **Mac Trackpad**: Enhanced horizontal and vertical scrolling mapping allows smooth, momentum-based paddle control.
* **Space / Enter**: Pause or resume the game. (Note: if you miss the ball, the game restarts automatically).

## Running the Game

1. Open **Godot 4.3**.
2. Select **Import** and navigate to this project folder (`pong_circle`).
3. Open the `project.godot` file.
4. Press **F5** (or the Play button in the top right corner of the editor) to run the game. The `main.tscn` scene is already configured as the main run scene.

## Directory Structure

* `main.gd` - The core script containing all game logic, collision detection, and procedural rendering.
* `main.tscn` - The root Node2D scene housing the `main.gd` script.
* `project.godot` - The standard Godot engine project configuration file.
