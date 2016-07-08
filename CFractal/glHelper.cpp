//
// A light weight open gl library built for cFractal.
//
// By Matthew Aitchison
// Date 2016/07/08 
//

#include "stdafx.h"
#include "glHelper.h"
#include "helper.h"

/*
 * Draws a test object.
 */
void drawTestObject()
{
	//  Draw Icosahedron
	glutWireIcosahedron();
}

/*
 * Sets up an orthographic projection with given width and height.
 */
void setOrtho(int width, int height)
{
	glLoadIdentity();
	gluOrtho2D(0, width, height, 0);	
}

/*
 * Draws a solid color block on the screen
 */
void drawRect(Vector2d topLeft, Vector2d bottomRight,  Color color)
{
	
	glColor3f(color.r / 255.0, color.g / 255.0, color.b / 255.0);
	glBegin(GL_TRIANGLES);
	glVertex3f(topLeft.x, topLeft.y, 0.0);
	glVertex3f(bottomRight.x, topLeft.y, 0.0);
	glVertex3f(bottomRight.x, bottomRight.y, 0.0);
	glVertex3f(bottomRight.x, bottomRight.y, 0.0);
	glVertex3f(topLeft.x, bottomRight.y, 0.0);
	glVertex3f(topLeft.x, topLeft.y, 0.0);
	glEnd();	
}
/*
 * Creates a texture from given data.
 * Data is just a 2d array of RGB.
 */
Texture createTexture(int width, int height, uint8_t *data)
{
	GLuint textureID;
	glGenTextures(1, &textureID);	
	glBindTexture(GL_TEXTURE_2D, textureID);
	glTexImage2D(GL_TEXTURE_2D, 0, 3, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, data);	

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	//gluBuild2DMipmaps(GL_TEXTURE_2D, 3, width, height, GL_RGB, GL_UNSIGNED_BYTE, data);

	auto error = glGetError();
	if (error) {
		TRACE("Upload error " + intToStr(error));
	}

	auto result = Texture();
	result.id = textureID;
	return result;
}

/*
 * Draws a texture on the screen
 */
void drawTexture(Vector2d topLeft, Vector2d bottomRight, Texture texture)
{
	glBindTexture(GL_TEXTURE_2D, texture.id);

	glEnable(GL_TEXTURE_2D);
	glBegin(GL_QUADS);

		glTexCoord2f(0.0, 0.0); glVertex3f(topLeft.x,		topLeft.y,		0.0);
		glTexCoord2f(1.0, 0.0); glVertex3f(bottomRight.x,	topLeft.y,		0.0);
		glTexCoord2f(1.0, 1.0); glVertex3f(bottomRight.x,	bottomRight.y,	0.0);
		glTexCoord2f(0.0, 1.0); glVertex3f(topLeft.x,		bottomRight.y,	0.0);
		
	glEnd();	

	auto error = glGetError();
	if (error) {
		TRACE("Draw error " + intToStr(error));
	}

}