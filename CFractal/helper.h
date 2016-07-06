#pragma once

#include <string>

using std::string;

// Location in 2d space.
struct Vector2d
{
public:
	double x;
	double y;

	Vector2d(double atX, double atY);
	Vector2d();
	~Vector2d();

	std::string toString();

	double Vector2d::length();
};

string floatToStr(double d);
string intToStr(int i);
void TRACE(string str);
void TRACE(double d);
void TRACE(int i);
void TRACE(float* ar);
void TRACE(int* ar);
BOOL DrawBitmap(HDC hDC, INT x, INT y, HBITMAP hBitmap, DWORD dwROP);
HBITMAP createDIB(HDC hdc, int width, int height);
void Assert(bool condition, string message);
double time();
void fillBitmap(HBITMAP bitmap, COLORREF color);
void drawRect(HBITMAP bitmap, Vector2d topLeft, Vector2d bottomRight, COLORREF color);

