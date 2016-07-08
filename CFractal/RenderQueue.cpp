#include "stdafx.h"
#include "RenderQueue.h"
#include "helper.h"
#include <chrono>


// our render pipes.
RenderPipe pipe[4] = {};

// Returns point to free pipe, or null if no free pipes.
RenderPipe *getFreePipe()
{
	for (int i = 0; i < 4; i++)
	{
		if (pipe[i].job == NULL)
		{
			return &pipe[i];
		}
	}
	return NULL;
}

void threaded_processJob(RenderPipe *sourcePipe, MandelbrotSolver *solver)
{
	TRACE("Worker thread "+intToStr(sourcePipe->id)+" starting ");

	while (true)	
	{

		//TRACE(" -tick " + intToStr(sourcePipe->id));
		RenderBlock *block = sourcePipe->job;

		// Look for a job, if there is none then move on.
		if (!block || block->status != rsINQUE) {
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
			continue;
		}

		auto _block = solver->CreateBlock(block->offset.x, block->offset.y, (1.0 / block->scale) / 64.0);
		solver->Solve(_block);

		block->data = _block;

		block->status = rsRENDERED;

		//TRACE("Finished block" + sourcePipe->job->toString());
	}

	
}

void processJobList(RenderQueue *queue)
{	
	TRACE("Job distrubution thread started");

	while (true)
	{
		// get lock
		// todo: we need to get a lock on the queue as does the addJob function.
		// check for jobs

		if (queue->jobQueue.size() >= 1) 
		{
			auto selectedPipe = getFreePipe();
			if ((!selectedPipe))
				continue;

			TRACE("Processing job.");
			
			selectedPipe->job = queue->jobQueue.back();						

			queue->jobQueue.pop_back();
		}
		

		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
}

/*
 * Handles texture uploads for the render queue.  Looks like this has to be done in the main thread. 
 */
void RenderQueue::update()
{
	for (int i = 0; i < 4; i++)
	{
		if (pipe[i].job && pipe[i].job->status == rsRENDERED) 
		{
			RenderBlock *block = pipe[i].job;

			// Map colors
			auto colors = new uint8_t[64 * 64 * 3];
			for (int i = 0; i < 64 * 64 * 3; i++)
			{
				colors[i] = 255 - block->data.values_out[i / 3] * 256.0 / 2048.0;
			}

			// Upload
			TRACE("Upload " + block->toString());
			block->texture = createTexture(64, 64, colors);

			delete colors;

			block->status = rsUPLOADED;

			// clear pipe for another job.
			pipe[i].job = NULL;

			// limit to 1 upload per frame so that we just halt the program too long.
			return;
		}

	}
}

void RenderQueue::addJob(RenderBlock *block)
{	
	block->status = rsINQUE;

	//todo: need to get lock here.
	jobQueue.push_back(block);
	TRACE("Job enqued, total jobs " + intToStr(jobQueue.size()));
}

/*
 * Process a single job in the queue.
 */
void RenderQueue::processJob(RenderBlock *block)
{
	// OK, so just for new we will render on the spot :)	
	auto _block = solver.CreateBlock(block->offset.x, block->offset.y, (1.0 / block->scale) / 64.0);
	solver.Solve(_block);

	block->data = _block;

	block->status = rsRENDERED;

	// Map colors
	auto colors = new uint8_t[64 * 64 * 3];
	for (int i = 0; i < 64 * 64 * 3; i++)
	{
		colors[i] = 255 - block->data.values_out[i / 3] / 4;
	}

	// Upload
	TRACE("Upload " + block->toString());
	block->texture = createTexture(64, 64, colors);

	delete colors;

	block->status = rsUPLOADED;
}

// Create a render que.
RenderQueue::RenderQueue()
{
	solver = MandelbrotSolver();
	jobQueue = std::vector<RenderBlock*>();
	workThread = std::thread(processJobList, this);			

	// start the threads.
	for (int i = 0; i < 4; i++)
	{
		pipe[i].id = i + 1;
		pipe[i].thread = std::thread(threaded_processJob, &pipe[i], &solver);
	}
}

RenderQueue::~RenderQueue()
{
	workThread.join();	
}