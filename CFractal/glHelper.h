#pragma once

#include "helper.h"
#include <gl/freeglut.h>

struct Texture
{
	UINT id;
};

void drawTestObject();
void drawRect(Vector2d topLeft, Vector2d bottomRight,  Color color);
Texture createTexture(int width, int height, uint8_t * data);
void drawTexture(Vector2d topLeft, Vector2d bottomRight, Texture texture);
void setOrtho(int width, int height);