# the midi maestro 🐝
A fun little robot that will play tunes for us, still a work in progress :)

<img width="4032" height="1412" alt="image" src="https://github.com/user-attachments/assets/a90546d8-a796-4325-bb1d-b997ddcae225" />


Maestro is a custom built CNC-type robot with two "hands" that cover an entire 12 note octave. It operates as two esp32s3's cooperating in tandem to try playing MIDI files! A solver attempts to parse MIDI files into an instruction sequence of movements and key presses/depresses. 

The solver has *some* intelligence to it in that it will try to look a couple notes in the future to optimize hand placement, but I'm sure much more work can still be done to improve it.

The left hand solves the entire song, then works on instructions at certain timestamps. Instructions for the right hand are sent over a UART connection.

## Demos 

https://github.com/user-attachments/assets/6ee0a4c3-5925-4142-81c9-4707cb508cc3

v2 prototype playing a bit of Runaway


https://github.com/user-attachments/assets/58f6e1ac-3eb3-450a-81f4-9b57bdd086b1

Early proof of concept on solonoids
