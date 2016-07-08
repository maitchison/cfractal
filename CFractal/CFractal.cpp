// CFractal.cpp : Defines the entry point for the application.
//

#include "stdafx.h"
#include "CFractal.h"
#include <stdio.h>
#include <string>
#include "Mandel.h"
#include <ctime>
#include "helper.h"
#include "RenderGrid.h"
#include "Windows.h"
#include "Winuser.h"
#include "glHelper.h"
#include <gl/freeglut.h>
#include <chrono>
#include <thread>

#define MAX_LOADSTRING 100

using namespace std;

MandelbrotSolver *solver = NULL;

RenderGrid *renderGrid = NULL;

int ticker = 0;

double elapsed = 0;

// Page to draw fractal onto.
HBITMAP page = NULL;

Viewport viewport;

bool dirty = true;

int VIEWPORT_WIDTH = 1440;
int VIEWPORT_HEIGHT = 1024;


void init();
void display(void);
void centerOnScreen();

//  define the window position on screen
int window_x;
int window_y;

//  variables representing the window size
int window_width = 1024;
int window_height = 768;

//  variable representing the window title
char *window_title = "Sample OpenGL FreeGlut App";

void drawFractalGrid();
void handleKeyboardInput(unsigned char key, int x, int y);
void update();

//-------------------------------------------------------------------------
//  Set OpenGL program initial state.
//-------------------------------------------------------------------------
void init()
{
	//  Set the frame buffer clear color to black. 
	glClearColor(0.0, 0.0, 0.0, 0.0);

	viewport = Viewport();
	viewport.size = Vector2d(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
	setOrtho(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
	renderGrid = new RenderGrid(&viewport);

	solver = new MandelbrotSolver();

	TRACE("OpenGL initialized to " + intToStr(VIEWPORT_WIDTH) + "x" + intToStr(VIEWPORT_WIDTH));
}

//-------------------------------------------------------------------------
//  Program Main method.
//-------------------------------------------------------------------------
void main(int argc, char **argv)
{
	TRACE("Initializing cFractal");
	//  Connect to the windowing system + create a window
	//  with the specified dimensions and position
	//  + set the display mode + specify the window title.
	glutInit(&argc, argv);
	centerOnScreen();
	glutInitWindowSize(window_width, window_height);
	glutInitWindowPosition(window_x, window_y);
	glutInitDisplayMode(GLUT_RGBA | GLUT_DOUBLE);
	glutCreateWindow(window_title);

	//  Set OpenGL program initial state.
	init();

	// Set the callback functions
	glutDisplayFunc(display);

	// Set input callback function
	glutKeyboardFunc(handleKeyboardInput);

	//  Start GLUT event processing loop
	glutMainLoop();
}



//-------------------------------------------------------------------------
//  This function is passed to glutDisplayFunc in order to display 
//  OpenGL contents on the window.
//-------------------------------------------------------------------------
void display(void)
{
	// Clear the window or more specifically the frame buffer...
	// This happens by replacing all the contents of the frame
	// buffer by the clear color (black in our case)
	glClear(GL_COLOR_BUFFER_BIT);	

	update();

	drawFractalGrid();

	// Swap contents of backward and forward frame buffers.
	glutSwapBuffers();

	// Request the next frame.
	glutPostRedisplay();

	// Wait a little while
	std::this_thread::sleep_for(std::chrono::milliseconds(1));
}


//-------------------------------------------------------------------------
//  This function sets the window x and y coordinates
//  such that the window becomes centered
//-------------------------------------------------------------------------
void centerOnScreen()
{
	window_x = (glutGet(GLUT_SCREEN_WIDTH) - window_width) / 2;
	window_y = (glutGet(GLUT_SCREEN_HEIGHT) - window_height) / 2;
}
	

/*
 * Draws the fractal grid using openGL.
 */
void drawFractalGrid()
{
	//drawRect(destination, Vector2d(0, 0), Vector2d(VIEWPORT_WIDTH, VIEWPORT_HEIGHT), RGB(0, 0, 0));

	int layer = (int)log2(viewport.scale);
	double startTime;

	startTime = time();
	renderGrid->prepare(layer + 1);
	//TRACE("Took " + floatToStr(time() - startTime) + " seconds to prep." + "[" + intToStr(ticker) + "]");

	renderGrid->targetDepth = layer;

	startTime = time();
	renderGrid->root->recursiveDraw();
	//TRACE("Took " + floatToStr(time() - startTime) + " seconds to draw." + "[" + intToStr(ticker) + "]");

}


// Handle keyboard input such as wasd.
void handleKeyboardInput(unsigned char key, int x, int y)
{
	double speed = elapsed * 10;

	TRACE("Input");

	switch (key) {
	case 'w': viewport.offset.y -= 1.0 / viewport.scale * 100 * speed;
		break;
	case 's': viewport.offset.y += 1.0 / viewport.scale * 100 * speed;
		break;
	case 'a': viewport.offset.x -= 1.0 / viewport.scale * 100 * speed;
		break;
	case 'd': viewport.offset.x += 1.0 / viewport.scale * 100 * speed;
		break;
	case 'q': viewport.scale *= 1.1;
		break;
	case 'e': viewport.scale /= 1.1;
	}		
}

void update()
{
	static double lastTime = time();
	elapsed = time() - lastTime;
	lastTime = time();
	ticker++;		
}


// Draws block to bitmap at given location.
void __drawBlock(HBITMAP destination, int atX, int atY, FractalBlock block, bool debug = false)
{
	HDC newdc = CreateCompatibleDC(NULL);
	SelectObject(newdc, destination);

	// this is quite slow, some kind of blit would be much faster
	COLORREF color = RGB(255, 0, 0);
	for (int ylp = 0; ylp < 64; ylp++)
	{
		for (int xlp = 0; xlp < 64; xlp++)
		{
			int it = block.values_out[xlp + ylp * 64];
			color = RGB(it / 4, it / 4, 128);

			if (debug && ((xlp == 0) || (ylp == 0)))
				color = RGB(255, 0, 0);

			SetPixel(newdc, atX + xlp, atY + ylp, color);
		}
	}

	DeleteDC(newdc);
}


// Renders fractal, if _hdc is supplied will be draw periodically to that device context.
void __renderFractal(HBITMAP destination, MandelbrotSolver solver, HDC _hdc = NULL)
{
	
	TRACE("Render command");

	HDC newdc = CreateCompatibleDC(NULL);
	SelectObject(newdc, destination);

	// go through rendering the blocks and drawing them to the screeen.

	using namespace std;
	clock_t begin = clock();

	for (int blockY = 0; blockY < 30; blockY++) {
		for (int blockX = 0; blockX < 30; blockX++) {

			float scale = 0.5f / 64.0f / 10.0f;
			float atX = blockX * 64.0f * scale - 1.5f;
			float atY = blockY * 64.0f * scale - 1.0f;
			

			FractalBlock block = solver.CreateBlock(atX, atY, scale);
			solver.Solve(block);

			// this is quite slow, some kind of blit would be much faster
			COLORREF color = RGB(255, 0, 0);
			for (int ylp = 0; ylp < 64; ylp++)
			{
				for (int xlp = 0; xlp < 64; xlp++)
				{
					int it = block.values_out[xlp + ylp * 64];
					color = RGB(it / 4, it / 4, it / 4);

					SetPixel(newdc, blockX * 64 + xlp, blockY * 64 + ylp, color);
				}
			}

		}

		if (_hdc != NULL)
		{
			// release the lock so we can draw, then get the lock back again.
			DeleteDC(newdc);
			DrawBitmap(_hdc, 5, 5, destination, SRCCOPY);
			newdc = CreateCompatibleDC(NULL);
			SelectObject(newdc, destination);

		}

		
	}	

	DeleteDC(newdc);

	clock_t end = clock();
	double elapsed_secs = double(end - begin) / CLOCKS_PER_SEC;
	TRACE(elapsed_secs);
	
}