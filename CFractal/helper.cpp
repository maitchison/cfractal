#include "stdafx.h"
#include "helper.h"
#include <ctime>

string floatToStr(double d)
{
	char buffer[50];
	sprintf_s(buffer, "%f", d);
	return buffer;
}

string intToStr(int i)
{
	char buffer[50];
	sprintf_s(buffer, "%d", i);
	return buffer;
}

void TRACE(string str)
{
	str = str + "\n";
	std::wstring stemp = std::wstring(str.begin(), str.end());
	LPCWSTR sw = stemp.c_str();
	OutputDebugString(sw);
}

void TRACE(double d)
{
	TRACE(floatToStr(d));
}

void TRACE(int i)
{
	char buffer[50];
	sprintf_s(buffer, "%d", i);
	TRACE(buffer);
}

void TRACE(float* ar)
{
	int n = 64;
	string str;
	for (int i = 0; i < n; i++) {
		str += floatToStr(ar[i]) + " ";
	}
	TRACE("[" + str + "]");
}

void TRACE(int* ar)
{
	int n = 64 * 64;
	string str;
	for (int i = 0; i < n; i++) {
		str += intToStr(ar[i]) + " ";
	}
	TRACE("[" + str + "]");
}

/******************************************************************************
*                                                                            *
*  FUNCTION   : DrawBitmap(HDC hDC, int x, int y,                            *
*                          HBITMAP hBitmap, DWORD dwROP)                     *
*                                                                            *
*  PURPOSE    : Draws bitmap <hBitmap> at the specified position in DC <hDC> *
*                                                                            *
*  RETURNS    : Return value of BitBlt()                                     *
*                                                                            *
*****************************************************************************/
BOOL DrawBitmap(HDC hDC, INT x, INT y, HBITMAP hBitmap, DWORD dwROP)
{
	HDC       hDCBits;
	BITMAP    Bitmap;
	BOOL      bResult;

	if (!hDC || !hBitmap)
		return FALSE;

	hDCBits = CreateCompatibleDC(hDC);
	GetObject(hBitmap, sizeof(BITMAP), (LPSTR)&Bitmap);
	SelectObject(hDCBits, hBitmap);
	bResult = BitBlt(hDC, x, y, Bitmap.bmWidth, Bitmap.bmHeight, hDCBits, 0, 0, dwROP);
	DeleteDC(hDCBits);

	return bResult;
}


// Creates and returns a device independant bitmap to be used for drawing.
HBITMAP createDIB(HDC hdc, int width, int height)
{
	return CreateCompatibleBitmap(hdc, width, height);
}

void Assert(bool condition, string message)
{
	if (!(condition)) {
		TRACE("ASSERTION FAILURE: "+message);
		exit(1);
	}
}

// draws rectangle to bitmap with given color.
void drawRect(HBITMAP bitmap, Vector2d topLeft, Vector2d bottomRight, COLORREF color)
{
	HDC hDC = CreateCompatibleDC(NULL);
	SelectObject(hDC, bitmap);

	auto brush = CreateSolidBrush(color);
	auto pen = CreatePen(PS_SOLID, 1, color);

	SelectObject(hDC, brush);
	SelectObject(hDC, pen);
	Rectangle(hDC, (int)topLeft.x, (int)topLeft.y, (int)bottomRight.x, (int)bottomRight.y);
	DeleteObject(brush);
	DeleteObject(pen);

	DeleteDC(hDC);
}


// Fills bitmap with given color.
void fillBitmap(HBITMAP bitmap, COLORREF color)
{
	HDC hDC = CreateCompatibleDC(NULL);
	SelectObject(hDC, bitmap);

	auto brush = CreateSolidBrush(color);

	SelectObject(hDC, brush);
	Rectangle(hDC, 0, 0, 640, 640);
	DeleteObject(brush);

	DeleteDC(hDC);
}

// Returns clock time in seconds.
double time() 
{
	using namespace std;
	return (double)clock() / CLOCKS_PER_SEC;
}

///  ------------------------------------------------------------------
///  Vector2d
///  ------------------------------------------------------------------

// Initialize the 2d vector with given co-ords.
Vector2d::Vector2d(double atX, double atY)
{
	x = atX;
	y = atY;
}

// Initialize the 2d vector to (0,0)
Vector2d::Vector2d()
{
	x = 0;
	y = 0;
}


// Destroy the vector.
Vector2d::~Vector2d()
{
}

std::string Vector2d::toString()
{
	return floatToStr(x) + ", " + floatToStr(y);
}

// Returns length of vector.
double Vector2d::length()
{
	return sqrt(x*x + y*y);
}
