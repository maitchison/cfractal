#pragma once

#include "Mandel.h"
#include "RenderBlock.h"
#include <vector>
#include <thread>

struct RenderPipe
{
	int id;
	RenderBlock *job;
	std::thread thread;
};

class RenderQueue
{
private:
	
	std::thread workThread;

public:
	// how do I make these private and have a seperate thread excute?
	MandelbrotSolver solver;
	std::vector<RenderBlock*> jobQueue;
	void processJob(RenderBlock *block);

	void process();

	void update();

	void addJob(RenderBlock *job);
	RenderQueue();
	~RenderQueue();
};
