unit uFractal;

(*
*********************************************************************
 renders various fractal paterns to a graphical page (potentialy an openGL surface)}
*********************************************************************
 V1.0   (??)
    Basic functionality
 V1.01  (14/09/2006)
    Re-enabled support for 3dNow
    Created option to force 3DN/SSE/SSE2 not to be used
    We now log render method used when tFractal.updateRendmethod is called

*********************************************************************
*)

interface

uses
	math,
	uDebug,
	uStrings,
	uColors,
    uVector2d,
	openGL,
    dglOPenGL,
	uPageGLhw,
	uTypes,
	sysUtils,
    uPage;


CONST
	{anti aliasing methods}
    amNone = 0;
    amAdaptive = 1;
    amFixed = 2;

CONST
	pixelsAtAtime = 32; {number of pixels to process at a time}
    USE_ALPHA_MASK = false; {if true edge pixels are transperient}

TYPE
	tFractal = class;

    tOctFloat = array[0..7] of float;
    tQuadExtended = array[0..3] of extended;

	getValueMpProc = function (packedDataPtr: pointer): integer; register;

    tColorMap = class
    PRIVATE
    	entry: array[0..4096] of tInt32Color; {entry index (12bit)}
        procedure setSubSection(startPos,endPos: integer;startColor,endColor: tFlt128Color);
    PUBLIC
        function getIndex(x: integer): tInt32Color; overload;
        function getIndex(x: Float): tInt32Color; overload;
        procedure setGradient(startColor,endColor: tFlt128Color);
        procedure setComplexFloat(indx: array of float;col: array of tFlt128Color); overload;
        procedure setComplex(indx: array of integer;col: array of tFlt128Color); overload;
        constructor create;
        destructor destroy; override;
    end;

    tVarType = (vtNONE,vtINT32,vtFLT32,vtFLT64,vtFLT80);

    {fractal data structure with variable data sizes and varaible spacing}
    {data is packed horizontaly (i.e. a1,a2,..an, b1,b2...bn etc)}

    tInt32Array = array[0..65535] of integer;
    tFlt32Array = array[0..65535] of single;
    tFlt64Array = array[0..65535] of double;
    tFlt80Array = array[0..65535] of extended;

    tPackedData = class
	PRIVATE
    	pData: record
	    	case tVarType of
            	vtNone:  (ptr: pointer);
	        	vtINT32: (pInt32: ^tInt32Array);
    	        vtFLT32: (pFlt32: ^tFlt32Array);
        	    vtFLT64: (pFlt64: ^tFlt64Array);
            	vtFLT80: (pFlt80: ^tFlt80Array);
        end;
    	unallignedPdata: pointer;
        varType: tVarType;
        numRecords: integer;
        numVariables: integer;
    PUBLIC
    	procedure setSpacing(aSpacing: integer); {define spacing (i.e. number of records) (all current data is lost)}
        procedure setVarType(aVarType: tVarType); {define variable type (all current data is lost)}
        procedure setRecord(RecordIndex: integer;data: array of extended);
        procedure getRecord(RecordIndex: integer;var data: array of extended);
		function  getValue(RecordIndex,valueIndex: integer): extended; inline;
		procedure setValue(RecordIndex,valueIndex: integer;data: extended); inline;
		function  getInt(RecordIndex,valueIndex: integer): integer; inline;
		procedure setInt(RecordIndex,valueIndex: integer;data: integer); inline;
        procedure clearData;
        function  dataSize: integer; inline;
        function  varSize: integer; inline;
        constructor create;
        destructor destroy; override;
    end;

    {packed data record used for rendering multiple fractal pixels simultaniously}
    {records are stored interleaved i.e. R1.a,R2.a,R3.a... R1.b,R2.b,R3.b this helps}
    {with optermising for horizontal SIMD instructions (e.g. 3dNow and SSE)}

    {fractal data structure: all varaibles are the same width
     	(0)A
        (1)B
        (2)AB
        (3)atX
        (4)atY
        (5)scratch space
        (6)itteration counter 	(int32)
        (7)tag                  (int32)
        (8)c4					(4.0 as constant)
        (9,10,11,12,13,14) 		(scratch space)
        (15)diverged            (long boolean)}

    {fractal procedures will need to:
    	1/ Compute fracal itterations
        2/ Return itterations performed in eax
        3/ Return in the packeddata structure the current state of each pipe
        	*especialy the diverged boolean, and itteration counter
            *other varaibles can be cleared if pipe has divereged
     fractal procedures may
     	1/ Return before the compleation of any/all of the pipes (so they can be restocked)
    }
    tFractalPackedData = class(tPackedData)
        maxIt: integer; {maximum number of itterations to perform}

		{stats data}
        stat: record
			a: int64;
    		b: int64;
			standardDeviation: extended;
        end;

        function isFinished(pipeIndex: integer): boolean;
        procedure markFinished(pipeIndex: integer);

        procedure setItterationsDone(pipeIndex: integer;newValue: integer);

        function getActive(pipeIndex: integer): boolean;
        function getItterationsDone(pipeIndex: integer): integer;
        function getRemainingItterations(pipeIndex: integer): integer;
        function getTag(pipeIndex: integer): integer;

        procedure initilisePipe(pipeIndex: integer;tag: integer;a,b: extended);
        procedure releasePipe(pipeIndex: integer);

        procedure printPipe(pipeIndex: integer;pretext: string = '');

    end;

	tFractal = class
        PRIVATE
        	fMaxItterations: integer;{maximum number of itterations to perform}
            dataMP: tFractalPackedData;{variable packed data used to render fractal pixels}
			procedure assignMPRenderMethod(proc: getValueMPProc;pipes: integer;percision: tVarType;aRenderMethodName: string);
            procedure _setMaxItterations(newValue: integer);
        PRIVATE
            initialValue: integer;  {intial fractal value (used by isTrivial)}
    	PUBLIC
			destinationPage: tPage;	{page to render fractal to (not owned by fractal)}
            colorMap: tColorMap;	{if assigned then is used to convert [0..1] values into colors}
            color: tInt32Color;		{color of fractal if colorMap is not assigned}
            {rendering paremeters}
            autoItterations: boolean;{if true maxItterations is adjusted with scale}
            renderSize: integer;	{size to render fractal (both width and height)}
            scale: extended; 		{scale: 1 = normal, 2 = 2*zoom etc}
            xOffset,yOffset: extended; {offset [0,0] is center}
            aaMethod: integer;		{method for anti aliasing 0=off, 1=fixed, 2=adaptive}
            aaLevel: integer;		{anti aliasing level number of samples taken = sqr(aaLevel)}
            aaRadius: single;		{1 = default; 2 = blury; 0.5=sharp}
            useMipMaps: boolean;	{if true mip maps will be generate, and texture set to Trilinea}
            {renderSubsection; {TODO: implement render subsections for multi threading}
            renderPercision: tVarType; {accuracy used when rendering (call updateRenderProc after changing)}
            renderMethodName: string[255]; {name of render method selected using assignMPrenderMethod}

            pixelOn: integer;  		{progress through progressive render}
            {optimizations}
            ignoreCorners: boolean; {if true only pixels within a circle of diamater "width" will be rendered}
            isTrivial: boolean;     {set to true if all pixels in this fractal are the same}
            {assigned to most efficent fractal generator that meets the given specs}
            getValueMp: getValueMPProc;
            getValueMpPipeCount: integer;	{number of pipes in getValueMP}
            {render pixel data}
            rpd: record
            	x,y: array [0..pixelsAtATime-1] of integer;
			    ax,ay: array [0..pixelsAtATime-1] of extended;
			    values: array [0..pixelsAtATime-1] of integer;
			    extraAx,extraAy: array [0..pixelsAtATime*4-1] of extended;
			    extraValues: array [0..pixelsAtATime*4-1] of integer; {extra samples used in AA}
			    extraSample: array [0..pixelsAtATime-1] of boolean; {if true then generate extra samples for this pixel}
			    accumulatedValues: array [0..pixelsAtATime-1] of float; {used for AA}
			    accumulatedColors: array [0..pixelsAtATime-1] of tFlt128Color; {used for AA}
            end;

			function valueAT(x,y: extended): integer;
            function maskAlphaAT(x,y: extended): byte; {returns alpha value of mask to be used at position}
            procedure valuesAT(x,y: array of extended;var results: array of integer;count: integer);

            function progress: float; {returns how completed the rendering of this fractal is 0=just started 1=finished}

            function renderPixelsNoAA(pixels: integer): integer; {renders at most "pixels" number of pixels in fractal}
            function renderPixelsFixedAA(pixels: integer): integer; {renders at most "pixels" number of pixels in fractal}
            function renderPixelsAdaptiveAA(pixels: integer): integer; {renders at most "pixels" number of pixels in fractal}


            procedure startProgressiveRender; {sets up a progressive render, no pixels are rendered until continueProgressiveRender is called}
            function  continueProgressiveRender(pixels: integer): integer; {renders at most "pixels" number of pixels in fractal}
			procedure nextPixelLocation(out pixX,pixY: integer;out resultX,resultY: extended);
            function  imageSpaceToFractalSpace(atLocation: tVector2d): tVector2d;
            procedure finishProgressiveRender; {renders all remaining pixels in fractal}
			procedure render; 		{renders fractal}

            function valueToColor(value: float): tInt32Color;

            property maxItterations: integer read fMaxItterations write _setMaxItterations;

            {todo: these should not be part of fractal}
            function cpuFeatureAvailable_SSE: boolean;
            function cpuFeatureAvailable_SSE2: boolean;
            function cpuFeatureAvailable_3DNOW: boolean;

            procedure assignRenderPage(aPage: tPage); {assign page to render fractal to}
            procedure updateRenderMethod; virtual; {assignes best render method given (renderPercision and availiable CPU capabilitys)}
            procedure setAAMethod(_aaMethod,_aaLevel: integer;_aaRadius: single = 1);

        	constructor create(aPage: tPage=nil);
            destructor Destroy; override;

    	end;

    tFractalMandelBrot = class(tFractal)
        PUBLIC
        	procedure updateRenderMethod; override; {assignes best render method given (renderPercision and availiable CPU capabilitys)}
    end;

function mandelBrot(x,y: extended;quality: integer = 1000): integer;

const
	stat_insideCycle : comp = 0;
    stat_outsideCycle : comp = 0;

    CANUSE_SSE: boolean = true;
    CANUSE_SSE2: boolean = true;
    CANUSE_3DNOW: boolean = true;


implementation

uses
    uFractalSSE,
    uFractal3DN,
    uFractalPas;

{computes mandelbrot set given location and itterations}
{note: not used by any of the fractals as they have their own optimised versions,
 this is included so that users can query the mandelbrot set without first creating
 a fractal}
function mandelBrot(x,y: extended;quality: integer = 1000): integer;
var
	a1,b1,a2,b2,ax,ay: single;
    lp: integer;
const
	limit = 4;
begin
	{And now for the magic formula!}
    ax := x; ay := y;
    a1:=ax; b1:=ay; lp:=0;
    repeat
        inc(lp);
        a2:=a1*a1-b1*b1+ax;
        b2:=2*a1*b1+ay;
        a1:=a2; b1:=b2;
    until (lp>=quality) or ((a1*a1)+(b1*b1)>limit);
    result := lp;
end;

{generates a random number [0..255] based on 2d cordinates}
function noise2d(seed: integer;wavelength: float; x,y: float;itterations: integer = 1): integer;
begin
	randSeed := seed+trunc(4212+x/wavelength)+trunc(11+y/wavelength)*9251241;
    result := random(256);
    result := random(256);
    result := random(256);
    {perform recursion (if enabled)}
    if itterations > 1 then result := (result+noise2d(seed,waveLength/10,x,y,itterations-1)) div 2;
end;

{generates fractal checker board}
{NIY}
function checker2d(x,y: float;itterations: integer): integer;
var
	toggle: boolean;
    A,B: float;
    lp: integer;
begin
	toggle := true;
    a := 0; b := 10;
    {subdivide x axis}
    for lp := 1 to itterations do begin
    end;

end;

{-----------------------------------------------------------------------------}
{ tPackedData }
{-----------------------------------------------------------------------------}

{define number of Records (all current data is lost)}
procedure tPackedData.setSpacing(aSpacing: integer);
begin
	numRecords := aSpacing;
    clearData;
end;

{define variable type (all current data is lost)}
procedure tPackedData.setVarType(aVarType: tVarType);
begin
	varType := aVarType;
    clearData;
end;

{sets varables in a packed record}
{if length(data) < numVariables then remaining varaibles are filled with 0's}
procedure tPackedData.setRecord(RecordIndex: integer;data: array of extended);
var
	lp: integer;
    value: extended;
begin
    for lp := 0 to numVariables-1 do begin
    	if lp >= length(data) then
        	value := 0
        else
        	value := data[lp];
    	setValue(RecordIndex,lp,value);
    end;
end;

procedure tPackedData.getRecord(RecordIndex: integer;var data: array of extended);
var
	lp: integer;
begin
    for lp := 0 to length(data)-1 do begin
    	data[lp] := getValue(RecordIndex,lp);
    end;
end;

procedure tPackedData.setValue(RecordIndex,valueIndex: integer;data: extended);
var
	index: integer;
begin
	{check parameters}
	if valueIndex > numVariables then exit;
    if RecordIndex > numRecords then exit;
	{find location of this varibles / record }
	index := (RecordIndex)+(valueIndex*NumRecords);
    {write data to memory}
	case varType of
    	vtINT32: pData.pInt32^[index] := trunc(data);
        vtFLT32: pData.pFlt32^[index] := data;
       	vtFLT64: pData.pFlt64^[index] := data;
       	vtFLT80: pData.pFlt80^[index] := data;
    	else;
  	end;
end;

procedure tPackedData.setInt(RecordIndex,valueIndex: integer;data: integer);
var
	index: integer;
begin
	{check parameters}
	if valueIndex > numVariables then exit;
    if RecordIndex > numRecords then exit;
	{find location of this varibles / record }
	index := (RecordIndex)+(valueIndex*NumRecords)*varSize div 4;
    {write data to memory}
	pData.pInt32^[index] := data;
end;

function tPackedData.getValue(RecordIndex,valueIndex: integer): extended;
var
	index: integer;
begin
	{check parameters}
	result := 0;
	if valueIndex > numVariables then exit;
    if RecordIndex > numRecords then exit;
    {}
	index := (RecordIndex)+(valueIndex*NumRecords);
    case varType of
    	vtINT32: result := pData.pInt32^[index];
        vtFLT32: result := pData.pFlt32^[index];
        vtFLT64: result := pData.pFlt64^[index];
        vtFLT80: result := pData.pFlt80^[index];
        else;
    end;
end;

function tPackedData.getInt(RecordIndex,valueIndex: integer): integer;
var
	index: integer;
begin
	{check parameters}
	result := 0;
	if valueIndex > numVariables then exit;
    if RecordIndex > numRecords then exit;
	index := (RecordIndex)+(valueIndex*NumRecords)*varSize div 4;
    result := pData.pInt32^[index];
end;

procedure tPackedData.clearData;
begin
	fillchar(pData.ptr^,64*1024,0);
end;

function tPackedData.dataSize: integer;
begin
	result := varSize * numRecords * numVariables;
end;

function tPackedData.varSize: integer;
begin
	case varType of
	    vtINT32,vtFLT32: result := 4;
        vtFLT64: result := 8;
        vtFLT80: result := 10;
    	else result := 0;
    end;
end;

constructor tPackedData.create;
var
    tmpP: pointer;
begin
	inherited;
    {allocate 64k, reallocate until we land on a 16 byte boundary}
    pData.ptr := nil;
    numVariables := 16;
    getmem(pData.ptr,64*1024+16);
    {allign memory}
    unAllignedPdata := pData.ptr;
    while (dword(pData.ptr) mod 16) <> 0 do inc(dword(pData));
end;


destructor tPackedData.destroy;
begin
	if assigned(unAllignedpData) then begin
		freeMem(unAllignedpData,64*1024+16);
        unAllignedpData:= nil;
        pData.ptr := nil;
    end;
    inherited;
end;

{-----------------------------------------------------------------------------}
{ tFractalPackedData }
{-----------------------------------------------------------------------------}

{returns true if pipe has diverged, or has completed the required amount of itterations}
function tFractalPackedData.isFinished(pipeIndex: integer): boolean;
var
	value: single;
    tmp: integer;
begin
    {check divergiance}
    result := (getInt(pipeIndex,15) <> 0) or (getRemainingItterations(pipeIndex) = 0);
end;

procedure tFractalPackedData.markFinished(pipeIndex: integer);
begin
	{marks pipe as finished}
    setInt(pipeIndex,15,-1);
end;

function tFractalPackedData.getActive(pipeIndex: integer): boolean;
begin
    result := getTag(pipeIndex) <> -1;
end;

function tFractalPackedData.getItterationsDone(pipeIndex: integer): integer;
begin
	result := getInt(pipeIndex,6);
end;

procedure tFractalPackedData.setItterationsDone(pipeIndex: integer;newValue: integer);
begin
	setInt(pipeIndex,6,newValue);
end;

function tFractalPackedData.getRemainingItterations(pipeIndex: integer): integer;
begin
	result := trunc(maxIt-getItterationsDone(pipeIndex));
end;

{initilise pipe, reseting counter and starting parameters at [a,b]}
{tag can be used to identify the pixel this pipe is processing}
procedure tFractalPackedData.initilisePipe(pipeIndex: integer;tag: integer;a,b: extended);
begin
	setValue(pipeIndex,0,a); {a}
	setValue(pipeIndex,1,b); {b}
	setValue(pipeIndex,2,0); {ab}
	setValue(pipeIndex,3,a); {atx}
	setValue(pipeIndex,4,b); {aty}
	setInt(pipeIndex,5,0); {diverged}
	setInt(pipeIndex,6,0); {itterations done}
	setInt(pipeIndex,7,tag); {tag}
	setValue(pipeIndex,8,4.0); {constant (4)}
end;

{makes pipe as avaliable}
{clears parameters so that this pipe will not cause a divergance when processing
 the other pipes}
procedure tFractalPackedData.releasePipe(pipeIndex: integer);
begin
	setValue(pipeIndex,0,0); {a}
	setValue(pipeIndex,1,0); {b}
	setValue(pipeIndex,2,0); {ab}
	setValue(pipeIndex,3,0); {atx}
	setValue(pipeIndex,4,0); {aty}
	setValue(pipeIndex,5,0); {diverged}
	setInt(pipeIndex,6,-1); {itterations done}
	setInt(pipeIndex,7,-1); {tag}
end;

{returns tag number assosiated with this pipe}
function tFractalPackedData.getTag(pipeIndex: integer): integer;
begin
	result := getInt(pipeIndex,7);
end;

{displays pipe information to debuging}
procedure tFractalPackedData.printPipe(pipeIndex: integer;pretext: string = '');
begin
	note(1,preText+
    	'A:'+floatToStr(getValue(pipeIndex,0))+','+
        'B:'+floatToStr(getValue(pipeIndex,1))+','+
        'AB:'+floatToStr(getValue(pipeIndex,2))+','+
        'ATX:'+floatToStr(getValue(pipeIndex,3))+','+
        'ATY:'+floatToStr(getValue(pipeIndex,4))+','+
        'DIV:'+floatToStr(getInt(pipeIndex,5))+','+
        'ITR:'+floatToStr(getInt(pipeIndex,6))+','+
        'TAG:'+floatToStr(getInt(pipeIndex,7))+','+
        'C4:'+floatToStr(getValue(pipeIndex,8))+','+
        'S1:'+floatToStr(getInt(pipeIndex,9))+','+
        'S2:'+floatToStr(getInt(pipeIndex,10))+','+
        'S3:'+floatToStr(getInt(pipeIndex,11))+','+
        'DV2:'+floatToStr(getInt(pipeIndex,15)));
end;

{-----------------------------------------------------------------------------}
{ tColorMap }
{-----------------------------------------------------------------------------}

{returns value at index [0..high(entry)]}
{clamps if out of range}
function tColorMap.getIndex(x: integer): tInt32Color;
begin
	{clamp}
	if x > high(entry) then x := high(entry);
    if x < 0 then x := 0;
	result := entry[x];
end;

{returns value at index [0..1]}
{camps if out of range}
function tColorMap.getIndex(x: Float): tInt32Color;
begin
	{clamp}
    if x < 0 then x := 0;
    if x > 1 then x := 1;
    result := entry[round(x*high(entry))];
end;

procedure tColorMap.setSubSection(startPos,endPos: integer;startColor,endColor: tFlt128Color);
var
	lp: integer;
    c: tFlt128Color;
begin
	if startPos < 0 then startPos := 0;
	if endPos > high(entry) then endPos := high(entry);
	assert(startPos <= endPos);
	for lp := startPos to endPos do begin
    	c := colorMix(startColor,endColor,(lp-startPos)/(endPos-StartPos+1));
    	entry[lp].setRGB(c.r,c.g,c.b);
    end;
end;

{produces a smooth gradient from start to finish}
procedure tColorMap.setGradient(startColor,endColor: tFlt128Color);
begin
	setSubSection(0,high(entry),startColor,endColor);
end;

procedure tColorMap.setComplexFloat(indx: array of float;col: array of tFlt128Color);
var
	lp: integer;
begin
	assert(length(indx) = length(col));
	assert(length(indx) >= 2);
	for lp := 0 to length(indx)-2 do
        setSubSection(round(indx[lp]*high(entry)),round(indx[lp+1]*high(entry)),col[lp],col[lp+1]);
end;

procedure tColorMap.setComplex(indx: array of integer;col: array of tFlt128Color);
var
	lp: integer;
begin
	assert(length(indx) = length(col));
	assert(length(indx) >= 2);
	for lp := 0 to length(indx)-2 do
        setSubSection(indx[lp],indx[lp+1],col[lp],col[lp+1]);
end;

constructor tColorMap.create;
begin
	inherited create;
	setGradient(rgb(0.0,0.0,0.0),rgb(255.0,255.0,255.0));
end;

destructor tColorMap.destroy;
begin
	inherited destroy;
end;

{-----------------------------------------------------------------------------}
{ tFractal }
{-----------------------------------------------------------------------------}

{completes all remaining pipes}
{currently just uses a very slow pascal routine}
{not used at the moment}
procedure completePipes(dataSP,dataMP: tFractalPackedData);
var
	lp: integer;
    itCounter: integer;
    a,b,ab,atX,atY: single;
    indx: integer;
    c: single;
begin
	{look for unfinished pipes}
	for lp := 0 to dataMP.numRecords-1 do if dataMP.getActive(lp) and (not dataMP.isFinished(lp)) then begin
    	{start from where we left off}
        itCounter := dataMP.getItterationsDone(lp);
        a := dataMP.getValue(lp,0);
        b := dataMP.getValue(lp,1);
        ab := dataMP.getValue(lp,2);
        atX := dataMP.getValue(lp,3);
        atY := dataMP.getValue(lp,4);
        c := dataMP.getValue(lp,8);
        repeat
        	inc(itCounter);
	        ab := a*b;a := a*a;b := b*b;
	        if (a+b > c) then break;
	        a := a - b + atX;b := ab + ab + atY;
        until (itCounter>=dataMP.MaxIt);
        {mark as completed}
        dataMP.setItterationsDone(lp,itCounter);
        dataMP.markFinished(lp);
    end;
end;

{renders "pixel" number of pixels to destination page}
{any excess pixels will be ignored}
{if progressive render is fininish then function will exit and return zero}
{note: "pixels" parameter is only used as a guidline, this procedure will
 currently process pixels only blocks of 64 (i.e. passing 100 will render 128 pixels)}
{returns number of pixels actualy processed}
function tFractal.continueProgressiveRender(pixels: integer): integer;
begin
	result := 0;
    try
    	case aaMethod of
        	0: result := renderPixelsNoAA(pixels);
            1: result := renderPixelsAdaptiveAA(pixels);
            2: result := renderPixelsFixedAA(pixels);
            else warning(1,'Invalid AA method "'+intToStr(aaMethod)+'"');
        end;
    except
        warning(1,'Error on fractal render!');
    end;
end;

{finds fractal coordintates from image coordinates}
function tFractal.imageSpaceToFractalSpace(atLocation: tVector2d): tVector2d;
begin
    result.X:=xOffset+atLocation.x/(scale*renderSize);
    result.Y:=yOffset+atLocation.y/(scale*renderSize);
end;

{pixX,pixY are pixel locations on the screen,
 resultX,resultY: represent the next fractal location to render a pixel at
 if "ignorecorners" is enabled then the edges of the page will not be rendered}
procedure tFractal.nextPixelLocation(out pixX,pixY: integer;out resultX,resultY: extended);
var
    pos: tVector2d;
begin
	{if ignore edges is enabled then keep calculating pixel positions until one is in bounds}
	repeat
		{calculate position of pixel}
	    pixX := (pixelOn) mod renderSize-renderSize div 2;
	    pixY := (pixelOn) div renderSize-renderSize div 2;
	    {move to next pixel}
	    inc(pixelOn);
	until (not ignoreCorners) or (pixelOn >= renderSize*renderSize) or (sqrt(sqr(pixX)+sqr(pixY))<(renderSize/2));
    {find position in fractal space}
    pos := vec(pixX,pixY);
    pos := imageSpaceToFractalSpace(pos);
    resultX := pos.x;
    resultY := pos.y;
end;

{renders "pixels" number without AA}
function tFractal.RenderPixelsNoAA(pixels: integer): integer;
var
	x,y: array [0..pixelsAtATime-1] of integer;
    pixelLP,lp: integer;
    ax,ay: array [0..pixelsAtATime-1] of extended;
    values: array [0..pixelsAtATime-1] of integer;
    dst: integer;
    smallValue: integer;
    baseColor,fractalColor: tInt32Color;
begin
	result := 0;
	if not assigned(destinationPage) then exit;
    assert(maxItterations > 0);
    if scale = 0 then exit;
    if pixels < 0 then exit;
    if pixelOn >= sqr(renderSize) then exit;

    for pixelLp := 1 to (pixels div pixelsAtATime) do begin
       	{calculate position of next group of pixels}
        for lp := 0 to pixelsAtATime-1 do nextPixelLocation(x[lp],y[lp],ax[lp],ay[lp]);
        {calculate value of pixel array}
        valuesAt(ax,ay,values,length(ax));
		{calculate color of these pixels}
		for lp := 0 to pixelsAtATime-1 do begin
            if isTrivial then isTrivial := (values[lp] = initialValue);
	    	{calculate color of pixel}
	        fractalColor := valueToColor(values[lp]/maxItterations);

            fractalColor.a := maskAlphaAt(x[lp],y[lp]);

    	    destinationPage.putPixel(x[lp]+renderSize div 2,y[lp]+renderSize div 2,FractalColor);
        	inc(result);
	    end;

	    if pixelOn >= (renderSize*renderSize) then begin
        	break;
	    end;
   	end;
end;

{renders "pixels" number of pixels using a fixed AA method}
{note: can be very slow at high AA levels}
function tFractal.RenderPixelsFixedAA(pixels: integer): integer;
var
	x,y: array [0..pixelsAtATime-1] of integer;
    pixelLP,lp: integer;
    ax,ay: array [0..pixelsAtATime-1] of extended;
    baseAx,baseAy: array [0..pixelsAtATime-1] of extended;
    values: array [0..pixelsAtATime-1] of integer;
	sampleOffsetX,sampleOffsetY: extended; {sample offset adjustment (used for AA)}
    accumulatedValues: array [0..pixelsAtATime-1] of integer; {used for AA}
    accumulatedColors: array [0..pixelsAtATime-1] of tFlt128Color; {used for AA}
    sampleLoop: integer; {used for AA}
    dst: integer;
    smallValue: integer;
    baseColor,fractalColor: tInt32Color;
    oldPixelOn: integer;
begin
	result := 0;
	if not assigned(destinationPage) then exit;
    assert(maxItterations > 0);
    if scale = 0 then exit;
    if pixels < 0 then exit;
    if pixelOn >= sqr(renderSize) then exit;

    for pixelLp := 1 to (pixels div pixelsAtATime) do begin
    	{clear accululation buffer}
    	for lp := 0 to pixelsAtATime-1 do begin
            accumulatedValues[lp] := 0;
            accumulatedColors[lp] := flt128Color(0,0,0);
        end;
        {generate fractal co-ords}
        for lp := 0 to pixelsAtATime-1 do nextPixelLocation(x[lp],y[lp],baseAX[lp],baseAY[lp]);
        {sample points}
    	for sampleLoop := 0 to (aaLevel*aaLevel)-1 do begin
        	{calculate sample offsets}
            sampleOffsetX := (((sampleLoop) mod aaLevel)/aaLevel)*(aaRadius/(scale*renderSize));
            sampleOffsetY := (((sampleLoop) div aaLevel)/aaLevel)*(aaRadius/(scale*renderSize));
            {adjust fractal co-ords}
	        for lp := 0 to pixelsAtATime-1 do begin
    	        ax[lp] := baseAX[lp] + sampleOffsetX;
        	    ay[lp] := baseAY[lp] + sampleOffsetY;
	        end;
	        {calculate value of pixel array}
	        valuesAt(ax,ay,values,length(ax));
	        {add this sample to other samples}
	        for lp := 0 to pixelsAtATime-1 do begin
	        	accumulatedValues[lp] := accumulatedValues[lp] + values[lp];
                accumulatedColors[lp] := colorAdd(accumulatedColors[lp],flt128Color(valueToColor(values[lp]/maxItterations)));
	        end;
		end;
        {calculate samples values}
        for lp := 0 to pixelsAtATime-1 do begin
        	values[lp] := accumulatedValues[lp] div (aaLevel*aaLevel);
        end;
        {calculate color of these pixels}
    	for lp := 0 to pixelsAtATime-1 do begin
            if isTrivial then isTrivial := (values[lp] = initialValue);
        	{calculate color of pixel}
            fractalColor := int32Color(colorMix(accumulatedColors[lp],flt128Color(0,0,0),1-(1/(aaLevel*aaLevel))));
			{find alpha}
            fractalColor.a := maskAlphaAt(x[lp],y[lp]);
            {place pixel}
            destinationPage.putPixel(x[lp]+renderSize div 2-1,y[lp]+renderSize div 2-1,FractalColor);
            inc(result);
        end;
        if pixelOn >= (renderSize*renderSize) then begin
			break;
        end;
	end;
end;

{renders "pixels" number of pixels using a fixed AA method}
{note: can be very slow at high AA levels}
function tFractal.RenderPixelsAdaptiveAA(pixels: integer): integer;
var
	extraSampleOn: integer;
    extraCount: integer;
    pixelLP,lp: integer;
    sampleOffsetX,sampleOffsetY: extended; {sample offset adjustment (used for AA)}

    sampleLoop: integer; {used for AA}
	dst: integer;
    smallValue: integer;
    delta: single;
    baseColor,fractalColor: tInt32Color;

{adds AA sample, xofs,yofs = [0..aaLevel-1]}
procedure addSample(index: integer;xofs,yofs: extended);
begin
	rpd.extraSample[index] := true;
    rpd.extraAx[extraCount] := rpd.ax[index] + xofs*(aaRadius/(scale*renderSize));
    rpd.extraAy[extraCount] := rpd.ay[index] + yofs*(aaRadius/(scale*renderSize));
    inc(extraCount);
end;

begin
	result := 0;
	if not assigned(destinationPage) then exit;
    assert(maxItterations > 0);
    if scale = 0 then exit;
    if pixels < 0 then exit;
    if pixelOn >= sqr(renderSize) then exit;

    for pixelLp := 1 to (pixels div pixelsAtATime) do begin
    	{calculate position of next group of pixels}
        for lp := 0 to pixelsAtATime-1 do nextPixelLocation(rpd.x[lp],rpd.y[lp],rpd.ax[lp],rpd.ay[lp]);
	    {calculate value of pixel array}
        valuesAt(rpd.ax,rpd.ay,rpd.values,length(rpd.ax));
		{calculate color of these pixels}
		for lp := 0 to pixelsAtATime-1 do begin
            if isTrivial then isTrivial := (rpd.values[lp] = initialValue);
    	    rpd.accumulatedColors[lp] := flt128Color(valueToColor(rpd.values[lp]/maxItterations));
	    end;
        {clear extra samples}
        extraCount := 0;
        fillchar(rpd.extraSample,sizeof(rpd.extraSample),0);
	    {for each result that look like it needs some extra samples generate x number of samples and modify}
		for lp := 0 to pixelsAtATime-1 do begin
	    	{calculate delta between this pixel and the last one}
            if lp = 0 then
            	delta := 0
            else
            	delta := sqrt(
            		sqr(rpd.accumulatedColors[lp].r-rpd.accumulatedColors[lp-1].r)+
	                sqr(rpd.accumulatedColors[lp].g-rpd.accumulatedColors[lp-1].g)+
	                sqr(rpd.accumulatedColors[lp].b-rpd.accumulatedColors[lp-1].b));
            if delta > 100{aaThreshold} then begin
            	{this pixel needs some extra samples}
                addSample(lp,0/2,1/2);
                addSample(lp,1/2,1/2);
                addSample(lp,1/2,0/2);
            end;
	    end;
        {process extra samples}
        valuesAt(rpd.extraAx,rpd.extraAy,rpd.extraValues,extraCount);
        {apply samples to data}
        extraSampleOn := 0;
        for lp := 0 to pixelsAtATime-1 do begin
        	if rpd.extraSample[lp] then begin
        		rpd.accumulatedColors[lp] := colorAdd(rpd.accumulatedColors[lp],flt128Color(valueToColor(rpd.extraValues[extraSampleOn]/maxItterations)));
	            inc(extraSampleOn);
	            rpd.accumulatedColors[lp] := colorAdd(rpd.accumulatedColors[lp],flt128Color(valueToColor(rpd.extraValues[extraSampleOn]/maxItterations)));
	            inc(extraSampleOn);
	            rpd.accumulatedColors[lp] := colorAdd(rpd.accumulatedColors[lp],flt128Color(valueToColor(rpd.extraValues[extraSampleOn]/maxItterations)));
	            inc(extraSampleOn);
        		fractalColor := int32Color(colorMix(flt128Color(0,0,0),rpd.accumulatedColors[lp],1/4));
                if false then
                	fractalColor := rgb(255,0,255);
            end else
            	fractalColor := int32Color(rpd.accumulatedColors[lp]);
            fractalColor.a := maskAlphaAt(rpd.x[lp],rpd.y[lp]);
    	    destinationPage.putPixel(rpd.x[lp]+renderSize div 2-1,rpd.y[lp]+renderSize div 2-1,FractalColor);
        	inc(result);
        end;
        {update texture if needed}
        if pixelOn >= (renderSize*renderSize) then begin
			break;
        end;

	end;
end;

{returns value of fractal at given location}
{use the valuesAt procedure when ever possable, as it can be much quicker}
function tFractal.valueAT(x,y: extended): integer;
begin
	{we call the MP version with only 1 pipe filled}
    {this is very enefficent, but this procedure is not used often anyway}
    valuesAt([x],[y],result,1);
end;

function tFractal.maskAlphaAt(x,y: extended): byte;
var
	dst: integer;
begin
    if USE_ALPHA_MASK then begin
    	dst := round(sqrt(sqr(x)+sqr(y))/(renderSize/2)*256);
        dst := (256-dst)*8;
        if dst < 0 then dst := 0; if dst > 255 then dst := 255;
        result := dst;
    end else result := 255;
end;


{calculates multiple fractal values at given positions}
{ignore any anti aliasing options}
{can be faster than calling valueAT many times as there is potential for this routine
 to be pipelined}
procedure tFractal.valuesAT(x,y: array of extended;var results: array of integer;count: integer);
var
	lp,pixelOn: integer;
    tmp: integer;
    activePipes: integer;
    maxItterationsThisRound: integer;
begin
	{check parameters}
    if count <= 0 then exit;
    assert(assigned(self));
    assert(assigned(dataMP));
    assert(length(x)>=count);
	assert(length(y)>=count);
    assert(length(results)>=count);
	{setup for loop}
    pixelOn := 0;
    activePipes := 0;
    for lp := 0 to getValueMpPipeCount-1 do dataMP.releasePipe(lp);
    {process pixels}
    while True do begin
    	{fill empty pipes}
        if activePipes < getValueMpPipeCount then for lp := 0 to getValueMpPipeCount-1 do if not(dataMP.getActive(lp)) and (pixelOn < count) then begin
        	dataMP.initilisePipe(lp,pixelOn,x[pixelOn],y[pixelOn]);
            inc(activePipes);
            inc(pixelOn);
        end;

        {stop when all pipes are completed}
        if (activePipes <= 0) then break;

		{calculate maximum number of itterations to perform}
        maxItterationsThisRound := maxItterations;
	    for lp := 0 to dataMP.numRecords-1 do
            if dataMP.getActive(lp)
                and (dataMP.getRemainingItterations(lp) < maxItterationsThisRound) then
            		maxItterationsThisRound := dataMP.getRemainingItterations(lp);
		{makes sure there is atleast 1 pipe to process}
		assert(maxItterationsThisRound > 0);
        {setup parameters for processing}
	    dataMP.setInt(2,10,maxItterationsThisRound);
    	{process all pipelines}
    	getValueMp(dataMP);
        {find which pipe(s) have completed and tag}
        for lp := 0 to getValueMpPipeCount-1 do if dataMP.getActive(lp) and dataMP.isFinished(lp) then begin
        	results[dataMP.getTag(lp)] := dataMP.getItterationsDone(lp);
            {free up pipe}
        	dataMP.releasePipe(lp);
            dec(activePipes);
        end;
    end;
end;


function tFractal.progress: float;
begin
	result := pixelOn/(renderSize*renderSize)
end;

procedure tFractal.startProgressiveRender;
var
	newItterations: integer;
    xx,yy: integer;
    fx,fy: extended;
begin
	{auto quality update}
    if autoItterations then begin
	    newItterations := round(maxItterations*0.4)+round((maxItterations/32)*log2(scale));
	    dataMP.maxIt := newItterations;
	    Note(1,'auto quality ='+comma(newItterations));
    end;
	pixelOn := 0;
    isTrivial := true;
    {find first pixel color}
    nextPixelLocation(xx,yy,fx,fy);
    initialValue := valueAt(fx,fy);
    pixelOn := 0;   {and reset back to pixel 0 again}

end;

{finished remaining pixels in render}
procedure tFractal.finishProgressiveRender;
begin
	continueProgressiveRender((renderSize*renderSize)-pixelOn);
end;

{fills page with selected fractal}
procedure tFractal.render;
begin
    startProgressiveRender;
    finishProgressiveRender;
end;

{private property procedure}
procedure tFractal._setMaxItterations(newValue: integer);
begin
	assert(assigned(dataMP));
	dataMP.maxIt := newValue;
    fMaxItterations := newValue;
end;

{assigned given procedure as the current render procedure}
procedure tFractal.assignMPRenderMethod(proc: getValueMPProc;pipes: integer;percision: tVarType;aRenderMethodName: string);
begin
    getValueMp := proc;
    getValueMpPipeCount := pipes;
    {adjust packing, and percision of data structure}
    dataMP.setSpacing(pipes);
    dataMP.setVarType(percision);
    renderMethodName := aRenderMethodName;
end;

{returns true of cpu feature is available, (if disabled with CANUSE_SSE then returns false}
function tFractal.cpuFeatureAvailable_SSE: boolean;
begin
    result := cpuHas_SSE and CANUSE_SSE;
end;

function tFractal.cpuFeatureAvailable_SSE2: boolean;
begin
    result := cpuHas_SSE2 and CANUSE_SSE2;
end;

function tFractal.cpuFeatureAvailable_3DNOW: boolean;
begin
    result := cpuHas_3DNOW and CANUSE_3DNOW;
end;

{assign page to render fractal to}
procedure tFractal.assignRenderPage(aPage: tPage);
begin
    assert(assigned(aPage));
    destinationPage := aPage;
end;

{assigns best render method given renderPercision and availiable CPU exentions}
procedure tFractal.updateRenderMethod;
begin
	{base fractal has no rendering methods}
	assignMPRenderMethod(nil,0,vtNONE,'Not Assigned');
end;

procedure tFractal.setAAMethod(_aaMethod,_aaLevel: integer;_aaRadius: single = 1);
begin
	assert(aaMethod in [0,1,2]);
	aaMethod := _aaMethod;
	aaLevel := _aaLevel;
	aaRadius := _aaRadius;
end;

{maps value [0..1] to color based on currently selected gradient}
function tFractal.valueToColor(value: float): tInt32Color;
begin
	{clamp value}
    if value < 0 then value := 0;
    if value > 1 then value := 1;
    {apply gradient}
    if assigned(colorMap) then
    	result := colorMap.getIndex(value)
    else
    	result := rgbInt32(round(value*color.r),round(value*color.g),round(value*color.b));
end;

{creates a fractal object.  aPage is a page to render to.  This can be nil at
 the creation stage but must be assigned before any rendering can happen}
constructor tFractal.create(aPage: tPage=nil);
begin
	inherited create;

    {disable corner cutting}
    ignoreCorners := false;

    {disable mip maps by default}
    useMipMaps := false;

    {create packed data array}
	dataMP := tFractalPackedData.create;

    {set no color map as default}
    colorMap := nil;
	color := rgb(255,255,128);

    {disable anti aliasing}
    aaMethod := amNone;
	aaLevel := 2;

    {setup values}
    if assigned(aPage) then
    begin
        assignRenderPage(aPage);
        renderSize := aPage.width;
    end
    else
        {take a guess at render size... this will have to be assigned later}
        renderSize := 128;

    renderPercision := vtFlt32;
    maxItterations := 1024;
    autoItterations := false;
	pixelOn := 0;
    scale := 1; xoffset := 0; yoffset := 0;
    isTrivial := true;

    {select best render method for default settings}
    updateRenderMethod;
end;

destructor tFractal.Destroy;
begin
    {page is not owned by fractal so do not free}
    {free objects}
    dataMP.Free;
end;

{-----------------------------------------------------------------------------}
{ tFractalMandelBrot }
{-----------------------------------------------------------------------------}

{assigns best render method given renderPercision and availiable CPU exentions}
{also packs data array to correct width and percision}
procedure tFractalMandelBrot.updateRenderMethod;
var
	ret: boolean;
begin
	assignMPRenderMethod(nil,0,vtNONE,'Not Assigned');

	case renderPercision of
    	vtFLT32: begin
        	{assign default procedures}
            assignMpRenderMethod(_PAS_FG_MND_FLOAT32_4P,4,vtFLT32,'FLT32 FPU');
            {try to upgrade to 3DNow! procs}
            if cpuFeatureAvailable_3DNOW then
                assignMpRenderMethod(_ASM_FG_MND_FLOAT32_4P_3DN,4,vtFLT32,'FLT32 3DN');
            {try to upgrade to SSE procs}
            if cpuFeatureAvailable_SSE then
                assignMpRenderMethod(_ASM_FG_MND_FLOAT32_8P_SSE,8,vtFLT32,'FLT32 SSE');
        end;
    	vtFLT64: begin
            assignMpRenderMethod(_PAS_FG_MND_FLOAT64_4P,4,vtFLT64,'FLT64 FPU');
            if cpuFeatureAvailable_SSE2 then
                assignMpRenderMethod(_ASM_FG_MND_FLOAT64_4P_SSE2,4,vtFLT64,'FLT64 SSE2');
        end;
    	vtFLT80:
            assignMpRenderMethod(_PAS_FG_MND_FLOAT80_4P,4,vtFLT80,'FLT80 FPU');
        else begin
        	warning(1,'Selected Percision is not supported by this fractal generator');
        end;
    end;
end;

end.

