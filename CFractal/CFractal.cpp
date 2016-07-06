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

#define MAX_LOADSTRING 100

using namespace std;

// Global Variables:
HINSTANCE hInst;                                // current instance
WCHAR szTitle[MAX_LOADSTRING];                  // The title bar text
WCHAR szWindowClass[MAX_LOADSTRING];            // the main window class name

// Forward declarations of functions included in this code module:
ATOM                MyRegisterClass(HINSTANCE hInstance);
BOOL                InitInstance(HINSTANCE, int);
LRESULT CALLBACK    WndProc(HWND, UINT, WPARAM, LPARAM);
INT_PTR CALLBACK    About(HWND, UINT, WPARAM, LPARAM);

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


// Inititialize our fractal
void setupFractal()
{
	TRACE("Initializing Fractal");
	solver = new MandelbrotSolver();

	viewport = Viewport();
	viewport.size = Vector2d(VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
	renderGrid = new RenderGrid(&viewport);
}
	

// Handle keyboard input such as wasd.
void handleKeyboardInput()
{
	double speed = elapsed;

	if (GetAsyncKeyState('W')) {
		viewport.offset.y -= 1/viewport.scale * 100 * speed;
		dirty = true;
	}
		
	if (GetAsyncKeyState('S')) {
		viewport.offset.y += 1/viewport.scale * 100 * speed;
		dirty = true;
	}
	if (GetAsyncKeyState('A')) {
		viewport.offset.x -= 1/viewport.scale * 100 * speed;
		dirty = true;
	}
	if (GetAsyncKeyState('D')) {
		viewport.offset.x += 1/viewport.scale * 100 * speed;
		dirty = true;
	}	
	if (GetAsyncKeyState('Q')) {
		viewport.scale *= 1.1;
		//TRACE(viewport.scale);
		dirty = true;
	}

	if (GetAsyncKeyState('E')) {
		viewport.scale *= 0.9;
		dirty = true;
	}
		
}

void update()
{
	static double lastTime = time();
	elapsed = time() - lastTime;
	lastTime = time();
	ticker++;	
	handleKeyboardInput();
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance,
                     _In_opt_ HINSTANCE hPrevInstance,
                     _In_ LPWSTR    lpCmdLine,
                     _In_ int       nCmdShow)
{
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);

    // TODO: Place code here.

	setupFractal();
	
    // Initialize global strings
    LoadStringW(hInstance, IDS_APP_TITLE, szTitle, MAX_LOADSTRING);
    LoadStringW(hInstance, IDC_CFRACTAL, szWindowClass, MAX_LOADSTRING);
    MyRegisterClass(hInstance);

    // Perform application initialization:
    if (!InitInstance (hInstance, nCmdShow))
    {
        return FALSE;
    }

    HACCEL hAccelTable = LoadAccelerators(hInstance, MAKEINTRESOURCE(IDC_CFRACTAL));

    MSG msg;

    // Main message loop:
    while (GetMessage(&msg, nullptr, 0, 0))
    {
		update();
		InvalidateRect(msg.hwnd, NULL, NULL);
        if (!TranslateAccelerator(msg.hwnd, hAccelTable, &msg))
        {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
    }

    return (int) msg.wParam;
}



//
//  FUNCTION: MyRegisterClass()
//
//  PURPOSE: Registers the window class.
//
ATOM MyRegisterClass(HINSTANCE hInstance)
{
    WNDCLASSEXW wcex;

    wcex.cbSize = sizeof(WNDCLASSEX);

    wcex.style          = CS_HREDRAW | CS_VREDRAW;
    wcex.lpfnWndProc    = WndProc;
    wcex.cbClsExtra     = 0;
    wcex.cbWndExtra     = 0;
    wcex.hInstance      = hInstance;
    wcex.hIcon          = LoadIcon(hInstance, MAKEINTRESOURCE(IDI_CFRACTAL));
    wcex.hCursor        = LoadCursor(nullptr, IDC_ARROW);
    wcex.hbrBackground  = (HBRUSH)(COLOR_WINDOW+1);
    wcex.lpszMenuName   = MAKEINTRESOURCEW(IDC_CFRACTAL);
    wcex.lpszClassName  = szWindowClass;
    wcex.hIconSm        = LoadIcon(wcex.hInstance, MAKEINTRESOURCE(IDI_SMALL));

    return RegisterClassExW(&wcex);
}

//
//   FUNCTION: InitInstance(HINSTANCE, int)
//
//   PURPOSE: Saves instance handle and creates main window
//
//   COMMENTS:
//
//        In this function, we save the instance handle in a global variable and
//        create and display the main program window.
//
BOOL InitInstance(HINSTANCE hInstance, int nCmdShow)
{
   hInst = hInstance; // Store instance handle in our global variable

   HWND hWnd = CreateWindowW(szWindowClass, szTitle, WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, 0, CW_USEDEFAULT, 0, nullptr, nullptr, hInstance, nullptr);

   if (!hWnd)
   {
      return FALSE;
   }

   ShowWindow(hWnd, nCmdShow);
   UpdateWindow(hWnd);

   return TRUE;
}


// Draws block to bitmap at given location.
void drawBlock(HBITMAP destination, int atX, int atY, FractalBlock block, bool debug = false)
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

// Draws fractal grid to a DIB then to device context.
void renderFractalGrid(HBITMAP destination, RenderGrid *grid)
{
	drawRect(destination, Vector2d(0,0), Vector2d(VIEWPORT_WIDTH, VIEWPORT_HEIGHT), RGB(0, 0, 0));

	int layer = (int)log2(viewport.scale);
	TRACE("LAYER:" + intToStr(layer));
	double startTime;

	startTime = time();
	renderGrid->prepare(layer + 1);
	TRACE("Took " + floatToStr(time() - startTime) + " seconds to prep."+"["+intToStr(ticker)+"]");

	renderGrid->targetDepth = layer;

	startTime = time();
	renderGrid->root->recursiveDraw();
	TRACE("Took " + floatToStr(time() - startTime) + " seconds to draw." + "[" + intToStr(ticker) + "]");

	/*
	
	// figure out what level we are at
	
	int layer = (int)1;
	int layerSize = (int)std::pow(2, layer);

	// make sure our fractal is all upto date.
	renderGrid->prepare(layer + 1);

	for (int blockY = 0; blockY < 8; blockY++) {
		for (int blockX = 0; blockX < 8; blockX++) {
			// fetch the block
			auto location = Vector2d((blockX - (layerSize / 2)) / (float)layerSize * 4, (blockY - (layerSize / 2)) / (float)layerSize * 4);
			
			auto block = grid->getBlock(location, layer + 1);
			if (block->getStatus() == rsRENDERED) {
				FractalBlock data = block->data;
				viewport.scale *= 32;
				auto draw = viewport.toScreen(location);
				viewport.scale /= 32;
				//TRACE(location.toString());
				drawBlock(destination, draw.x, draw.y, data, true);
			}
		}
	}

	*/

	/*
	// draw all blocks
	int layer = 4;
	int layerSize = (int)std::pow(2,layer);

	// make sure our fractal is all upto date.
	renderGrid->prepare(layer+1);

	for (int blockY = 0; blockY < layerSize; blockY++) {
		for (int blockX = 0; blockX < layerSize; blockX++) {
			// fetch the block
			auto location = Vector2d((blockX - (layerSize / 2))/(float)layerSize*4, (blockY - (layerSize / 2))/(float)layerSize*4);
			TRACE(location.toString());
			auto block = grid.getBlock(location, layer + 1);
			if (block->getStatus() == rsRENDERED) {
				FractalBlock data = block->data;
				drawBlock(destination, blockX * 64, blockY * 64, data, true);
			}
		}
	}
	*/
}

// Renders fractal, if _hdc is supplied will be draw periodically to that device context.
void renderFractal(HBITMAP destination, MandelbrotSolver solver, HDC _hdc = NULL)
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



//
//  FUNCTION: WndProc(HWND, UINT, WPARAM, LPARAM)
//
//  PURPOSE:  Processes messages for the main window.
//
//  WM_COMMAND  - process the application menu
//  WM_PAINT    - Paint the main window
//  WM_DESTROY  - post a quit message and return
//
//
LRESULT CALLBACK WndProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message)
    {
    case WM_COMMAND:
        {
            int wmId = LOWORD(wParam);
            // Parse the menu selections:
            switch (wmId)
            {
            case IDM_ABOUT:
                DialogBox(hInst, MAKEINTRESOURCE(IDD_ABOUTBOX), hWnd, About);
                break;
            case IDM_EXIT:
                DestroyWindow(hWnd);
                break;
            default:
                return DefWindowProc(hWnd, message, wParam, lParam);
            }
        }
        break;
    case WM_PAINT:
        {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hWnd, &ps);

			if (page == NULL) {
				page = createDIB(hdc, VIEWPORT_WIDTH, VIEWPORT_HEIGHT);
				viewport.target = page;
			}

			if (solver != NULL && dirty) 
			{				
				renderFractalGrid(page, renderGrid);
				dirty = FALSE;
			}

			DrawBitmap(hdc, 5, 5, page, SRCCOPY);
			
            EndPaint(hWnd, &ps);
        }
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProc(hWnd, message, wParam, lParam);
    }
    return 0;
}

// Message handler for about box.
INT_PTR CALLBACK About(HWND hDlg, UINT message, WPARAM wParam, LPARAM lParam)
{
    UNREFERENCED_PARAMETER(lParam);
    switch (message)
    {
    case WM_INITDIALOG:
        return (INT_PTR)TRUE;

    case WM_COMMAND:
        if (LOWORD(wParam) == IDOK || LOWORD(wParam) == IDCANCEL)
        {
            EndDialog(hDlg, LOWORD(wParam));
            return (INT_PTR)TRUE;
        }
        break;
    }
    return (INT_PTR)FALSE;
}
